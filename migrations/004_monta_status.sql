-- =============================================================================
-- Tilføj dynamisk status til monta_evses
-- =============================================================================
ALTER TABLE monta_evses
  ADD COLUMN IF NOT EXISTS availability_status  TEXT,
  ADD COLUMN IF NOT EXISTS price_json           JSONB,
  ADD COLUMN IF NOT EXISTS last_status_updated  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_monta_evses_availability
  ON monta_evses (availability_status);

-- Opdatér API-view til at inkludere dynamisk status og pris
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
  e.is_green_energy,
  e.availability_status,
  e.price_json,
  e.last_status_updated
FROM monta_sites s
JOIN monta_evses e ON e.site_id = s.id;
