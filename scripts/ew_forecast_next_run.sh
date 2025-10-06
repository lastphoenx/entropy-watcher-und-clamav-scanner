#!/bin/bash
set -euo pipefail

# Reines Infrastruktur-Status-Skript für EntropyWatcher / Backup-Pipeline
# Anzeige-Stil: "ascii" (stabil) oder "box" (schön). Override via ENV: STYLE=box
STYLE="${STYLE:-ascii}"

SERVICES=(
  "entropywatcher-nas"
  "entropywatcher-nas-av"
  "entropywatcher-nas-av-weekly"
  "entropywatcher-os"
  "entropywatcher-os-av"
  "entropywatcher-os-av-weekly"
  "backup-pipeline"
)

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
      -e 's/[[:space:]]+//g'
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
