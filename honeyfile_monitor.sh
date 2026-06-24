#!/usr/bin/env bash
set -euo pipefail

AUDIT_KEY="honeyfile_access"
ALERT_FLAG="${HONEYFILE_ALERT_FLAG:-/var/lib/honeyfile_alert}"
LAST_PROCESSED="${HONEYFILE_LAST_PROCESSED:-/var/lib/honeyfile_last_alert_ts}"
LOG_FILE="${HONEYFILE_LOG_FILE:-/var/log/honeyfile_monitor.log}"
COMMON_ENV="${COMMON_ENV:-/opt/apps/entropywatcher/config/common.env}"
HONEYFILE_PATHS_CONFIG="/opt/apps/entropywatcher/config/honeyfile_paths"

log() {
    local msg="[$(date '+%F %T')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# ausearch --start: Epoch in LAST_PROCESSED -> lesbares Datum
_ausearch_start_arg() {
    if [[ ! -f "$LAST_PROCESSED" ]]; then
        echo "recent"
        return
    fi
    local ts
    ts=$(tr -d '[:space:]' < "$LAST_PROCESSED")
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        date -d "@$ts" '+%m/%d/%Y %H:%M:%S' 2>/dev/null || echo "recent"
    else
        echo "$ts"
    fi
}

# Tier 2/3: ganze Audit-Bloecke ohne honeyfile_monitor (eigener Config-Read)
_filter_audit_output() {
    awk '
        BEGIN { block = "" }
        /^----/ {
            if (block != "" && block !~ /honeyfile_monitor/) print block
            block = $0 "\n"
            next
        }
        { block = block $0 "\n" }
        END {
            if (block != "" && block !~ /honeyfile_monitor/) print block
        }
    '
}

_ausearch_filtered() {
    local key="$1"
    local start="$2"
    ausearch -k "$key" --start "$start" 2>/dev/null | _filter_audit_output || true
}

load_mail_config() {
    if [[ -f "$COMMON_ENV" ]]; then
        # shellcheck source=/dev/null
        source "$COMMON_ENV"
    fi
}

send_alert_email() {
    local events="$1"
    local subject="$2"

    if [[ "${MAIL_ENABLE:-0}" != "1" ]]; then
        log "ℹ️  Mail deaktiviert (MAIL_ENABLE=0)"
        return 0
    fi

    if [[ -z "${MAIL_TO:-}" ]] || [[ -z "${MAIL_SMTP_HOST:-}" ]]; then
        log "⚠️  Mail-Konfiguration unvollständig (MAIL_TO oder MAIL_SMTP_HOST fehlt)"
        return 1
    fi

    local smtp_host="${MAIL_SMTP_HOST}"
    local smtp_port="${MAIL_SMTP_PORT:-587}"
    local smtp_user="${MAIL_USER:-}"
    local smtp_pass="${MAIL_PASS:-}"
    local mail_to="${MAIL_TO}"
    local use_tls="${MAIL_STARTTLS:-1}"

    python3 - <<PYEOF
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import sys

try:
    msg = MIMEMultipart()
    msg['From'] = "${smtp_user:-honeyfile-monitor@$(hostname)}"
    msg['To'] = "${mail_to}"
    msg['Subject'] = "${subject}"

    body = """🚨 HONEYFILE INTRUSION DETECTED

Hostname: $(hostname)
Time: $(date)
Alert Level: CRITICAL

Audit Events:
${events}

---
EntropyWatcher Honeyfile Intrusion Detection System
"""

    msg.attach(MIMEText(body, 'plain'))

    with smtplib.SMTP("${smtp_host}", ${smtp_port}, timeout=10) as server:
        if ${use_tls} == 1:
            server.starttls()

        if "${smtp_user}":
            server.login("${smtp_user}", "${smtp_pass}")

        server.send_message(msg)

    print("✓ Alert-Email versendet")
    sys.exit(0)

except Exception as e:
    print(f"✗ Mail-Versand fehlgeschlagen: {e}")
    sys.exit(1)
PYEOF
}

_log_honeyfile_count() {
    if [[ ! -f "$HONEYFILE_PATHS_CONFIG" ]]; then
        return
    fi
    local count
    count=$(grep -cve '^\s*$' -e '^\s*#' "$HONEYFILE_PATHS_CONFIG" 2>/dev/null || echo 0)
    log "✓ ${count} Honeyfile(s) konfiguriert"
}

# Config nur pruefen (stat), nicht lesen — vermeidet Tier-2-Self-Trigger
if [[ ! -f "$HONEYFILE_PATHS_CONFIG" ]]; then
    log "❌ Config nicht gefunden: $HONEYFILE_PATHS_CONFIG"
    exit 1
fi

START=$(_ausearch_start_arg)
if [[ -f "$LAST_PROCESSED" ]]; then
    log "Prüfe auf Zugriffe seit letzter Verarbeitung..."
else
    log "Erste Ausführung - prüfe letzte 10 min..."
fi

EVENTS=$(_ausearch_filtered "$AUDIT_KEY" "$START")

CONFIG_ACCESS=$(_ausearch_filtered "honeyfile_config_access" "$START")
AUDIT_TAMPERING=$(_ausearch_filtered "audit_tampering" "$START")
AUDIT_CONFIG_CHANGE=$(_ausearch_filtered "audit_config_change" "$START")

ALL_EVENTS="$EVENTS"
if [[ -n "$CONFIG_ACCESS" ]]; then
    ALL_EVENTS="${ALL_EVENTS}\n\n=== TIER 2: CONFIG ACCESS DETECTED ===\n${CONFIG_ACCESS}"
fi
if [[ -n "$AUDIT_TAMPERING" ]]; then
    ALL_EVENTS="${ALL_EVENTS}\n\n=== TIER 3: AUDIT TAMPERING DETECTED ===\n${AUDIT_TAMPERING}"
fi
if [[ -n "$AUDIT_CONFIG_CHANGE" ]]; then
    ALL_EVENTS="${ALL_EVENTS}\n\n=== TIER 3: AUDIT CONFIG CHANGE DETECTED ===\n${AUDIT_CONFIG_CHANGE}"
fi

if [[ -n "$ALL_EVENTS" ]]; then
    log "⚠️  SECURITY EVENT ERKANNT!"
    log ""
    echo -e "$ALL_EVENTS" | tee -a "$LOG_FILE"
    log ""

    touch "$ALERT_FLAG"
    log "✓ Alert-Flag gesetzt: $ALERT_FLAG"

    if [[ -n "$AUDIT_TAMPERING" ]] || [[ -n "$AUDIT_CONFIG_CHANGE" ]]; then
        SUBJECT="🚨🔥 CRITICAL: AUDIT TAMPERING DETECTED on $(hostname)"
    elif [[ -n "$CONFIG_ACCESS" ]]; then
        SUBJECT="⚠️ CONFIG SNIFFING: Honeyfile Config accessed on $(hostname)"
    else
        SUBJECT="🚨 HONEYFILE ACCESS DETECTED on $(hostname)"
    fi

    load_mail_config
    if send_alert_email "$ALL_EVENTS" "$SUBJECT"; then
        log "✓ Alert-Email versendet"
        date +%s > "$LAST_PROCESSED"
        log "✓ Timestamp aktualisiert - verhindert Duplikat-Mails"
    else
        log "⚠️  Mail-Versand fehlgeschlagen"
    fi

    _log_honeyfile_count
    exit 1
else
    log "✓ Keine verdächtigen Zugriffe"
    date +%s > "$LAST_PROCESSED"
    _log_honeyfile_count
    exit 0
fi
