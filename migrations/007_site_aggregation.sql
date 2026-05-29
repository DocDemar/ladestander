-- Migration 007: Return one feature per site (aggregated EVSEs)
-- Fixes the issue of multiple EVSEs at the same coordinates stacking on top of each other.

CREATE OR REPLACE FUNCTION api.monta_charging_points_bbox(
  xmin float8, ymin float8, xmax float8, ymax float8
)
RETURNS TABLE(
  site_id text, site_name text, address text, city text,
  postal_code text, country text, operator_name text,
  evse_count integer,
  ac_count integer, dc_count integer,
  max_power_kw integer,
  has_available boolean,
  connector_types text[],
  coordinates json
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
    COUNT(e.id)::integer                                          AS evse_count,
    COUNT(e.id) FILTER (WHERE e.current_type = 'ac')::integer    AS ac_count,
    COUNT(e.id) FILTER (WHERE e.current_type = 'dc')::integer    AS dc_count,
    (MAX(e.max_power_w) / 1000)::integer                         AS max_power_kw,
    bool_or(e.availability_status = 'available')                 AS has_available,
    ARRAY(
      SELECT DISTINCT jsonb_array_elements(e2.connectors)->>'connector_type'
      FROM monta_evses e2
      WHERE e2.site_id = s.id
        AND e2.connectors IS NOT NULL
      ORDER BY 1
    )                                                             AS connector_types,
    ST_AsGeoJSON(s.coordinates)::json
  FROM monta_sites s
  JOIN monta_evses e ON e.site_id = s.id
  WHERE s.coordinates && ST_MakeEnvelope(xmin, ymin, xmax, ymax, 4326)
  GROUP BY s.id, s.name, s.address, s.city, s.postal_code, s.country, s.operator_name, s.coordinates
$$;
