#!/bin/bash
set -euo pipefail

# ==============================================================================
# ew_forecast_next_run.sh - EntropyWatcher/Backup-Pipeline Timer Status
# ==============================================================================
# Zeigt systemd-Timer-Status mit flexiblen Output-Formaten
#
# Usage:
#   ew_forecast_next_run.sh [--format FORMAT] [--sort FIELD]
#
# Formats:
#   compact       - Nur relative Zeiten (default, platzsparend)
#   hybrid        - Relative Zeit für Last, absolutes Datum für Next
#   full          - Vollständige Datum+Zeit-Informationen
#   box           - Kompakt mit Unicode-Rahmen
#
# Sort:
#   next          - Nach nächstem Lauf (default)
#   last          - Nach letztem Lauf
#   name          - Alphabetisch nach Service-Name
# ==============================================================================

# Defaults
FORMAT="${FORMAT:-compact}"
SORT_BY="${SORT_BY:-next}"

# Parse Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --sort)
      SORT_BY="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--format FORMAT] [--sort FIELD]"
      echo ""
      echo "Formats: compact (default), hybrid, full, box"
      echo "Sort:    next (default), last, name"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage"
      exit 1
      ;;
  esac
done

# Validate format
case "$FORMAT" in
  compact|hybrid|full|box) ;;
  *)
    echo "Error: Invalid format '$FORMAT'. Use: compact, hybrid, full, box"
    exit 1
    ;;
esac

SERVICES=(
  "entropywatcher-nas"
  "entropywatcher-nas-av"
  "entropywatcher-nas-av-weekly"
  "entropywatcher-os"
  "entropywatcher-os-av"
  "entropywatcher-os-av-weekly"
  "backup-pipeline"
)

# Temporary file for sorting
TMPFILE=$(mktemp)

# Format delta in seconds as XXd XXh XXm (always 2-digit)
format_delta() {
  local seconds="$1"
  
  if [[ "$seconds" -eq 0 ]]; then
    echo "n/a"
    return
  fi
  
  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  local mins=$(((seconds % 3600) / 60))
  
  printf "%02dd %02dh %02dm" "$days" "$hours" "$mins"
}

parse_timer_info() {
  local unit="$1"
  local -n result=$2
  
  result[enabled]="$(systemctl is-enabled "${unit}.timer" 2>/dev/null || echo "-")"
  result[active]="$(systemctl is-active "${unit}.timer" 2>/dev/null || echo "-")"
  
  local timer_line
  timer_line="$(systemctl list-timers "${unit}.timer" 2>/dev/null | sed -n '2p')"
  
  if [[ -z "$timer_line" ]]; then
    result[next_dt]="n/a"
    result[last_dt]="n/a"
    result[next_delta]="n/a"
    result[last_delta]="n/a"
    result[next_epoch]=0
    result[last_epoch]=0
    return
  fi
  
  # Parse datetime (robust gegen verschiedene Zeitzonen)
  local dates
  dates="$(echo "$timer_line" | grep -oE '[A-Za-z]+ [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')"
  result[next_dt]="$(echo "$dates" | head -1)"
  result[last_dt]="$(echo "$dates" | tail -1)"
  
  # Epoch timestamps
  local current_epoch
  current_epoch=$(date +%s)
  
  if [[ "${result[next_dt]}" != "n/a" ]]; then
    result[next_epoch]=$(date -d "${result[next_dt]}" +%s 2>/dev/null || echo 0)
  else
    result[next_epoch]=0
  fi
  
  if [[ "${result[last_dt]}" != "n/a" ]]; then
    result[last_epoch]=$(date -d "${result[last_dt]}" +%s 2>/dev/null || echo 0)
  else
    result[last_epoch]=0
  fi
  
  # Delta calculation: format as XXd XXh XXm
  local next_delta_sec last_delta_sec
  
  if [[ ${result[next_epoch]} -gt 0 ]]; then
    next_delta_sec=$((result[next_epoch] - current_epoch))
    [[ $next_delta_sec -lt 0 ]] && next_delta_sec=0
    result[next_delta]="$(format_delta $next_delta_sec)"
  else
    result[next_delta]="n/a"
  fi
  
  if [[ ${result[last_epoch]} -gt 0 ]]; then
    last_delta_sec=$((current_epoch - result[last_epoch]))
    [[ $last_delta_sec -lt 0 ]] && last_delta_sec=0
    result[last_delta]="$(format_delta $last_delta_sec)"
  else
    result[last_delta]="n/a"
  fi
}

header_compact() {
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-12.12s\n" "Unit" "Enabled" "Active" "Last" "Next"
  printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-12.12s-+-%-12.12s\n" \
    "-----------------------------------" "-------" "-------" "------------" "------------"
}

header_hybrid() {
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-38.38s\n" "Unit" "Enabled" "Active" "Last" "Next"
  printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-12.12s-+-%-38.38s\n" \
    "-----------------------------------" "-------" "-------" "------------" "--------------------------------------"
}

header_full() {
  printf "%-35.35s | %-7.7s | %-7.7s | %-38.38s | %-38.38s\n" "Unit" "Enabled" "Active" "LastRun" "NextRun"
  printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-38.38s-+-%-38.38s\n" \
    "-----------------------------------" "-------" "-------" "--------------------------------------" "--------------------------------------"
}

header_box() {
  echo "┌─────────────────────────────────────┬─────────┬─────────┬──────────────┬──────────────┐"
  printf "│ %-35.35s │ %-7.7s │ %-7.7s │ %-12.12s │ %-12.12s │\n" \
    "Unit" "Enabled" "Active" "Last" "Next"
  echo "├─────────────────────────────────────┼─────────┼─────────┼──────────────┼──────────────┤"
}

footer_box() {
  echo "└─────────────────────────────────────┴─────────┴─────────┴──────────────┴──────────────┘"
}

print_row_compact() {
  local unit="$1"
  declare -A info
  parse_timer_info "$unit" info
  
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-12.12s\n" \
    "${unit}.timer" "${info[enabled]}" "${info[active]}" "${info[last_delta]}" "${info[next_delta]}"
}

print_row_hybrid() {
  local unit="$1"
  declare -A info
  parse_timer_info "$unit" info
  
  # Next: Datum + Zeit + Delta
  local next_display
  if [[ "${info[next_dt]}" != "n/a" ]]; then
    local next_short="$(echo "${info[next_dt]}" | awk '{print $2, $3}')"  # Nur Datum + Zeit
    next_display="$next_short (${info[next_delta]})"
  else
    next_display="n/a"
  fi
  
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-38.38s\n" \
    "${unit}.timer" "${info[enabled]}" "${info[active]}" "${info[last_delta]}" "$next_display"
}

print_row_full() {
  local unit="$1"
  declare -A info
  parse_timer_info "$unit" info
  
  local last_display next_display
  if [[ "${info[last_dt]}" != "n/a" ]]; then
    local last_short="$(echo "${info[last_dt]}" | awk '{print $2, $3}')"
    last_display="$last_short (${info[last_delta]})"
  else
    last_display="n/a"
  fi
  
  if [[ "${info[next_dt]}" != "n/a" ]]; then
    local next_short="$(echo "${info[next_dt]}" | awk '{print $2, $3}')"
    next_display="$next_short (${info[next_delta]})"
  else
    next_display="n/a"
  fi
  
  printf "%-35.35s | %-7.7s | %-7.7s | %-38.38s | %-38.38s\n" \
  printf "│ %-35.35s │ %-7.7s │ %-7.7s │ %-12.12s │ %-12.12s │\n" \
    "${unit}.timer" "${info[enabled]}" "${info[active]}" "${info[last_delta]}" "${info[next_delta]}"
}

# Main execution
echo "EntropyWatcher / Backup-Pipeline Timer-Status"
echo ""

# Collect data with sort keys
for u in "${SERVICES[@]}"; do
  declare -A info
  parse_timer_info "$u" info
  
  # Sort key selection
  case "$SORT_BY" in
    next)
      sort_key="${info[next_epoch]}"
      ;;
    last)
      sort_key="${info[last_epoch]}"
      ;;
    name)
      sort_key="$u"
      ;;
    *)
      sort_key="${info[next_epoch]}"
      ;;
  esac
  
  # Write to temp file: sort_key|unit
  echo "$sort_key|$u" >> "$TMPFILE"
done

# Sort and display
case "$FORMAT" in
  compact)
    header_compact
    sort -t'|' -k1 -n "$TMPFILE" | while IFS='|' read -r _ unit; do
      print_row_compact "$unit"
    done
    ;;
  hybrid)
    header_hybrid
    sort -t'|' -k1 -n "$TMPFILE" | while IFS='|' read -r _ unit; do
      print_row_hybrid "$unit"
    done
    ;;
  full)
    header_full
    sort -t'|' -k1 -n "$TMPFILE" | while IFS='|' read -r _ unit; do
      print_row_full "$unit"
    done
    ;;
  box)
    header_box
    sort -t'|' -k1 -n "$TMPFILE" | while IFS='|' read -r _ unit; do
      print_row_box "$unit"
    done
    footer_box
    ;;
esac

# Cleanup
rm -f "$TMPFILE"
