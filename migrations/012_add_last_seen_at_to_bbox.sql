-- Migration 012: Tilføj last_seen_at til bbox-funktionen.
-- Returnerer tidspunkt for seneste statusopdatering (per site) i dansk lokal tid.

DROP FUNCTION IF EXISTS api.monta_charging_points_bbox(float8, float8, float8, float8);
DROP FUNCTION IF EXISTS api.monta_charging_points_bbox(float8, float8, float8, float8, text);

CREATE FUNCTION api.monta_charging_points_bbox(
  xmin float8, ymin float8, xmax float8, ymax float8,
  operator_name text DEFAULT NULL
)
RETURNS TABLE(
  site_id         text,
  site_name       text,
  address         text,
  city            text,
  postal_code     text,
  country         text,
  operator_name   text,
  evse_count      integer,
  ac_count        integer,
  dc_count        integer,
  max_power_kw    integer,
  has_available   boolean,
  available_count integer,
  occupied_count  integer,
  out_of_service_count integer,
  connector_types text[],
  last_seen_at    text,
  coordinates     json
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
    COUNT(e.id)::integer                                                                        AS evse_count,
    COUNT(e.id) FILTER (WHERE e.current_type = 'ac')::integer                                  AS ac_count,
    COUNT(e.id) FILTER (WHERE e.current_type = 'dc')::integer                                  AS dc_count,
    (MAX(e.max_power_w) / 1000)::integer                                                       AS max_power_kw,
    bool_or(e.availability_status = 'available')                                               AS has_available,
    COUNT(e.id) FILTER (WHERE e.availability_status = 'available')::integer                    AS available_count,
    COUNT(e.id) FILTER (WHERE e.availability_status = 'occupied')::integer                     AS occupied_count,
    COUNT(e.id) FILTER (WHERE e.availability_status IN ('outOfService', 'out_of_service'))::integer AS out_of_service_count,
    ARRAY(
      SELECT DISTINCT jsonb_array_elements(e2.connectors)->>'connector_type'
      FROM monta_evses e2
      WHERE e2.site_id = s.id
        AND e2.connectors IS NOT NULL
      ORDER BY 1
    )                                                                                          AS connector_types,
    TO_CHAR(
      MAX(e.last_seen_at) AT TIME ZONE 'Europe/Copenhagen',
      'DD/MM/YYYY HH24:MI'
    )                                                                                          AS last_seen_at,
    ST_AsGeoJSON(s.coordinates)::json
  FROM monta_sites s
  JOIN monta_evses e ON e.site_id = s.id
  WHERE s.coordinates && ST_MakeEnvelope(xmin, ymin, xmax, ymax, 4326)
    AND (monta_charging_points_bbox.operator_name IS NULL
         OR s.operator_name = monta_charging_points_bbox.operator_name)
  GROUP BY s.id, s.name, s.address, s.city, s.postal_code, s.country, s.operator_name, s.coordinates
$$;

GRANT EXECUTE ON FUNCTION api.monta_charging_points_bbox(float8, float8, float8, float8, text) TO web_anon;
