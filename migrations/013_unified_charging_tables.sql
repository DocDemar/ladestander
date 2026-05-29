-- Migration 013: Generiske charging_sites og charging_evses tabeller.
-- Erstatter de Monta-specifikke monta_sites/monta_evses med en fælles
-- datamodel der kan rumme alle operatørkilder via et source-felt.
-- Monta-data migreres i 014. De gamle tabeller bevares midlertidigt.

-- ── charging_sites ────────────────────────────────────────────────────────────
CREATE TABLE charging_sites (
  id              TEXT PRIMARY KEY,        -- "{source}-{external_id}", fx "monta-site-195706"
  source          TEXT NOT NULL,           -- 'monta', 'eco-movement', 'ok', 'edf', 'eon', 'spirii', 'drivee'
  external_id     TEXT NOT NULL,           -- kildens egne ID
  name            TEXT,
  address         TEXT,
  city            TEXT,
  postal_code     TEXT,
  country         TEXT DEFAULT 'DK',
  coordinates     GEOMETRY(Point, 4326),
  operator_name   TEXT,
  opening_times   JSONB,
  raw_data        JSONB,
  synced_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (source, external_id)
);

CREATE INDEX idx_charging_sites_coordinates ON charging_sites USING GIST (coordinates);
CREATE INDEX idx_charging_sites_source       ON charging_sites (source);
CREATE INDEX idx_charging_sites_operator     ON charging_sites (operator_name);

-- ── charging_evses ────────────────────────────────────────────────────────────
CREATE TABLE charging_evses (
  id                    TEXT PRIMARY KEY,  -- "{source}-{external_id}"
  source                TEXT NOT NULL,
  external_id           TEXT NOT NULL,     -- kildens eget EVSE-id
  site_id               TEXT REFERENCES charging_sites(id) ON DELETE CASCADE,
  evse_id               TEXT,             -- OCPI standard EVSE ID, fx "DK*MON*E4244495"
  current_type          TEXT,             -- 'ac' eller 'dc'
  max_power_w           INTEGER,
  connectors            JSONB,
  is_green_energy       BOOLEAN,
  availability_status   TEXT,             -- 'available', 'occupied', 'out_of_service', 'unknown'
  last_status_updated   TIMESTAMPTZ,
  last_seen_at          TIMESTAMPTZ,
  raw_data              JSONB,
  synced_at             TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (source, external_id)
);

CREATE INDEX idx_charging_evses_site_id      ON charging_evses (site_id);
CREATE INDEX idx_charging_evses_source       ON charging_evses (source);
CREATE INDEX idx_charging_evses_evse_id      ON charging_evses (evse_id);
CREATE INDEX idx_charging_evses_availability ON charging_evses (availability_status);
