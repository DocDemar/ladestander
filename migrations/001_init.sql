-- Aktivér PostGIS extension (kræver superbruger første gang)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Ladestander-lokationer (statiske data)
CREATE TABLE IF NOT EXISTS locations (
  id              TEXT PRIMARY KEY,
  name            TEXT,
  address         TEXT,
  city            TEXT,
  postal_code     TEXT,
  country         TEXT,
  coordinates     GEOMETRY(Point, 4326),
  operator_name   TEXT,
  opening_times   JSONB,
  facilities      TEXT[],
  last_updated    TIMESTAMPTZ,
  synced_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_locations_coordinates
  ON locations USING GIST (coordinates);

-- EVSEs (ladestandere/stik-enheder) med dynamisk status
CREATE TABLE IF NOT EXISTS evses (
  id              INTEGER PRIMARY KEY,   -- AMPECOs interne id
  uid             TEXT NOT NULL,         -- OCPI uid
  location_id     TEXT REFERENCES locations(id) ON DELETE CASCADE,
  status          TEXT,
  capabilities    TEXT[],
  floor_level     TEXT,
  coordinates     GEOMETRY(Point, 4326),
  last_updated    TIMESTAMPTZ,
  synced_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_evses_location_id
  ON evses (location_id);

CREATE INDEX IF NOT EXISTS idx_evses_status
  ON evses (status);

CREATE INDEX IF NOT EXISTS idx_evses_coordinates
  ON evses USING GIST (coordinates);

-- Stiktyper tilknyttet EVSEs (statiske data)
CREATE TABLE IF NOT EXISTS connectors (
  id                  TEXT,
  evse_id             INTEGER REFERENCES evses(id) ON DELETE CASCADE,
  standard            TEXT,   -- fx IEC_62196_T2, CHADEMO, IEC_62196_T2_COMBO
  format              TEXT,   -- CABLE eller SOCKET
  power_type          TEXT,   -- AC_1_PHASE, AC_3_PHASE, DC
  max_voltage         INTEGER,
  max_amperage        INTEGER,
  max_electric_power  INTEGER,
  last_updated        TIMESTAMPTZ,
  PRIMARY KEY (id, evse_id)
);

CREATE INDEX IF NOT EXISTS idx_connectors_evse_id
  ON connectors (evse_id);
