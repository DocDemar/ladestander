-- Migration 017: Slet gamle tabeller og views der er erstattet af den generiske datamodel.
-- Backup er gemt i backups/old_tables_backup_*.sql inden denne migration kørtes.

-- ── Gamle api-views fra migration 002 ────────────────────────────────────────
DROP VIEW IF EXISTS api.monta_charging_points CASCADE;
DROP VIEW IF EXISTS api.charging_points CASCADE;
DROP VIEW IF EXISTS api.connectors CASCADE;
DROP VIEW IF EXISTS api.evses CASCADE;
DROP VIEW IF EXISTS api.locations CASCADE;

-- ── Monta-specifikke tabeller (erstattet af charging_sites/charging_evses) ───
DROP TABLE IF EXISTS monta_evses CASCADE;
DROP TABLE IF EXISTS monta_sites CASCADE;

-- ── Ubrugte OCPI-tabeller fra migration 001 (aldrig taget i brug) ─────────────
DROP TABLE IF EXISTS connectors CASCADE;
DROP TABLE IF EXISTS evses CASCADE;
DROP TABLE IF EXISTS locations CASCADE;
