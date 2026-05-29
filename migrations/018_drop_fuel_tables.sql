-- Migration 018: Fjern fuel-tabeller og fuel-API-funktioner.
-- Projektet dækker udelukkende ladestandere og elpriser — ikke brændstofpriser.

DROP FUNCTION IF EXISTS api.fuel_stations_bbox(float8, float8, float8, float8);

DROP TABLE IF EXISTS fuel_price_history CASCADE;
DROP TABLE IF EXISTS fuel_station_prices CASCADE;
DROP TABLE IF EXISTS fuel_stations CASCADE;
