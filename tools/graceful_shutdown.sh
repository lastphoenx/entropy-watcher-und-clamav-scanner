#!/usr/bin/env bash
#
# graceful_shutdown.sh
# Wartet auf laufende Services (EntropyWatcher, RTB, pCloud) und fährt dann sauber herunter
#
# Usage:
#   sudo ./graceful_shutdown.sh [--timeout SECONDS] [--dry-run] [--no-shutdown]
#
# Options:
#   --timeout SECONDS     Maximale Wartezeit pro Service (default: 1800 = 30 min)
#   --dry-run            Nur prüfen, nicht herunterfahren
#   --no-shutdown        Nach Warten nicht herunterfahren (nur prüfen & warten)
#
# Exit Codes:
#   0 = Shutdown geplant; Wartezeit bis Halt abgelaufen (Prozess endet mit systemd)
#   1 = Fehler / Timeout / Lockfile oder Prozesse blockieren
#   2 = Nur --dry-run ausgeführt

set -euo pipefail

# ============================================================================
# Konfiguration
# ============================================================================
TIMEOUT=1800          # 30 Minuten max Wartezeit
DRY_RUN=0
NO_SHUTDOWN=0
POLL_INTERVAL=10      # Sekunden zwischen Checks
SHUTDOWN_DELAY_SEC=60 # Entspricht shutdown -h +1 (Abbrechen: shutdown -c)
LOCKFILE="/run/backup_pipeline.lock" # Globales Lockfile
LOG_FILE="/var/log/graceful_shutdown.log"

# Parse Argumente
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --no-shutdown)
            NO_SHUTDOWN=1
            shift
            ;;
        *)
            echo "Unbekannter Parameter: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================
log() {
    local line
    line="$(date '+%F %T') [graceful_shutdown] $*"
    printf "%s\n" "$line"
    logger -t graceful_shutdown -- "$*"
    if [[ -w /var/log ]] || [[ -f "$LOG_FILE" ]]; then
        printf "%s\n" "$(date -Is) $line" >>"$LOG_FILE" 2>/dev/null || true
    fi
}

error() {
    local line
    line="$(date '+%F %T') [graceful_shutdown] ✗ $*"
    printf "%s\n" "$line" >&2
    logger -t graceful_shutdown -p user.err -- "$*"
    if [[ -w /var/log ]] || [[ -f "$LOG_FILE" ]]; then
        printf "%s\n" "$(date -Is) $line" >>"$LOG_FILE" 2>/dev/null || true
    fi
}

is_lockfile_held() {
    if [[ ! -f "$LOCKFILE" ]]; then
        return 1
    fi
    exec 9<"$LOCKFILE"
    if flock -n 9; then
        exec 9<&-
        return 1
    fi
    exec 9<&-
    return 0
}

wait_for_scheduled_halt() {
    local halt_at="$1"
    local now remaining

    log "Warte ${SHUTDOWN_DELAY_SEC}s bis Halt (Abbrechen: shutdown -c). SSH kann vorher abbrechen — Halt läuft trotzdem."
    log "Nach Halt: Netzteil aus, dann SD tauschen. „Wirklich aus“ von außen: ping weg oder LED aus."

    while true; do
        now=$(date +%s)
        if (( now >= halt_at )); then
            break
        fi
        remaining=$((halt_at - now))
        log "Noch ${remaining}s bis geplanter Halt..."
        if (( remaining > 10 )); then
            sleep 10
        else
            sleep "$remaining"
        fi
    done

    log "Halt-Zeit erreicht — systemd fährt jetzt herunter."
    sync
}

is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null && return 0 || return 1
}

get_service_status() {
    local service="$1"
    systemctl is-active "$service" 2>/dev/null || echo "unknown"
}

wait_for_service() {
    local service="$1"
    local timeout="$2"
    local elapsed=0
    
    log "⏳ Warte auf $service (Timeout: ${timeout}s)..."
    
    while (( elapsed < timeout )); do
        if ! is_service_running "$service"; then
            log "✓ $service ist beendet"
            return 0
        fi
        
        log "  $service läuft noch... (${elapsed}/${timeout}s)"
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    error "$service hat nicht rechtzeitig beendet (Timeout nach ${timeout}s)"
    return 1
}

check_process() {
    local name="$1"
    local pattern="$2"
    local pids
    
    pids=$(pgrep -f "$pattern" 2>/dev/null || echo "")
    if [[ -n "$pids" ]]; then
        log "  Prozesse: $name (PIDs: $pids)"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# SCHRITT 0: Timer stoppen (Neue Jobs verhindern)
# ============================================================================
log "════════════════════════════════════════════════════════════════════"
log "Stoppe Timer (Verhindere neue Jobs während Wartezeit)..."
log "════════════════════════════════════════════════════════════════════"

TIMERS_TO_STOP=(
    "entropywatcher.timer"
    "entropywatcher-nas.timer"
    "entropywatcher-os.timer"
)

for timer in "${TIMERS_TO_STOP[@]}"; do
    if systemctl is-active --quiet "$timer"; then
        if [[ $DRY_RUN -eq 0 ]]; then
            systemctl stop "$timer"
            log "✓ $timer gestoppt"
        else
            log "[DRY-RUN] Würde $timer stoppen"
        fi
    fi
done

# ============================================================================
# PRÜFUNG: Laufende Services
# ============================================================================
log "════════════════════════════════════════════════════════════════════"
log "Prüfe laufende Services..."
log "════════════════════════════════════════════════════════════════════"

SERVICES_TO_WAIT=(
    "entropywatcher-nas.service"
    "entropywatcher-nas-av.service"
    "entropywatcher-os.service"
    "entropywatcher-os-av.service"
    "backup-pipeline.service"
)

RUNNING_SERVICES=()
for service in "${SERVICES_TO_WAIT[@]}"; do
    if is_service_running "$service"; then
        RUNNING_SERVICES+=("$service")
        log "⚠ $service läuft aktuell"
    else
        log "✓ $service ist nicht aktiv"
    fi
done

# ============================================================================
# PRÜFUNG: Laufende Prozesse (zusätzlich)
# ============================================================================
log ""
log "Prüfe laufende Prozesse & Lockfile..."

RUNNING_PROCESSES=0

# 1. Lockfile Check
if is_lockfile_held; then
    log "⚠ Globales Lockfile $LOCKFILE ist aktiv (Backup läuft!)"
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
elif [[ -f "$LOCKFILE" ]]; then
    log "✓ Lockfile existiert, ist aber nicht gesperrt (Stale?)"
fi

if check_process "entropywatcher" "entropywatcher.py"; then
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
fi

if check_process "rsync/rtb" "rsync.*backup"; then
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
fi

if check_process "pcloud-tools" "pcloud.*sync"; then
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
fi

# ============================================================================
# --DRY-RUN MODE
# ============================================================================
if [[ $DRY_RUN -eq 1 ]]; then
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "DRY-RUN MODUS (kein Shutdown)"
    log "════════════════════════════════════════════════════════════════════"
    
    if [[ ${#RUNNING_SERVICES[@]} -eq 0 ]] && [[ $RUNNING_PROCESSES -eq 0 ]]; then
        log "✓ Alle Services sind idle. Shutdown würde sofort ausgeführt"
        exit 0
    else
        log "⚠ Es laufen noch Services/Prozesse:"
        for svc in "${RUNNING_SERVICES[@]}"; do
            log "  - $svc ($(get_service_status "$svc"))"
        done
        log "  Bei normalem Aufruf würde auf diese gewartet"
        exit 2
    fi
fi

if [[ $RUNNING_PROCESSES -gt 0 ]]; then
    error "Backup/Lockfile oder manuelle Prozesse aktiv — Shutdown abgebrochen."
    exit 1
fi

# ============================================================================
# WARTEN: Auf Services
# ============================================================================
if [[ ${#RUNNING_SERVICES[@]} -gt 0 ]]; then
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "Warte auf ${#RUNNING_SERVICES[@]} laufende Service(s)..."
    log "════════════════════════════════════════════════════════════════════"
    
    FAILED_SERVICES=()
    for service in "${RUNNING_SERVICES[@]}"; do
        if ! wait_for_service "$service" "$TIMEOUT"; then
            FAILED_SERVICES+=("$service")
        fi
    done
    
    if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
        error "Services konnten nicht rechtzeitig beendet werden:"
        for svc in "${FAILED_SERVICES[@]}"; do
            error "  - $svc"
        done
        error "Shutdown abgebrochen!"
        exit 1
    fi
else
    log "✓ Keine laufenden Services gefunden"
fi

# ============================================================================
# FINALE PRÜFUNG
# ============================================================================
log ""
log "════════════════════════════════════════════════════════════════════"
log "Finale Prüfung vor Shutdown..."
log "════════════════════════════════════════════════════════════════════"

FINAL_CHECK_FAILED=0

for service in "${SERVICES_TO_WAIT[@]}"; do
    if is_service_running "$service"; then
        error "$service läuft noch!"
        FINAL_CHECK_FAILED=1
    else
        log "✓ $service ist beendet"
    fi
done

if [[ $FINAL_CHECK_FAILED -eq 1 ]]; then
    error "Finale Prüfung fehlgeschlagen!"
    exit 1
fi

# Check auf manuelle Prozesse vor dem harten Shutdown
if check_process "ANY-MANUAL" "entropywatcher.py|rsync.*backup|pcloud.*sync"; then
    error "Es laufen noch manuelle Prozesse (nicht via systemd)! Shutdown abgebrochen."
    exit 1
fi

log "✓ Alle Services beendet"

# ============================================================================
# SHUTDOWN (sofern nicht --no-shutdown)
# ============================================================================
if [[ $NO_SHUTDOWN -eq 1 ]]; then
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "✓ Alle Services beendet. --no-shutdown aktiv, fahre nicht herunter"
    log "════════════════════════════════════════════════════════════════════"
    exit 0
fi

log ""
log "════════════════════════════════════════════════════════════════════"
log "✓✓✓ Fahre Server sauber herunter..."
log "════════════════════════════════════════════════════════════════════"

sync

halt_at=$(($(date +%s) + SHUTDOWN_DELAY_SEC))
shutdown -h +1 "graceful_shutdown: Server wird heruntergefahren"

log "Shutdown geplant für $(date -d "@$halt_at" '+%F %T %Z' 2>/dev/null || date -r "$halt_at" '+%F %T %Z' 2>/dev/null || echo "@$halt_at")"
log "Shutdown initiiert. System fährt in 1 Minute herunter."

wait_for_scheduled_halt "$halt_at"
