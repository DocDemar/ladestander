-- Migration 014: Kopiér eksisterende Monta-data til de generiske tabeller.
-- monta_sites  → charging_sites  (source='monta', id='monta-'||id)
-- monta_evses  → charging_evses  (source='monta', id='monta-'||id)
-- evse_status_history → tilføj source-kolonne, sæt eksisterende rækker til 'monta'
--
-- De gamle tabeller (monta_sites, monta_evses) bevares uændret og kan slettes
-- manuelt efter verifikation.

-- ── Kopiér sites ──────────────────────────────────────────────────────────────
INSERT INTO charging_sites (
  id, source, external_id, name, address, city, postal_code, country,
  coordinates, operator_name, opening_times, synced_at
)
SELECT
  'monta-' || id  AS id,
  'monta'         AS source,
  id              AS external_id,
  name,
  address,
  city,
  postal_code,
  COALESCE(country, 'DK'),
  coordinates,
  operator_name,
  opening_times,
  synced_at
FROM monta_sites
ON CONFLICT (source, external_id) DO NOTHING;

-- ── Kopiér EVSEs ─────────────────────────────────────────────────────────────
INSERT INTO charging_evses (
  id, source, external_id, site_id, evse_id, current_type, max_power_w,
  connectors, is_green_energy, availability_status, last_status_updated,
  last_seen_at, synced_at
)
SELECT
  'monta-' || e.id    AS id,
  'monta'             AS source,
  e.id                AS external_id,
  'monta-' || e.site_id AS site_id,
  e.evse_id,
  e.current_type,
  e.max_power_w,
  e.connectors,
  e.is_green_energy,
  e.availability_status,
  e.last_status_updated,
  e.last_seen_at,
  e.synced_at
FROM monta_evses e
ON CONFLICT (source, external_id) DO NOTHING;

-- ── Tilføj source-kolonne til evse_status_history ────────────────────────────
ALTER TABLE evse_status_history
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'monta';

CREATE INDEX IF NOT EXISTS idx_evse_status_history_source
  ON evse_status_history (source);
