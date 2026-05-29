-- Migration 011: Historik-visualisering — belastning pr. time på dagen.
-- Giver et heatmap-view: for hvert (site × time 0-23) beregnes % optaget
-- baseret på alle observationer i evse_status_history.

-- Operatører der har historikdata (til dropdown i frontend)
CREATE OR REPLACE VIEW api.operators_with_history AS
  SELECT DISTINCT s.operator_name
  FROM evse_status_history h
  JOIN monta_evses e ON e.evse_id = h.evse_id
  JOIN monta_sites s ON s.id = e.site_id
  WHERE s.operator_name IS NOT NULL
  ORDER BY s.operator_name;

GRANT SELECT ON api.operators_with_history TO web_anon;

-- Funktion: timelig belastning pr. ladestation
-- Returnerer én række pr. (site × time 0-23) med pct_occupied.
-- Parameteren op_name er optional — NULL returnerer alle operatører.
CREATE OR REPLACE FUNCTION api.site_hourly_occupancy(
  op_name text DEFAULT NULL
)
RETURNS TABLE(
  site_id       text,
  site_name     text,
  operator_name text,
  hour_of_day   integer,
  occupied_count bigint,
  available_count bigint,
  total_count   bigint,
  pct_occupied  integer
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    s.id                                                                        AS site_id,
    s.name                                                                      AS site_name,
    s.operator_name,
    EXTRACT(hour FROM h.recorded_at)::integer                                   AS hour_of_day,
    COUNT(1) FILTER (WHERE h.status = 'occupied')                               AS occupied_count,
    COUNT(1) FILTER (WHERE h.status = 'available')                              AS available_count,
    COUNT(1)                                                                    AS total_count,
    ROUND(
      100.0 * COUNT(1) FILTER (WHERE h.status = 'occupied')
      / NULLIF(COUNT(1), 0)
    )::integer                                                                  AS pct_occupied
  FROM evse_status_history h
  JOIN monta_evses e ON e.evse_id = h.evse_id
  JOIN monta_sites s ON s.id = e.site_id
  WHERE (op_name IS NULL OR s.operator_name = op_name)
  GROUP BY s.id, s.name, s.operator_name, EXTRACT(hour FROM h.recorded_at)
  ORDER BY s.id, hour_of_day
$$;

GRANT EXECUTE ON FUNCTION api.site_hourly_occupancy(text) TO web_anon;
