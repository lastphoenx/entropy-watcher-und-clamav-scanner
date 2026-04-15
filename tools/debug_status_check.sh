#!/usr/bin/env bash
# =====================================================
# Debug: Status-Check für nas und nas-av analysieren
# =====================================================

set -euo pipefail

DB_NAME="entropywatcher"

echo "═══════════════════════════════════════════════════════"
echo "   EntropyWatcher Status Debug (nas vs nas-av)"
echo "═══════════════════════════════════════════════════════"
echo ""

# 1. Prüfe files Tabelle nach source
echo "📋 1. Files Tabelle - Einträge nach source"
echo "─────────────────────────────────────────────────────"
mysql -t -e "
  SELECT 
    source,
    COUNT(*) AS total,
    SUM(flagged) AS flagged_count
  FROM ${DB_NAME}.files
  GROUP BY source
  ORDER BY source
" 2>/dev/null

echo ""

# 2. Flagged files in den letzten 2 Stunden (Standard-Fenster)
echo "🚨 2. Flagged Files (letzte 2 Stunden)"
echo "─────────────────────────────────────────────────────"
mysql -t -e "
  SELECT 
    source,
    COUNT(*) AS flagged_recent
  FROM ${DB_NAME}.files
  WHERE flagged=1 
    AND (last_time >= DATE_SUB(NOW(), INTERVAL 120 MINUTE)
         OR missing_since >= DATE_SUB(NOW(), INTERVAL 120 MINUTE))
  GROUP BY source
" 2>/dev/null

echo ""

# 3. Letzte run_summaries
echo "⏱️  3. Letzte Scan-Läufe"
echo "─────────────────────────────────────────────────────"
mysql -t -e "
  SELECT 
    source,
    cmd,
    DATE_FORMAT(finished_at, '%d.%m.%Y %H:%i') AS finished,
    flagged_new_count,
    note
  FROM ${DB_NAME}.run_summaries
  WHERE finished_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
  ORDER BY finished_at DESC
  LIMIT 10
" 2>/dev/null

echo ""

# 4. ENV-Konfiguration prüfen
echo "⚙️  4. Service-Konfiguration"
echo "─────────────────────────────────────────────────────"

for SERVICE in nas nas-av; do
  ENV_FILE="/opt/apps/entropywatcher/config/${SERVICE}.env"
  if [[ -f "$ENV_FILE" ]]; then
    echo "[$SERVICE]"
    grep -E "^SOURCE_LABEL=|^SCAN_PATHS=|^CLAMAV_ENABLE=|^HEALTH_FLAGGED_MAX=" "$ENV_FILE" 2>/dev/null || echo "  (keine relevanten Einstellungen)"
    echo ""
  else
    echo "[$SERVICE] ENV nicht gefunden: $ENV_FILE"
    echo ""
  fi
done

# 5. Simuliere Status-Check für beide Services
echo "🔍 5. Status-Check Simulation"
echo "─────────────────────────────────────────────────────"

for SERVICE in nas nas-av; do
  ENV_FILE="/opt/apps/entropywatcher/config/${SERVICE}.env"
  
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "[$SERVICE] Übersprungen (ENV fehlt)"
    continue
  fi
  
  echo "[$SERVICE]"
  /opt/apps/entropywatcher/venv/bin/python /opt/apps/entropywatcher/main/entropywatcher.py \
    --env /opt/apps/entropywatcher/config/common.env \
    --env "$ENV_FILE" \
    status --debug 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "  Status-Check fehlgeschlagen"
  echo ""
done

echo "═══════════════════════════════════════════════════════"
