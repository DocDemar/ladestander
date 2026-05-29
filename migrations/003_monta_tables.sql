-- =============================================================================
-- Monta AFIR-tabeller (statiske data fra Monta Partner API)
-- =============================================================================
-- Kør efter 001_init.sql og 002_api_schema.sql
-- Eksempel: psql -d ladestander -f migrations/003_monta_tables.sql
-- =============================================================================

-- Ladestander-lokationer fra Monta AFIR-endpoint
CREATE TABLE IF NOT EXISTS monta_sites (
  id              TEXT PRIMARY KEY,          -- site-195706
  name            TEXT,
  address         TEXT,
  city            TEXT,
  postal_code     TEXT,
  country         TEXT DEFAULT 'DK',
  coordinates     GEOMETRY(Point, 4326),
  operator_name   TEXT,
  opening_times   JSONB,
  synced_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_monta_sites_coordinates
  ON monta_sites USING GIST (coordinates);

CREATE INDEX IF NOT EXISTS idx_monta_sites_operator
  ON monta_sites (operator_name);

-- EVSEs (refillPoints) fra Monta AFIR-endpoint
-- Connectors gemmes som JSONB-array (typisk 1 connector pr. EVSE)
CREATE TABLE IF NOT EXISTS monta_evses (
  id              TEXT PRIMARY KEY,          -- ecp-DK*MON*E4244495
  evse_id         TEXT,                      -- DK*MON*E4244495 (OCPI EVSE ID)
  site_id         TEXT REFERENCES monta_sites(id) ON DELETE CASCADE,
  station_id      TEXT,                      -- station-BS817T323
  current_type    TEXT,                      -- ac / dc
  max_power_w     INTEGER,                   -- stationens max effekt i watt
  connectors      JSONB,                     -- array af {connector_type, connector_format, charging_mode, max_power_w, max_current_a}
  is_green_energy BOOLEAN,
  synced_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_monta_evses_site_id
  ON monta_evses (site_id);

CREATE INDEX IF NOT EXISTS idx_monta_evses_evse_id
  ON monta_evses (evse_id);

-- =============================================================================
-- API-view til PostgREST
-- =============================================================================

CREATE OR REPLACE VIEW api.monta_charging_points AS
SELECT
  s.id              AS site_id,
  s.name            AS site_name,
  s.address,
  s.city,
  s.postal_code,
  s.country,
  ST_AsGeoJSON(s.coordinates)::json AS coordinates,
  s.operator_name,
  s.opening_times,
  e.id              AS evse_internal_id,
  e.evse_id,
  e.station_id,
  e.current_type,
  e.max_power_w,
  e.connectors,
  e.is_green_energy
FROM monta_sites s
JOIN monta_evses e ON e.site_id = s.id;

GRANT SELECT ON api.monta_charging_points TO web_anon;
