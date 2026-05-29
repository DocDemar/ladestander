-- Migration 006: Change bbox function to accept WGS84 (EPSG:4326) coordinates
-- Widget3 with srs:"EPSG:4326" sends bbox as lon/lat, not EPSG:25832

CREATE OR REPLACE FUNCTION api.monta_charging_points_bbox(
  xmin float8, ymin float8, xmax float8, ymax float8
)
RETURNS TABLE(site_id text, site_name text, address text, city text,
  postal_code text, country text, operator_name text, opening_times jsonb,
  evse_internal_id text, evse_id text, station_id text, current_type text,
  max_power_w integer, connectors jsonb, is_green_energy boolean,
  availability_status text, price_json jsonb, last_status_updated timestamptz,
  coordinates json)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT s.id, s.name, s.address, s.city, s.postal_code, s.country,
    s.operator_name, s.opening_times, e.id, e.evse_id, e.station_id,
    e.current_type, e.max_power_w, e.connectors, e.is_green_energy,
    e.availability_status, e.price_json, e.last_status_updated,
    ST_AsGeoJSON(s.coordinates)::json
  FROM monta_sites s JOIN monta_evses e ON e.site_id = s.id
  WHERE s.coordinates && ST_MakeEnvelope(xmin, ymin, xmax, ymax, 4326)
$$;
