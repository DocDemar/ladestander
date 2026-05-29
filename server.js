require('dotenv').config();
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');
const { Pool } = require('pg');

const PORT = 8080;
const POSTGREST_HOST = 'localhost';
const POSTGREST_PORT = 3002;

const MIME = { '.html': 'text/html', '.json': 'application/json', '.ico': 'image/x-icon', '.js': 'application/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };

// ── Monta status — baggrundspoll, skriver til DB ───────────────────────────────
// Status hentes fra Monta AFIR API med jævne mellemrum og gemmes i
// charging_evses.availability_status. bbox-funktionen i PostGIS returnerer derefter
// status direkte fra DB — ingen live Monta-kald ved kortvisning.

const db = new Pool({ connectionString: process.env.DATABASE_URL });

// Monta throttler samtidige forbindelser — kør én request pr. credential ad gangen
// 4 workers (en pr. credential) × ~2.5s/request = ~1.6 req/s
// 3569 EWII+Apcoa EVSEs ã ~37 min · 13369 EVSEs total ã ~2.3 timer
const POLL_CONCURRENCY_PRIORITY = 4; // én worker pr. credential
const POLL_CONCURRENCY_SLOW     = 4; // samme for baggrunden
const POLL_DELAY_MS             = 0;  // ingen kunstig delay — responstiden er rate-limiteren
const ROUND_MIN_MS      = 30 * 60 * 1000; // 30 min pause mellem runder
const REQUEST_TIMEOUT_MS = 8_000;         // 8s — endpoint svarer typisk på 2-3s

// 4 credential-sæt — roteres på tværs af workers for at fordele API-load
const MONTA_CREDENTIALS = [
  { clientId: '3887eed3-33ee-4f09-8c64-546e826c9b14', clientSecret: '8fd10e3b-c286-4ca7-92e1-900c4de2ab3f' },
  { clientId: 'c6f4e737-9d35-49af-8948-4d15da27930d', clientSecret: 'd7db4c38-3693-441e-8703-f713b27e88f6' },
  { clientId: '0a177f7f-5186-408f-9bcf-0b88077bd3be', clientSecret: 'bcdc8cdb-f270-4ce0-83c4-40482f6f0269' },
  { clientId: '1db8bb1e-8780-423d-8c37-932ff22f8fc4', clientSecret: '01e664cc-a3d9-48b0-83ea-b96982fbcfce' },
];
const _tokenCache  = new Array(MONTA_CREDENTIALS.length).fill(null);
const _tokenExpiry = new Array(MONTA_CREDENTIALS.length).fill(0);
let lastPollTs = 0;
let _pollRunning = false;

function httpsRequest(options, body) {
  let req;
  const request = new Promise((resolve, reject) => {
    req = https.request(options, (res) => {
      let buf = '';
      res.on('data', c => buf += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(buf) }); }
        catch { resolve({ status: res.statusCode, body: buf }); }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
  const timeout = new Promise((_, reject) =>
    setTimeout(() => { try { req?.destroy(); } catch { /* ignore */ } reject(new Error('request timeout')); }, REQUEST_TIMEOUT_MS)
  );
  return Promise.race([request, timeout]);
}

async function getMontaToken(credIndex) {
  if (_tokenCache[credIndex] && Date.now() < _tokenExpiry[credIndex]) return _tokenCache[credIndex];
  const { clientId, clientSecret } = MONTA_CREDENTIALS[credIndex];
  const data = JSON.stringify({ clientId, clientSecret });
  const res = await httpsRequest({
    hostname: 'public-api.monta.com',
    path: '/api/v1/auth/token',
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
  }, data);
  if (!res.body.accessToken) throw new Error(`Token-fejl for credential ${credIndex}: ${JSON.stringify(res.body)}`);
  _tokenCache[credIndex]  = res.body.accessToken;
  _tokenExpiry[credIndex] = Date.now() + 55 * 60 * 1000;
  console.log(`[poll] Token hentet for credential ${credIndex}`);
  return _tokenCache[credIndex];
}

async function pollMontaStatuses() {
  if (_pollRunning) return;
  _pollRunning = true;
  const roundStart = Date.now();
  try {
    // Hent tokens for alle 4 credentials parallelt
    const tokens = await Promise.all(MONTA_CREDENTIALS.map((_, i) => getMontaToken(i)));

    // Prioritets-kø: EWII + Apcoa (kendte respondenter) — hurtig poll
    const { rows: priRows } = await db.query(`
      SELECT e.external_id AS evse_id FROM charging_evses e
      JOIN charging_sites s ON s.id = e.site_id
      WHERE e.source = 'monta'
        AND e.evse_id IS NOT NULL
        AND s.operator_name IN ('EWII', 'Apcoa Parking Danmark A/S')
      ORDER BY e.evse_id`);

    // Baggrunds-kø: alle andre Monta-EVSEs — langsom poll
    const { rows: slowRows } = await db.query(`
      SELECT e.external_id AS evse_id FROM charging_evses e
      JOIN charging_sites s ON s.id = e.site_id
      WHERE e.source = 'monta'
        AND e.evse_id IS NOT NULL
        AND s.operator_name NOT IN ('EWII', 'Apcoa Parking Danmark A/S')
      ORDER BY e.last_seen_at DESC NULLS LAST, e.evse_id`);

    console.log(`[poll] Prioritet: ${priRows.length} EVSEs (EWII+Apcoa) · Baggrund: ${slowRows.length} EVSEs`);
    let updated = 0, recorded = 0, skipped = 0;

    async function fetchStatus(evseId, token, delay) {
      if (delay) await new Promise(r => setTimeout(r, POLL_DELAY_MS));
      try {
        const res = await httpsRequest({
          hostname: 'public-api.monta.com',
          path: '/api/v1/afir/charge-points/' + encodeURIComponent(evseId) + '/status',
          method: 'GET',
          headers: { Authorization: 'Bearer ' + token },
        });
        if (res.status === 200) {
          const status = res.body?.electricChargingPointStatus?.availabilityStatus ?? null;
          if (status) {
            await db.query(
              `UPDATE charging_evses SET availability_status=$1, last_status_updated=NOW(), last_seen_at=NOW() WHERE source='monta' AND external_id=$2`,
              [status, evseId]
            );
            await db.query('INSERT INTO evse_status_history (evse_id, status, source) VALUES ($1,$2,$3)', [evseId, status, 'monta']);
            updated++; recorded++;
            return true;
          }
        }
      } catch { /* timeout / netfejl */ }
      skipped++;
      return false;
    }

    // --- Prioritets-poll (hurtig) ---
    const priQueue = [...priRows.map(r => r.evse_id)];
    async function priWorker(i) {
      const token = tokens[i % tokens.length];
      while (priQueue.length > 0) await fetchStatus(priQueue.shift(), token, false);
    }
    await Promise.all(Array.from({ length: POLL_CONCURRENCY_PRIORITY }, (_, i) => priWorker(i)));
    console.log(`[poll] Prioritet færdig — ${updated} opdateret, ${skipped} sprunget over`);
    const priDone = updated;
    lastPollTs = Date.now(); // markér klar selv hvis baggrunden ikke er færdig

    // --- Baggrunds-poll (langsom) ---
    const slowQueue = [...slowRows.map(r => r.evse_id)];
    let slowUpdated = 0, slowSkipped = 0;
    async function slowWorker(i) {
      const token = tokens[i % tokens.length];
      while (slowQueue.length > 0) {
        const ok = await fetchStatus(slowQueue.shift(), token, true);
        if (ok) slowUpdated++; else slowSkipped++;
        if ((slowUpdated + slowSkipped) % 500 === 0)
          console.log(`[poll] Baggrund: ${slowUpdated + slowSkipped}/${slowRows.length} behandlet, ${slowUpdated} nye svar`);
      }
    }
    await Promise.all(Array.from({ length: POLL_CONCURRENCY_SLOW }, (_, i) => slowWorker(i)));

    lastPollTs = Date.now();
    const elapsed = Math.round((lastPollTs - roundStart) / 1000);
    console.log(`[poll] Færdig — ${recorded} historikpunkter gemt, ${updated} aktuelle opdateret, ${skipped} sprunget over — runde tog ${elapsed}s`);
  } catch (err) {
    console.error('[poll] Fejl:', err.message ?? err);
  } finally {
    _pollRunning = false;
  }
}

async function pollLoop() {
  while (true) {
    const start = Date.now();
    await pollMontaStatuses();
    const elapsed = Date.now() - start;
    const wait = Math.max(0, ROUND_MIN_MS - elapsed);
    if (wait > 0) {
      console.log(`[poll] Næste runde om ${Math.round(wait / 60000)} min`);
      await new Promise(resolve => setTimeout(resolve, wait));
    }
  }
}

async function cleanupHistory() {
  try {
    const { rowCount } = await db.query(
      "DELETE FROM evse_status_history WHERE recorded_at < NOW() - INTERVAL '30 days'"
    );
    if (rowCount > 0) console.log(`[cleanup] Slettede ${rowCount} historikrækker ældre end 30 dage`);
  } catch (err) {
    console.error('[cleanup] Fejl:', err.message ?? err);
  }
}

// ── PostgREST proxy ────────────────────────────────────────────────────────────

async function proxyPostgREST(req, res) {
  const parsed = url.parse(req.url, true);

  // Strip cache-busting _ param that Widget3/jQuery adds
  const query = Object.assign({}, parsed.query);
  delete query._;

  const qs = Object.keys(query).length ? '?' + new URLSearchParams(query).toString() : '';
  const targetPath = parsed.pathname.replace('/api', '') + qs;

  const options = {
    hostname: POSTGREST_HOST,
    port: POSTGREST_PORT,
    path: targetPath,
    method: req.method,
    headers: { Accept: 'application/json' }
  };

  // Fetch from PostgREST
  const body = await new Promise((resolve, reject) => {
    const pgReq = http.request(options, (pgRes) => {
      if (pgRes.statusCode !== 200) {
        let err = '';
        pgRes.on('data', c => err += c);
        pgRes.on('end', () => reject({ status: pgRes.statusCode, body: err }));
        return;
      }
      let buf = '';
      pgRes.on('data', c => buf += c);
      pgRes.on('end', () => resolve(buf));
    });
    pgReq.on('error', reject);
    pgReq.end();
  }).catch(e => {
    if (e.status) { res.writeHead(e.status, { 'Content-Type': 'application/json' }); res.end(e.body); }
    else { res.writeHead(502); res.end('Bad Gateway'); }
    return null;
  });

  if (body === null) return;

  // Convert JSON array → GeoJSON FeatureCollection
  const items = JSON.parse(body);
  const features = items.map(item => {
    const { coordinates, ...properties } = item;
    return { type: 'Feature', geometry: coordinates, properties };
  });

  const geojson = {
    type: 'FeatureCollection',
    crs: { type: 'name', properties: { name: 'urn:ogc:def:crs:EPSG::4326' } },
    features,
  };

  res.writeHead(200, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-cache'
  });
  res.end(JSON.stringify(geojson));
}

const server = http.createServer((req, res) => {
  // Tidspunkt for seneste status-poll — klienten kan bruge dette til at reload
  if (req.url === '/api/status-ready' || req.url.startsWith('/api/status-ready?')) {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-cache' });
    res.end(JSON.stringify({ ready: lastPollTs > 0, ts: lastPollTs, polling: _pollRunning }));
    return;
  }

  // API proxy
  if (req.url.startsWith('/api/')) {
    proxyPostgREST(req, res).catch(err => {
      console.error('[proxy] Uventet fejl:', err.message ?? err);
      if (!res.headersSent) { res.writeHead(500); res.end('Internal Server Error'); }
    });
    return;
  }

  // Static files from public/
  const pathname = url.parse(req.url).pathname;
  const filePath = path.join(__dirname, 'public', pathname === '/' ? 'ladestander.html' : pathname);
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'text/plain' });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`Serving on http://localhost:${PORT}/ladestander.html`);
  // Kør kontinuerlig Monta-poll-loop (runde → vent → runde → ...)
  pollLoop().catch(err => console.error('[pollLoop] Fatal fejl:', err.message ?? err));
  // Daglig oprydning af historikrækker ældre end 30 dage
  cleanupHistory();
  setInterval(cleanupHistory, 24 * 60 * 60 * 1000);
});
