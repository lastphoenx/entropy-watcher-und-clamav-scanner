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

shorten_rel() {
  local rel="$1"
  echo "$rel" \
    | sed -E \
      -e 's/([0-9]+)[[:space:]]*days?/\1d/g' \
      -e 's/([0-9]+)[[:space:]]*day/\1d/g' \
      -e 's/([0-9]+)[[:space:]]*hours?/\1h/g' \
      -e 's/([0-9]+)[[:space:]]*hour/\1h/g' \
      -e 's/([0-9]+)[[:space:]]*mins?/\1m/g' \
      -e 's/[[:space:]]+ago//g' \
      -e 's/[[:space:]]+left//g' \
      -e 's/[[:space:]]+/ /g' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
_compact() {
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-12.12s\n" "Unit" "Enabled" "Active" "Last" "Next"
  printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-12.12s-+-%-12.12s\n" \
    "-----------------------------------" "-------" "-------" "------------" "------------"
}

header_hybrid() {
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-30.30s\n" "Unit" "Enabled" "Active" "Last" "Next"
  printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-12.12s-+-%-30.30s\n" \
    "-----------------------------------" "-------" "-------" "------------" "------------------------------"
}

header_full() {
  printf _compact() {
  local unit="$1"
  declare -A info
  parse_timer_info "$unit" info
  
  local last_display="${info[last_rel]}"
  [[ "${info[last_rel]}" != "n/a" ]] && last_display="${info[last_rel]} ago"
  
  local next_display="${info[next_rel]}"
  [[ "${info[next_rel]}" != "n/a" ]] && next_display="${info[next_rel]} left"
  
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-12.12s\n" \
    "${unit}.timer" "${info[enabled]}" "${info[active]}" "$last_display" "$next_display"
}

print_row_hybrid() {
  local unit="$1"
  declare -A info
  parse_timer_info "$unit" info
  
  local last_display="${info[last_rel]}"
  [[ "${info[last_rel]}" != "n/a" ]] && last_display="${info[last_rel]} ago"
  
  # Next: Datum + relative Zeit
  local next_display
  if [[ "${info[next_dt]}" != "n/a" ]]; then
    local next_short="$(echo "${info[next_dt]}" | awk '{print $2, $3}')"  # Nur Datum + Zeit
    next_display="$next_short (${info[next_rel]})"
  else
    next_display="n/a"
  fi
  
  printf "%-35.35s | %-7.7s | %-7.7s | %-12.12s | %-30.30s\n" \
    "${unit}.timer" "${info[enabled]}" "${info[active]}" "$last_display" "$next_display"
}

print_row_full() {
  local unit="$1"
  declare -A info
  parse_timer_info "$unit" info
  
  local last_display next_display
  if [[ "${info[last_dt]}" != "n/a" ]]; then
    local last_short="$(echo "${info[last_dt]}" | awk '{print $2, $3}')"
    last_display="$last_short (${info[last_rel]})"
  else
    last_display="n/a"
  fi
  
  if [[ "${info[next_dt]}" != "n/a" ]]; then
    local next_short="$(echo "${info[next_dt]}" | awk '{print $2, $3}')"
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
rm -f "$TMPFILE"${info[last_rel]}" != "n/a" ]] && last_display="${info[last_rel]} ago"
  
  local next_display="${info[next_rel]}"
  [[ "${info[next_rel]}" != "n/a" ]] && next_display="${info[next_rel]} left"
  
  printf "│ %-35.35s │ %-7.7s │ %-7.7s │ %-12.12s │ %-12.12s │\n" \
    "${unit}.timer" "${info[enabled]}" "${info[active]}" "$last_display" "$next_display"Epoch timestamps für Sortierung
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
}

header() {
  if [[ "$STYLE" == "box" ]]; then
    echo "┌─────────────────────────────────────┬─────────┬─────────┬────────────────────────────────────────────┬────────────────────────────────────────────┐"
    printf "│ %-35.35s │ %-7.7s │ %-7.7s │ %-44.44s │ %-44.44s │\n" \
      "Unit" "Enabled" "Active" "LastRun" "NextRun"
    echo "├─────────────────────────────────────┼─────────┼─────────┼────────────────────────────────────────────┼────────────────────────────────────────────┤"
  else
    printf "%-35.35s | %-7.7s | %-7.7s | %-44.44s | %-44.44s\n" "Unit" "Enabled" "Active" "LastRun" "NextRun"
    printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-44.44s-+-%-44.44s\n" \
      "-----------------------------------" "-------" "-------" "--------------------------------------------" "--------------------------------------------"
  fi
}

print_row() {
  local unit="$1"
  local enabled active last next

  enabled="$(systemctl is-enabled "${unit}.timer" 2>/dev/null || echo "-")"
  active="$(systemctl is-active "${unit}.timer" 2>/dev/null || echo "-")"

  # systemctl list-timers Zeile 2 parsen - ROBUST nach Datumsformat!
  # Format: Sun 2025-12-07 11:20:22 CET 14h left Sun 2025-12-07 12:24:25 CET 22min ago entropywatcher-nas.timer
  local timer_line
  timer_line="$(systemctl list-timers "${unit}.timer" 2>/dev/null | sed -n '2p')"
  
  if [[ -z "$timer_line" ]]; then
    next="n/a"
    last="n/a"
  else
    local dates next_datetime last_datetime next_rel last_rel
    
    dates="$(echo "$timer_line" | grep -oE '[A-Za-z]+ [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')"
    next_datetime="$(echo "$dates" | head -1)"
    last_datetime="$(echo "$dates" | tail -1)"
    
    next_rel="$(echo "$timer_line" | sed -E 's/^.* CET ([^ ].* left).*/\1/')"
    last_rel="$(echo "$timer_line" | sed -E 's/^.* CET ([^ ].* ago) .*/\1/')"

    next_rel="$(shorten_rel "$next_rel")"
    last_rel="$(shorten_rel "$last_rel")"
    
    if [[ -n "$next_rel" ]]; then
      next_rel="$(shorten_rel "$next_rel")"
    fi
    if [[ -n "$last_rel" ]]; then
      last_rel="$(shorten_rel "$last_rel")"
    fi
    
    next="${next_datetime} (${next_rel})"
    last="${last_datetime} (${last_rel})"
    
    if [[ -z "$next_rel" ]]; then next="n/a"; fi
    if [[ -z "$last_rel" ]]; then last="n/a"; fi
  fi

  if [[ "$STYLE" == "box" ]]; then
    printf "│ %-35.35s │ %-7.7s │ %-7.7s │ %-44.44s │ %-44.44s │\n" \
      "${unit}.timer" "$enabled" "$active" "$last" "$next"
  else
    printf "%-35.35s | %-7.7s | %-7.7s | %-44.44s | %-44.44s\n" \
      "${unit}.timer" "$enabled" "$active" "$last" "$next"
  fi
}

footer() {
  if [[ "$STYLE" == "box" ]]; then
    echo "└─────────────────────────────────────┴─────────┴─────────┴────────────────────────────────────────────┴────────────────────────────────────────────┘"
  else
    printf "%-35.35s-+-%-7.7s-+-%-7.7s-+-%-44.44s-+-%-44.44s\n" \
      "-----------------------------------" "-------" "-------" "--------------------------------------------" "--------------------------------------------"
  fi
}

echo "EntropyWatcher / Backup-Pipeline Timer-Status"
echo
header
for u in "${SERVICES[@]}"; do
  print_row "$u"
done
footer
