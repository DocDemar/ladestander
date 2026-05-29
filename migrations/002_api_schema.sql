-- =============================================================================
-- PostgREST API-lag
-- =============================================================================
-- Kør denne migration EFTER 001_init.sql
-- Eksempel: psql -d ladestander -f migrations/002_api_schema.sql
-- =============================================================================

-- 1. Roller
-- web_anon: read-only rolle til anonyme HTTP-requests (ingen login)
CREATE ROLE web_anon NOLOGIN;

-- authenticator: login-rolle som PostgREST forbinder med
-- VIGTIGT: Skift 'skift-dette-password' til et stærkt password
--          og brug det samme i PGRST_DB_URI i .env
CREATE ROLE authenticator LOGIN PASSWORD 'skift-dette-password' NOINHERIT;
GRANT web_anon TO authenticator;

-- 2. API-schema (adskiller det offentlige API fra interne tabeller)
CREATE SCHEMA IF NOT EXISTS api;
GRANT USAGE ON SCHEMA api TO web_anon;

-- =============================================================================
-- 3. Views
-- =============================================================================

-- Lokationer (coordinates som GeoJSON Point)
CREATE OR REPLACE VIEW api.locations AS
SELECT
  id,
  name,
  address,
  city,
  postal_code,
  country,
  ST_AsGeoJSON(coordinates)::json AS coordinates,
  operator_name,
  opening_times,
  facilities,
  last_updated
FROM public.locations;

GRANT SELECT ON api.locations TO web_anon;

-- EVSEs med realtids-status (coordinates som GeoJSON)
CREATE OR REPLACE VIEW api.evses AS
SELECT
  id,
  uid,
  location_id,
  status,
  capabilities,
  floor_level,
  ST_AsGeoJSON(coordinates)::json AS coordinates,
  last_updated
FROM public.evses;

GRANT SELECT ON api.evses TO web_anon;

-- Stiktyper (connectors)
CREATE OR REPLACE VIEW api.connectors AS
SELECT
  id,
  evse_id,
  standard,
  format,
  power_type,
  max_voltage,
  max_amperage,
  max_electric_power,
  last_updated
FROM public.connectors;

GRANT SELECT ON api.connectors TO web_anon;

-- Kombineret view: lokation + EVSE + connectors (nestede som JSON array)
-- Bruges til at hente alt om et ladepunkt i ét kald
CREATE OR REPLACE VIEW api.charging_points AS
SELECT
  l.id            AS location_id,
  l.name          AS location_name,
  l.address,
  l.city,
  l.postal_code,
  l.country,
  ST_AsGeoJSON(l.coordinates)::json AS coordinates,
  l.operator_name,
  l.opening_times,
  l.facilities,
  e.id            AS evse_id,
  e.uid           AS evse_uid,
  e.status,
  e.capabilities,
  e.floor_level,
  json_agg(
    json_build_object(
      'id',                c.id,
      'standard',          c.standard,
      'format',            c.format,
      'power_type',        c.power_type,
      'max_voltage',       c.max_voltage,
      'max_amperage',      c.max_amperage,
      'max_electric_power',c.max_electric_power
    )
  ) FILTER (WHERE c.id IS NOT NULL) AS connectors,
  e.last_updated
FROM public.locations l
JOIN public.evses e
  ON e.location_id = l.id
LEFT JOIN public.connectors c
  ON c.evse_id = e.id
GROUP BY
  l.id, l.name, l.address, l.city, l.postal_code, l.country,
  l.coordinates, l.operator_name, l.opening_times, l.facilities,
  e.id, e.uid, e.status, e.capabilities, e.floor_level, e.last_updated;

GRANT SELECT ON api.charging_points TO web_anon;
