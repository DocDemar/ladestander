-- Migration 015: Tabeller til brændstofstationer og -priser.
-- Samme mønster som charging_sites/charging_evses og evse_status_history.

-- ── fuel_stations ─────────────────────────────────────────────────────────────
CREATE TABLE fuel_stations (
  id              TEXT PRIMARY KEY,    -- "{source}-{external_id}", fx "ok-1030"
  source          TEXT NOT NULL,       -- 'ok' (udvides til andre brændstofkilder)
  external_id     TEXT NOT NULL,       -- facility_number (integer som text)
  name            TEXT,
  address         TEXT,
  city            TEXT,
  postal_code     TEXT,
  country         TEXT DEFAULT 'DK',
  coordinates     GEOMETRY(Point, 4326),
  raw_data        JSONB,
  synced_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (source, external_id)
);

CREATE INDEX idx_fuel_stations_coordinates ON fuel_stations USING GIST (coordinates);
CREATE INDEX idx_fuel_stations_source      ON fuel_stations (source);

-- ── fuel_station_prices (aktuelle priser) ─────────────────────────────────────
-- Én række pr. (station, produkt) — overskrives ved hver fetch
CREATE TABLE fuel_station_prices (
  station_id    TEXT NOT NULL REFERENCES fuel_stations(id) ON DELETE CASCADE,
  product_name  TEXT NOT NULL,          -- 'Blyfri 95', 'Svovlfri Diesel', 'Oktan 100'
  price         NUMERIC(6, 2),
  fetched_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (station_id, product_name)
);

-- ── fuel_price_history (historiske priser) ────────────────────────────────────
-- Ny række ved hver prisændring — samme mønster som evse_status_history
CREATE TABLE fuel_price_history (
  id            BIGSERIAL PRIMARY KEY,
  station_id    TEXT NOT NULL,
  source        TEXT NOT NULL DEFAULT 'ok',
  product_name  TEXT NOT NULL,
  price         NUMERIC(6, 2),
  recorded_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_fuel_price_history_station ON fuel_price_history (station_id);
CREATE INDEX idx_fuel_price_history_time    ON fuel_price_history (recorded_at DESC);
CREATE INDEX idx_fuel_price_history_source  ON fuel_price_history (source);
