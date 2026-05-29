-- Migration 016: Generiske PostgREST API-funktioner.
-- Erstatter api.monta_charging_points_bbox med api.charging_stations_bbox
-- der virker for alle kilder. Tilføjer api.fuel_stations_bbox.

-- ── Drop de gamle Monta-specifikke funktioner ─────────────────────────────────
DROP FUNCTION IF EXISTS api.monta_charging_points_bbox(float8, float8, float8, float8);
DROP FUNCTION IF EXISTS api.monta_charging_points_bbox(float8, float8, float8, float8, text);

-- ── api.charging_stations_bbox ───────────────────────────────────────────────
-- Returnerer aggregerede ladestanderdata per site inden for et bbox.
-- source-parameteret filtrerer på kilde (NULL = alle kilder).
CREATE FUNCTION api.charging_stations_bbox(
  xmin float8, ymin float8, xmax float8, ymax float8,
  source text DEFAULT NULL
)
RETURNS TABLE(
  site_id              text,
  site_name            text,
  address              text,
  city                 text,
  postal_code          text,
  country              text,
  operator_name        text,
  source               text,
  evse_count           integer,
  ac_count             integer,
  dc_count             integer,
  max_power_kw         integer,
  has_available        boolean,
  available_count      integer,
  occupied_count       integer,
  out_of_service_count integer,
  connector_types      text[],
  last_seen_at         text,
  coordinates          json
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    s.id,
    s.name,
    s.address,
    s.city,
    s.postal_code,
    s.country,
    s.operator_name,
    s.source,
    COUNT(e.id)::integer                                                                                   AS evse_count,
    COUNT(e.id) FILTER (WHERE e.current_type = 'ac')::integer                                             AS ac_count,
    COUNT(e.id) FILTER (WHERE e.current_type = 'dc')::integer                                             AS dc_count,
    (MAX(e.max_power_w) / 1000)::integer                                                                  AS max_power_kw,
    bool_or(e.availability_status = 'available')                                                          AS has_available,
    COUNT(e.id) FILTER (WHERE e.availability_status = 'available')::integer                               AS available_count,
    COUNT(e.id) FILTER (WHERE e.availability_status = 'occupied')::integer                                AS occupied_count,
    COUNT(e.id) FILTER (WHERE e.availability_status IN ('outOfService', 'out_of_service'))::integer       AS out_of_service_count,
    ARRAY(
      SELECT DISTINCT jsonb_array_elements(e2.connectors)->>'connector_type'
      FROM charging_evses e2
      WHERE e2.site_id = s.id
        AND e2.connectors IS NOT NULL
      ORDER BY 1
    )                                                                                                     AS connector_types,
    TO_CHAR(
      MAX(e.last_seen_at) AT TIME ZONE 'Europe/Copenhagen',
      'DD/MM/YYYY HH24:MI'
    )                                                                                                     AS last_seen_at,
    ST_AsGeoJSON(s.coordinates)::json
  FROM charging_sites s
  JOIN charging_evses e ON e.site_id = s.id
  WHERE s.coordinates && ST_MakeEnvelope(xmin, ymin, xmax, ymax, 4326)
    AND (charging_stations_bbox.source IS NULL OR s.source = charging_stations_bbox.source)
  GROUP BY s.id, s.name, s.address, s.city, s.postal_code, s.country, s.operator_name, s.source, s.coordinates
$$;

GRANT EXECUTE ON FUNCTION api.charging_stations_bbox(float8, float8, float8, float8, text) TO web_anon;

-- ── api.fuel_stations_bbox ────────────────────────────────────────────────────
-- Returnerer brændstofstationer med aktuelle priser inden for et bbox.
CREATE FUNCTION api.fuel_stations_bbox(
  xmin float8, ymin float8, xmax float8, ymax float8
)
RETURNS TABLE(
  station_id    text,
  source        text,
  address       text,
  city          text,
  postal_code   text,
  country       text,
  prices        jsonb,
  synced_at     timestamptz,
  coordinates   json
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    s.id,
    s.source,
    s.address,
    s.city,
    s.postal_code,
    s.country,
    jsonb_object_agg(p.product_name, p.price) FILTER (WHERE p.product_name IS NOT NULL) AS prices,
    s.synced_at,
    ST_AsGeoJSON(s.coordinates)::json
  FROM fuel_stations s
  LEFT JOIN fuel_station_prices p ON p.station_id = s.id
  WHERE s.coordinates && ST_MakeEnvelope(xmin, ymin, xmax, ymax, 4326)
  GROUP BY s.id, s.source, s.address, s.city, s.postal_code, s.country, s.synced_at, s.coordinates
$$;

GRANT EXECUTE ON FUNCTION api.fuel_stations_bbox(float8, float8, float8, float8) TO web_anon;

-- ── Opdater operators_with_history view ──────────────────────────────────────
CREATE OR REPLACE VIEW api.operators_with_history AS
  SELECT DISTINCT s.operator_name
  FROM charging_sites s
  JOIN charging_evses e ON e.site_id = s.id
  JOIN evse_status_history h ON h.evse_id = e.external_id AND h.source = e.source
  WHERE s.operator_name IS NOT NULL
  ORDER BY s.operator_name;

GRANT SELECT ON api.operators_with_history TO web_anon;

-- ── Opdater site_hourly_occupancy funktion ─────────────────────────────────────
DROP FUNCTION IF EXISTS api.site_hourly_occupancy(text, text, text);

CREATE FUNCTION api.site_hourly_occupancy(
  p_site_id   text,
  p_date_from text DEFAULT (NOW() - INTERVAL '7 days')::date::text,
  p_date_to   text DEFAULT NOW()::date::text
)
RETURNS TABLE(
  hour_bucket   timestamptz,
  avg_available numeric,
  avg_occupied  numeric
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    date_trunc('hour', h.recorded_at AT TIME ZONE 'Europe/Copenhagen') AS hour_bucket,
    AVG(CASE WHEN h.status = 'available'  THEN 1.0 ELSE 0.0 END)       AS avg_available,
    AVG(CASE WHEN h.status = 'occupied'   THEN 1.0 ELSE 0.0 END)       AS avg_occupied
  FROM evse_status_history h
  JOIN charging_evses e ON e.external_id = h.evse_id AND e.source = h.source
  WHERE e.site_id = p_site_id
    AND h.recorded_at BETWEEN p_date_from::timestamptz AND (p_date_to::date + 1)::timestamptz
  GROUP BY 1
  ORDER BY 1
$$;

GRANT EXECUTE ON FUNCTION api.site_hourly_occupancy(text, text, text) TO web_anon;
