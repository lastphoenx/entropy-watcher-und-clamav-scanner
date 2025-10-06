#!/bin/bash
set -euo pipefail

"${1:-}" >/dev/null 2>&1 || true

OFFSET_DAYS="${1:-}"
CONFIG_DIR="/opt/apps/entropywatcher/config"

# Services to check (schedule will be read from systemctl)
SERVICES=(
  "nas"
  "nas-av"
  "nas-av-weekly"
  "os"
  "os-av"
  "os-av-weekly"
)

get_health_window() {
  local svc="$1"
  local common_env="${CONFIG_DIR}/common.env"
  local env_file="${CONFIG_DIR}/${svc}.env"
  
  # Start with default
  local window="120"
  
  # Load from common.env first (if exists)
  if [[ -f "$common_env" ]]; then
    local common_val=$(grep -E '^HEALTH_WINDOW_MIN=' "$common_env" 2>/dev/null \
      | sed 's/^[^=]*=//' | sed 's/#.*$//' | tr -d ' ')
    [[ -n "$common_val" ]] && window="$common_val"
  fi
  
  # Override with service-specific value (if exists)
  if [[ -f "$env_file" ]]; then
    local service_val=$(grep -E '^HEALTH_WINDOW_MIN=' "$env_file" 2>/dev/null \
      | sed 's/^[^=]*=//' | sed 's/#.*$//' | tr -d ' ')
    [[ -n "$service_val" ]] && window="$service_val"
  fi
  
  echo "$window"
}

get_timer_schedule() {
  local svc="$1"
  systemctl cat "entropywatcher-${svc}.timer" 2>/dev/null \
    | grep -E '^OnCalendar=' \
    | sed 's/^OnCalendar=//' \
    | head -1 || echo ""
}

# Parse OnCalendar to determine schedule type and interval
parse_schedule() {
  local oncalendar="$1"
  
  # *-*-* *:20:00 → hourly
  if [[ "$oncalendar" =~ ^\*-\*-\*[[:space:]]+\*:[0-9]{2}:[0-9]{2}$ ]]; then
    echo "hourly:3600"
  # *-*-* HH:MM:SS → daily
  elif [[ "$oncalendar" =~ ^\*-\*-\*[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    echo "daily:86400"
  # Mon..Sun HH:MM → weekly pattern (any multi-day)
  elif [[ "$oncalendar" =~ ^[A-Z][a-z]+\.\.[A-Z][a-z]+[[:space:]]+ ]]; then
    echo "weekly:604800"
  # Sun HH:MM (single day) → weekly
  elif [[ "$oncalendar" =~ ^[A-Z][a-z]+[[:space:]]+ ]]; then
    echo "weekly:604800"
  else
    echo "unknown:86400"
  fi
}

get_schedule_display_from_oncalendar() {
  local oncalendar="$1"
  
  # *-*-* *:20:00 → "1h (:20)"
  if [[ "$oncalendar" =~ ^\*-\*-\*[[:space:]]+\*:([0-9]{2}):[0-9]{2}$ ]]; then
    local minute="${BASH_REMATCH[1]}"
    echo "1h (:${minute})"
  # *-*-* HH:MM:SS → "1d (HH:MM)"
  elif [[ "$oncalendar" =~ ^\*-\*-\*[[:space:]]+([0-9]{2}):([0-9]{2}):[0-9]{2}$ ]]; then
    local hour="${BASH_REMATCH[1]}"
    local minute="${BASH_REMATCH[2]}"
    echo "1d (${hour}:${minute})"
  # Mon..Sun HH:MM → "taegl (HH:MM)" (ASCII-only to avoid width issues)
  elif [[ "$oncalendar" =~ ^Mon\.\.Sun[[:space:]]+([0-9]{2}):([0-9]{2})$ ]]; then
    local hour="${BASH_REMATCH[1]}"
    local minute="${BASH_REMATCH[2]}"
    echo "taegl (${hour}:${minute})"
  # Mon..Sat HH:MM → "Mo-Sa (HH:MM)"
  elif [[ "$oncalendar" =~ ^Mon\.\.Sat[[:space:]]+([0-9]{2}):([0-9]{2})$ ]]; then
    local hour="${BASH_REMATCH[1]}"
    local minute="${BASH_REMATCH[2]}"
    echo "Mo-Sa (${hour}:${minute})"
  # Sun HH:MM → "So (HH:MM)"
  elif [[ "$oncalendar" =~ ^Sun[[:space:]]+([0-9]{2}):([0-9]{2})$ ]]; then
    local hour="${BASH_REMATCH[1]}"
    local minute="${BASH_REMATCH[2]}"
    echo "So (${hour}:${minute})"
  else
    echo "?"
  fi
}

get_last_run() {
  local svc="$1"
  systemctl list-timers "entropywatcher-${svc}.timer" 2>/dev/null \
    | awk 'NR==2 {
      for(i=5; i<=NF; i++) {
        if($i ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
          print $i, $(i+1);
          break;
        }
      }
    }' || echo ""
}

to_epoch() {
  local ts="$1"
  date -d "$ts" +%s 2>/dev/null || echo "0"
}

calc_last_run_before_target() {
  local oncalendar="$1"
  local target_epoch="$2"
  
  local target_date target_time target_hour target_min
  target_date=$(date -d "@${target_epoch}" "+%Y-%m-%d")
  target_time=$(date -d "@${target_epoch}" "+%H:%M")
  target_hour=$(date -d "@${target_epoch}" "+%H")
  target_min=$(date -d "@${target_epoch}" "+%M")
  
  local result_epoch
  
  # Pattern: *-*-* *:MM:SS (Stündlich)
  if [[ "$oncalendar" =~ ^\*-\*-\*[[:space:]]+\*:([0-9]{2}):[0-9]{2}$ ]]; then
    local pattern_min="${BASH_REMATCH[1]}"
    
    # Wenn target_min >= pattern_min, dann diese Stunde
    # Sonst vorherige Stunde
    if (( target_min >= pattern_min )); then
      result_epoch=$(date -d "$target_date $target_hour:$pattern_min:00" +%s)
    else
      #result_epoch=$(date -d "$target_date $target_hour:$pattern_min:00 - 1 hour" +%s)
      this_hour_epoch=$(date -d "$target_date $target_hour:$pattern_min:00" +%s)
      result_epoch=$((this_hour_epoch - 3600))


    fi
    echo "$result_epoch"
    return
  fi
  
  # Pattern: *-*-* HH:MM:SS (Täglich um feste Zeit)
  if [[ "$oncalendar" =~ ^\*-\*-\*[[:space:]]+([0-9]{2}):([0-9]{2}):[0-9]{2}$ ]]; then
    local pattern_hour="${BASH_REMATCH[1]}"
    local pattern_min="${BASH_REMATCH[2]}"
    
    # Wenn target heute nach der Laufzeit ist, dann heute
    # Sonst gestern
    local today_run_epoch=$(date -d "$target_date $pattern_hour:$pattern_min:00" +%s)
    if (( target_epoch >= today_run_epoch )); then
      result_epoch="$today_run_epoch"
    else
      result_epoch=$(date -d "$target_date $pattern_hour:$pattern_min:00 - 1 day" +%s)
    fi
    echo "$result_epoch"
    return
  fi
  
  # Pattern: Mon..Sat HH:MM (Mo-Fr täglich)
  if [[ "$oncalendar" =~ ^Mon\.\.Sat[[:space:]]+([0-9]{2}):([0-9]{2})$ ]]; then
    local pattern_hour="${BASH_REMATCH[1]}"
    local pattern_min="${BASH_REMATCH[2]}"
    
    # Rückwärts gehen bis wir einen Wochentag (Mo-Sa) finden
    local current_date="$target_date"
    local current_epoch="$target_epoch"
    
    while true; do
      local dow=$(date -d "@$current_epoch" +%u)  # 1=Mo, 7=So
      local run_time_epoch=$(date -d "$current_date $pattern_hour:$pattern_min:00" +%s)
      
      # Falls aktueller Tag ein Wochentag ist (1-6) und run_time <= target
      if (( dow <= 6 )) && (( run_time_epoch <= current_epoch )); then
        result_epoch="$run_time_epoch"
        echo "$result_epoch"
        return
      fi
      
      # Einen Tag zurück
      current_date=$(date -d "$current_date - 1 day" "+%Y-%m-%d")
      current_epoch=$((current_epoch - 86400))
    done
  fi
  
  # Pattern: Mon..Sun HH:MM (täglich)
  if [[ "$oncalendar" =~ ^Mon\.\.Sun[[:space:]]+([0-9]{2}):([0-9]{2})$ ]]; then
    local pattern_hour="${BASH_REMATCH[1]}"
    local pattern_min="${BASH_REMATCH[2]}"
    
    local today_run_epoch=$(date -d "$target_date $pattern_hour:$pattern_min:00" +%s)
    if (( target_epoch >= today_run_epoch )); then
      result_epoch="$today_run_epoch"
    else
      result_epoch=$(date -d "$target_date $pattern_hour:$pattern_min:00 - 1 day" +%s)
    fi
    echo "$result_epoch"
    return
  fi
  
  # Pattern: Sun HH:MM, Mon HH:MM etc. (wöchentlich an bestimmtem Tag)
  if [[ "$oncalendar" =~ ^(Sun|Mon|Tue|Wed|Thu|Fri|Sat)[[:space:]]+([0-9]{2}):([0-9]{2})$ ]]; then
    local pattern_day="${BASH_REMATCH[1]}"
    local pattern_hour="${BASH_REMATCH[2]}"
    local pattern_min="${BASH_REMATCH[3]}"
    
    # Map Wochentag zu DOW (1=Mo, 7=So)
    local target_dow
    case "$pattern_day" in
      Sun) target_dow=7 ;;
      Mon) target_dow=1 ;;
      Tue) target_dow=2 ;;
      Wed) target_dow=3 ;;
      Thu) target_dow=4 ;;
      Fri) target_dow=5 ;;
      Sat) target_dow=6 ;;
    esac
    
    # Rückwärts gehen bis wir den richtigen Wochentag finden
    local current_date="$target_date"
    local current_epoch="$target_epoch"
    
    while true; do
      local dow=$(date -d "@$current_epoch" +%u)
      local run_time_epoch=$(date -d "$current_date $pattern_hour:$pattern_min:00" +%s)
      
      # Falls aktueller Tag der richtige Wochentag ist und run_time <= target
      if (( dow == target_dow )) && (( run_time_epoch <= current_epoch )); then
        result_epoch="$run_time_epoch"
        echo "$result_epoch"
        return
      fi
      
      # Einen Tag zurück
      current_date=$(date -d "$current_date - 1 day" "+%Y-%m-%d")
      current_epoch=$((current_epoch - 86400))
    done
  fi
  
  # Fallback (sollte nicht vorkommen)
  echo "$target_epoch"
}

get_backup_base_date() {
  local base_date
  if [[ -z "${OFFSET_DAYS}" ]]; then
    base_date="$(systemctl list-timers backup-pipeline.timer 2>/dev/null \
      | awk 'NR==2 {print $2}')"
  else
    base_date="$(date -d "today +${OFFSET_DAYS} day" +%Y-%m-%d)"
  fi
  echo "$base_date"
}

slot_epoch() {
  local base_date="$1"
  local time_hm="$2"
  date -d "$base_date $time_hm" +%s
}

# Calculate next run based on schedule type
calc_next_run() {
  local last_epoch="$1"
  local target_epoch="$2"
  local schedule="$3"
  local target_date="$4"
  
  case "$schedule" in
    hourly)
      # Runs every hour at :20
      # Find FIRST run AFTER target_epoch
      local next=$last_epoch
      while (( next <= target_epoch )); do
        next=$((next + 3600))  # +1 hour
      done
      echo "$next"
      ;;
    daily)
      # Runs once per day at fixed time (e.g., 03:40)
      # Find FIRST run AFTER target_epoch
      local next=$last_epoch
      while (( next <= target_epoch )); do
        next=$((next + 86400))  # +1 day
      done
      echo "$next"
      ;;
    mon-sat)
      # Runs Mon-Sat at fixed time
      # Find FIRST run AFTER target_epoch
      local next=$last_epoch
      while (( next <= target_epoch )); do
        next=$((next + 86400))
        local dow=$(date -d "@$next" +%u)  # 1=Mon, 7=Sun
        # If next would be Sunday, skip to Monday
        if [[ "$dow" == "7" ]]; then
          next=$((next + 86400))
        fi
      done
      echo "$next"
      ;;
    weekly)
      # Runs once per week on specific day (e.g., Sunday)
      # Find FIRST run AFTER target_epoch
      local next=$last_epoch
      while (( next <= target_epoch )); do
        next=$((next + 604800))  # +7 days
      done
      echo "$next"
      ;;
  esac
}



SLOTS=("04:00" "12:00" "20:00")
BACKUP_BASE_DATE="$(get_backup_base_date)"

echo "════════════════════════════════════════════════════════════════════════════"
printf "  pCloud Backup Pipeline Forecast für: %s\n" "$BACKUP_BASE_DATE"
echo "  Pipeline-Starts: 04:00 / 12:00 / 20:00"
echo "════════════════════════════════════════════════════════════════════════════"

for slot in "${SLOTS[@]}"; do
  target_epoch="$(slot_epoch "$BACKUP_BASE_DATE" "$slot")"
  target_str="$(date -d "@${target_epoch}" "+%Y-%m-%d %H:%M")"

  echo "───────────────────────────────────────────────────────────────────────────"
  printf "  Pipeline-Start: %s\n" "$target_str"
  echo "───────────────────────────────────────────────────────────────────────────"
  printf "%-13s | %-19s | %-5s | %-13s | %6s | %-6s\n" "Service" "Last Scan" "Age" "Schedule" "Window" "Status"
  printf "%-13s | %-19s | %-5s | %-13s | %6s | %-6s\n" "-------------" "-------------------" "-----" "-------------" "------" "------"

  for svc in "${SERVICES[@]}"; do
    # Read actual timer configuration
    oncalendar="$(get_timer_schedule "$svc" || true)"
    
    if [[ -z "$oncalendar" ]]; then
      printf "%-13s | %-19s | %-5s | %-13s | %6s | %-6s\n" "$svc" "no timer" "-" "-" "-" "?"
      continue
    fi
    
    # Parse schedule display from OnCalendar
    schedule_display="$(get_schedule_display_from_oncalendar "$oncalendar")"
    
    last_run_str="$(get_last_run "$svc" || true)"
    window_min="$(get_health_window "$svc")"
    
    if [[ -z "${last_run_str:-}" ]]; then
      printf "%-13s | %-19s | %-5s | %-13s | %6s | %-6s\n" "$svc" "unknown" "-" "$schedule_display" "$window_min" "?"
      continue
    fi

    last_epoch="$(to_epoch "$last_run_str" 2>/dev/null || echo "0")"
    
    if [[ "$last_epoch" == "0" ]]; then
      printf "%-13s | %-19s | %-5s | %-13s | %6s | %-6s\n" "$svc" "parse-error" "-" "$schedule_display" "$window_min" "?"
      continue
    fi

    # Find LAST scan BEFORE pipeline start using OnCalendar pattern
    last_scan_before=$(calc_last_run_before_target "$oncalendar" "$target_epoch")
    
    last_scan_str="$(date -d "@${last_scan_before}" "+%Y-%m-%d %H:%M")"
    age_at_pipeline_min=$(( (target_epoch - last_scan_before) / 60 ))
    
    # Format age display
    if (( age_at_pipeline_min < 60 )); then
      age_display="${age_at_pipeline_min}m"
    elif (( age_at_pipeline_min < 1440 )); then
      age_hours=$((age_at_pipeline_min / 60))
      age_display="${age_hours}h"
    else
      age_days=$((age_at_pipeline_min / 1440))
      age_display="${age_days}d"
    fi

    # Determine status based on age at pipeline time (same logic as ew_status.sh)
    three_quarter_window=$((window_min * 3 / 4))
    
    if (( age_at_pipeline_min < three_quarter_window )); then
      status="GREEN"
    elif (( age_at_pipeline_min < window_min )); then
      status="YELLOW"
    else
      status="RED"
    fi

    printf "%-13s | %-19s | %-5s | %-13s | %6d | %-6s\n" "$svc" "$last_scan_str" "$age_display" "$schedule_display" "$window_min" "$status"
  done

  echo
done

echo "════════════════════════════════════════════════════════════════════════════"
