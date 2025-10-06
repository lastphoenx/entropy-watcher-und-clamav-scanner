#!/usr/bin/env bash
# =====================================================
# EntropyWatcher Safety-Gate
# =====================================================
# Zentrale Sicherheits-Entscheidung vor RTB/pCloud Backups
#
# Checks (in dieser Reihenfolge):
#   1. HONEYFILES: Wurde System kompromittiert? (Fail-Fast Pre-Check)
#   2. ENTROPYWATCHER: nas + nas-av Status prüfen
#
# Usage:
#   ./safety_gate.sh          # Prüft Honeyfiles + nas + nas-av
#   ./safety_gate.sh --strict # Blockiert auch bei YELLOW (EntropyWatcher)
#
# Environment:
#   CHECK_HONEYFILES=0        # Honeyfiles-Check deaktivieren (default: 1)
#   HONEYFILE_FLAG=...        # Custom Flag-File-Pfad
#   HONEYFILE_AUDIT_KEY=...   # Custom Audit-Key
#
# Exit Codes:
#   0 = SAFE (GREEN)
#   1 = WARNING (YELLOW - nur EntropyWatcher)
#   2 = BLOCKED (RED - Honeyfiles ODER kritischer Fehler)

set -euo pipefail

# === Konfiguration ===
ENTROPYWATCHER_PY="${ENTROPYWATCHER_PY:-/opt/apps/entropywatcher/venv/bin/python}"
ENTROPYWATCHER_SCRIPT="${ENTROPYWATCHER_SCRIPT:-/opt/apps/entropywatcher/main/entropywatcher.py}"
ENTROPYWATCHER_COMMON_ENV="${ENTROPYWATCHER_COMMON_ENV:-/opt/apps/entropywatcher/config/common.env}"

# Strict Mode (blockiert auch bei YELLOW)
STRICT_MODE=0
if [[ "${1:-}" == "--strict" ]]; then
  STRICT_MODE=1
fi

log() { printf "%s [SafetyGate] %s\n" "$(date '+%F %T')" "$*" >&2; }

# === Honeyfiles Konfiguration ===
CHECK_HONEYFILES="${CHECK_HONEYFILES:-1}"
HONEYFILE_FLAG="${HONEYFILE_FLAG:-/var/lib/honeyfile_alert}"
HONEYFILE_AUDIT_KEY="${HONEYFILE_AUDIT_KEY:-honeyfile_access}"

check_honeyfiles() {
  [[ $CHECK_HONEYFILES -eq 0 ]] && return 0
  
  if [[ -f "$HONEYFILE_FLAG" ]]; then
    log "✗ CRITICAL: Honeyfile-Alarm-Flag gefunden: $HONEYFILE_FLAG"
    return 1
  fi
  
  if command -v ausearch &>/dev/null; then
    if ausearch -k "$HONEYFILE_AUDIT_KEY" --start recent 2>/dev/null | grep -q "type=SYSCALL"; then
      log "✗ CRITICAL: Frischer Honeyfile-Zugriff im Audit-Log erkannt!"
      return 1
    fi
  fi
  
  return 0
}

# Services die für Backup-Safety relevant sind
# (NAS: Dateien, NAS-AV: Viren-Check)
SERVICES=("nas" "nas-av")

OVERALL_STATUS=0  # 0=GREEN, 1=YELLOW, 2=RED

echo ""
log "════════════════════════════════════════════════════════════════════"
log "1. PRE-FLIGHT: System-Integrität (Honeyfiles)"
log "════════════════════════════════════════════════════════════════════"

if ! check_honeyfiles; then
  log ""
  log "!!! SYSTEM KOMPROMITTIERT - BACKUP BLOCKIERT !!!"
  log "════════════════════════════════════════════════════════════════════"
  log "✗✗✗ SAFETY-GATE: RED - KRITISCHER HONEYFILE-ALARM!"
  log "    → RTB/pCloud Backups NICHT ERLAUBT"
  log "    → Prüfe: sudo ausearch -k honeyfile_access --start recent"
  log "════════════════════════════════════════════════════════════════════"
  exit 2
fi

log "✓ Honeyfiles: kein verdächtiger Zugriff erkannt"

echo ""
log "════════════════════════════════════════════════════════════════════"
log "2. ENTROPYWATCHER CHECKS (nas + nas-av)"
log "════════════════════════════════════════════════════════════════════"

for SERVICE in "${SERVICES[@]}"; do
  SERVICE_ENV="/opt/apps/entropywatcher/config/${SERVICE}.env"
  
  if [[ ! -f "$SERVICE_ENV" ]]; then
    log "⚠ Service-ENV nicht gefunden: $SERVICE_ENV (überspringe)"
    continue
  fi
  
  log "Prüfe Service: $SERVICE ..."
  
  set +e
  "$ENTROPYWATCHER_PY" "$ENTROPYWATCHER_SCRIPT" \
    --env "$ENTROPYWATCHER_COMMON_ENV" \
    --env "$SERVICE_ENV" \
    status --json-out /dev/null 2>/dev/null
  
  STATUS=$?
  set -e
  
  case $STATUS in
    0) 
      log "  ✓ $SERVICE: GREEN (sicher)"
      ;;
    1) 
      log "  ⚠ $SERVICE: YELLOW (Warnungen)"
      if [[ $OVERALL_STATUS -lt 1 ]]; then
        OVERALL_STATUS=1
      fi
      ;;
    2) 
      log "  ✗ $SERVICE: RED (ALARM!)"
      OVERALL_STATUS=2
      ;;
    *)
      log "  ? $SERVICE: UNKNOWN (Exit $STATUS)"
      OVERALL_STATUS=2  # Bei Fehler: RED
      ;;
  esac
done

echo ""
log "========================================"
case $OVERALL_STATUS in
  0)
    log "✓✓✓ SAFETY-GATE: GREEN"
    log "    → RTB/pCloud Backups ERLAUBT"
    ;;
  1)
    if [[ $STRICT_MODE -eq 1 ]]; then
      log "✗✗✗ SAFETY-GATE: BLOCKED (YELLOW im Strict-Mode)"
      log "    → RTB/pCloud Backups BLOCKIERT (--strict aktiv)"
      OVERALL_STATUS=2  # Im Strict-Mode wird YELLOW zu RED
    else
      log "⚠⚠⚠ SAFETY-GATE: YELLOW"
      log "    → RTB/pCloud Backups mit Warnung ERLAUBT"
      log "    → Verwende --strict zum Blockieren"
    fi
    ;;
  2)
    log "✗✗✗ SAFETY-GATE: RED - BLOCKIERT!"
    log "    → RTB/pCloud Backups NICHT ERLAUBT"
    log "    → Prüfe: ./test_commands.sh nas"
    ;;
esac
log "========================================"

exit $OVERALL_STATUS
