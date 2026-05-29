-- =============================================================================
-- Historik-tabel til tidsstemplede EVSE-statusobservationer
-- Kun kendte statuser gemmes (available / occupied / outOfService).
-- Rækker ældre end 30 dage slettes løbende af server.js.
-- =============================================================================

CREATE TABLE IF NOT EXISTS evse_status_history (
  id          BIGSERIAL    PRIMARY KEY,
  evse_id     TEXT         NOT NULL,
  status      TEXT         NOT NULL,  -- available | occupied | outOfService
  recorded_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Opslag per EVSE over tid (tidsserieanalyse per lader)
CREATE INDEX IF NOT EXISTS idx_evse_status_history_evse_time
  ON evse_status_history (evse_id, recorded_at DESC);

-- Opslag på tværs af alle EVSEs inden for et tidsvindue
CREATE INDEX IF NOT EXISTS idx_evse_status_history_time
  ON evse_status_history (recorded_at DESC);

-- Tilføj last_seen_at til monta_evses: tidspunkt for seneste HTTP 200 fra Monta
ALTER TABLE monta_evses
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;
