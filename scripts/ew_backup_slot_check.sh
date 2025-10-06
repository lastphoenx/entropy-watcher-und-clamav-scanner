#!/bin/bash
set -euo pipefail

"${1:-}" >/dev/null 2>&1 || true

# Bewertet, ob für einen Backup-Tag alle Backup-Slots
# (04:00, 12:00, 20:00) die relevanten EntropyWatcher-Services
# voraussichtlich innerhalb ihres HEALTH_WINDOW_MIN liegen.
# Logik:
#   - Default (kein Argument): Backup-Tag wird aus NEXT von
#     backup-pipeline.timer abgeleitet (nächster Backup-Tag).
#   - Mit Argument N: Zieltag = heute + N Tage (N=0/1/2,...).
#   - Für jeden Service: ausgehend von LAST aus systemd list-timers
#     vorwärts in Schritten der bekannten Frequenz springen, solange
#     NEXT <= Ziel-Slot-Zeitpunkt liegt; der letzte so gefundene Lauf
#     ist der „effektiv letzte“ vor dem Slot.

OFFSET_DAYS="${1:-}"  # leer = aus backup-pipeline.timer ableiten
CONFIG_DIR="/opt/apps/entropywatcher/config"

# Services, die für das Safety-Gate kritisch sind + ihre Frequenz in Minuten
SERVICES=(
  "nas:60"       # stündlich
  "nas-av:1440"  # täglich
)

# HEALTH_WINDOW_MIN aus service-env holen (Kommentare abschneiden)
get_health_window() {
  local svc="$1"
  local env_file="${CONFIG_DIR}/${svc}.env"
  grep -E '^HEALTH_WINDOW_MIN=' "$env_file" \
    | sed 's/^[^=]*=//' \
    | sed 's/#.*$//' \
    | tr -d ' '
}

# Letzten Lauf aus systemd-Timer holen ("YYYY-MM-DD HH:MM:SS")
get_last_run_from_timer() {
  local svc="$1"
  # systemctl list-timers Format variiert
  # Wir suchen nach dem ersten Feld mit YYYY-MM-DD Pattern nach Position 5
  systemctl list-timers "entropywatcher-${svc}.timer" 2>/dev/null \
    | awk 'NR==2 {
      for(i=5; i<=NF; i++) {
        if($i ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
          print $i, $(i+1);
          break;
        }
      }
    }'
}

# Letzten ECHTEN Scan vor einem Zeitpunkt aus der DB holen
get_last_scan_from_db() {
  local svc="$1"
  local before_epoch="$2"
  local before_ts
  before_ts="$(date -d "@${before_epoch}" "+%Y-%m-%d %H:%M:%S")"
  
  # Hole DB-Credentials: zuerst common.env, dann service env (service übersteuert)
  local env_common="${CONFIG_DIR}/common.env"
  local env_file="${CONFIG_DIR}/${svc}.env"
  if [[ ! -f "$env_file" && ! -f "$env_common" ]]; then
    return 1
  fi

  # Parse beide .env Dateien mit python-dotenv wie in entropywatcher.py
  local db_creds
  db_creds="$(python3 - <<PY
from dotenv import dotenv_values
import json, os
env_common = '${env_common}'
env_file = '${env_file}'
try:
    common = dotenv_values(env_common) if env_common and os.path.exists(env_common) else {}
except Exception:
    common = {}
try:
    svcvals = dotenv_values(env_file) if env_file and os.path.exists(env_file) else {}
except Exception:
    svcvals = {}
merged = dict(common)
merged.update(svcvals)
print(json.dumps({
    'host': merged.get('DB_HOST','localhost'),
    'port': merged.get('DB_PORT','3306'),
    'name': merged.get('DB_NAME','entropywatcher'),
    'user': merged.get('DB_USER','entropyuser'),
    'pass': merged.get('DB_PASS','')
}))
PY
  )"

  if [[ -z "$db_creds" ]]; then
    return 1
  fi

  local db_host db_port db_name db_user db_pass
  db_host="$(echo "$db_creds" | python3 -c "import sys, json; print(json.load(sys.stdin)['host'])")"
  db_port="$(echo "$db_creds" | python3 -c "import sys, json; print(json.load(sys.stdin)['port'])")"
  db_name="$(echo "$db_creds" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'])")"
  db_user="$(echo "$db_creds" | python3 -c "import sys, json; print(json.load(sys.stdin)['user'])")"
  db_pass="$(echo "$db_creds" | python3 -c "import sys, json; print(json.load(sys.stdin)['pass'])")"
  
  # MariaDB-Query via mysql CLI
  local result
  result=$(mysql -h "$db_host" -P "$db_port" -u "$db_user" -p"$db_pass" "$db_name" -N -e "SELECT started_at FROM scan_summary WHERE source = '$svc' AND started_at < '$before_ts' ORDER BY started_at DESC LIMIT 1;" 2>/dev/null | head -1)
  
  if [[ -n "$result" ]]; then
    echo "[DB-Query] service=$svc before=$before_ts result=$result" >&2
    echo "$result"
  fi
}

# Timer-Status prüfen
is_timer_ready() {
  local svc="$1"
  local enabled active
  enabled="$(systemctl is-enabled "entropywatcher-${svc}.timer" 2>/dev/null || echo "disabled")"
  active="$(systemctl is-active "entropywatcher-${svc}.timer" 2>/dev/null || echo "inactive")"
  
  if [[ "$enabled" == "enabled" && "$active" == "active" ]]; then
    return 0
  else
    return 1
  fi
}

# Zeitstring "YYYY-MM-DD HH:MM:SS" in Epoch konvertieren
to_epoch() {
  local ts="$1"
  date -d "$ts" +%s
}

# Backup-Basisdatum ermitteln (YYYY-MM-DD)
get_backup_base_date() {
  local base_date
  if [[ -z "${OFFSET_DAYS}" ]]; then
    # Default: aus NEXT von backup-pipeline.timer ableiten
    # Format: NEXT(Day) NEXT(Date) NEXT(Time) ...
    # NEXT(Date) ist Spalte 2
    base_date="$(systemctl list-timers backup-pipeline.timer 2>/dev/null \
      | awk 'NR==2 {print $2}')"
  else
    # Expliziter Offset: heute + OFFSET_DAYS
    base_date="$(date -d "today +${OFFSET_DAYS} day" +%Y-%m-%d)"
  fi
  echo "$base_date"
}

# Epoch eines Ziel-Slots (Basisdatum + Uhrzeit)
slot_epoch() {
  local base_date="$1"   # YYYY-MM-DD
  local time_hm="$2"     # z.B. 04:00
  date -d "$base_date $time_hm" +%s
}

SLOTS=("04:00" "12:00" "20:00")

BACKUP_BASE_DATE="$(get_backup_base_date)"

echo "Backup-Slot-Check für Backup-Tag ${BACKUP_BASE_DATE}"
echo

for slot in "${SLOTS[@]}"; do
  target_epoch="$(slot_epoch "$BACKUP_BASE_DATE" "$slot")"
  target_str="$(date -d "@${target_epoch}" "+%Y-%m-%d %H:%M")"

  echo "Slot ${slot} (${target_str})"
  printf "%-8s %-29s %-8s %-10s\n" "Service" "EffLastRun" "Window" "OK?"

  for entry in "${SERVICES[@]}"; do
    IFS=":" read -r svc freq_min <<<"$entry"

    window_min="$(get_health_window "$svc" || true)"
    
    if [[ -z "${window_min:-}" ]]; then
      printf "%-8s %-29s %-8s %-10s\n" "$svc" "n/a" "n/a" "UNKNOWN"
      continue
    fi

    now_epoch="$(date +%s)"
    freq_sec=$((freq_min * 60))
    
    # Unterscheide: Slot in Vergangenheit oder Zukunft?
    if (( target_epoch <= now_epoch )); then
      # VERGANGENHEIT: Hole echte Scan-Zeit aus DB
      eff_last_str="$(get_last_scan_from_db "$svc" "$target_epoch" || true)"
      
      if [[ -z "$eff_last_str" ]]; then
        printf "%-8s %-29s %-8s %-10s\n" "$svc" "NO-DB-DATA" "$window_min" "FAIL"
        continue
      fi
      
      last_epoch="$(to_epoch "$eff_last_str" 2>/dev/null || echo "0")"
      if [[ "$last_epoch" == "0" ]]; then
        printf "%-8s %-29s %-8s %-10s\n" "$svc" "DB-DATE-ERROR" "$window_min" "FAIL"
        continue
      fi
      
      eff_last_str="$(date -d "@${last_epoch}" "+%Y-%m-%d %H:%M:%S")"
      age_min=$(( (target_epoch - last_epoch) / 60 ))

      if (( age_min < window_min )); then
        status="OK"
      else
        status="OLD"
      fi
      
    else
      # ZUKUNFT: Prüfe Timer-Status + simuliere
      if ! is_timer_ready "$svc"; then
        printf "%-8s %-29s %-8s %-10s\n" "$svc" "TIMER-DISABLED" "$window_min" "FAIL"
        continue
      fi
      
      last_run_str="$(get_last_run_from_timer "$svc" || true)"
      if [[ -z "${last_run_str:-}" ]]; then
        printf "%-8s %-29s %-8s %-10s\n" "$svc" "PARSE-ERROR" "$window_min" "FAIL"
        continue
      fi
      
      last_epoch="$(to_epoch "$last_run_str" 2>/dev/null || echo "0")"
      if [[ "$last_epoch" == "0" ]]; then
        printf "%-8s %-29s %-8s %-10s\n" "$svc" "DATE-ERROR" "$window_min" "FAIL"
        continue
      fi

      # Vorwärts springen bis kurz vor Slot
      next_epoch=$((last_epoch + freq_sec))
      while (( next_epoch <= target_epoch )); do
        last_epoch=$next_epoch
        next_epoch=$((next_epoch + freq_sec))
      done

      eff_last_str="$(date -d "@${last_epoch}" "+%Y-%m-%d %H:%M")"
      age_min=$(( (target_epoch - last_epoch) / 60 ))

      if (( age_min < window_min )); then
        status="OK"
      else
        status="OLD"
      fi
    fi

    printf "%-8s %-29s %-8s %-10s\n" "$svc" "$eff_last_str" "$window_min" "$status"
  done

  echo
done
