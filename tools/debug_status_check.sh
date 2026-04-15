#!/usr/bin/env bash
# =====================================================
# Debug: Status-Check für nas und nas-av analysieren
# =====================================================

set -uo pipefail  # Kein -e, damit Script bei leeren Queries nicht abbricht

DB_NAME="entropywatcher"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════"
echo "   EntropyWatcher Status Debug (nas vs nas-av)"
echo "═══════════════════════════════════════════════════════"
echo ""

# 1. Prüfe files Tabelle nach source
echo "📋 1. Files Tabelle - Einträge nach source"
echo "─────────────────────────────────────────────────────"
RESULT=$(mysql -t -e "
  SELECT 
    source,
    COUNT(*) AS total,
    SUM(flagged) AS flagged_count
  FROM ${DB_NAME}.files
  GROUP BY source
  ORDER BY source
" 2>/dev/null)

if [[ -n "$RESULT" ]]; then
  echo "$RESULT"
else
  echo -e "${YELLOW}(keine Einträge in files Tabelle)${NC}"
fi

echo ""

# 2. Flagged files in den letzten 2 Stunden (Standard-Fenster)
echo "🚨 2. Flagged Files (letzte 2 Stunden)"
echo "─────────────────────────────────────────────────────"
RESULT=$(mysql -t -e "
  SELECT 
    source,
    COUNT(*) AS flagged_recent
  FROM ${DB_NAME}.files
  WHERE flagged=1 
    AND (last_time >= DATE_SUB(NOW(), INTERVAL 120 MINUTE)
         OR missing_since >= DATE_SUB(NOW(), INTERVAL 120 MINUTE))
  GROUP BY source
" 2>/dev/null)

if [[ -n "$RESULT" ]]; then
  echo "$RESULT"
else
  echo -e "${GREEN}✓ Keine flagged files in den letzten 2 Stunden${NC}"
fi

echo ""

# 2b. Alle flagged files (zum Vergleich)
echo "🚨 2b. Alle Flagged Files (unabhängig vom Zeitfenster)"
echo "─────────────────────────────────────────────────────"
RESULT=$(mysql -t -e "
  SELECT 
    source,
    COUNT(*) AS flagged_total,
    MAX(DATE_FORMAT(last_time, '%d.%m.%Y %H:%i')) AS latest_flag
  FROM ${DB_NAME}.files
  WHERE flagged=1
  GROUP BY source
" 2>/dev/null)

if [[ -n "$RESULT" ]]; then
  echo "$RESULT"
else
  echo -e "${GREEN}✓ Keine flagged files vorhanden${NC}"
fi

echo ""

# 3. Letzte run_summaries
echo "⏱️  3. Letzte Scan-Läufe (24h)"
echo "─────────────────────────────────────────────────────"
RESULT=$(mysql -t -e "
  SELECT 
    source,
    cmd,
    DATE_FORMAT(finished_at, '%d.%m %H:%i') AS finished,
    flagged_new_count AS new_flags,
    CASE 
      WHEN LENGTH(note) > 50 THEN CONCAT(LEFT(note, 47), '...')
      ELSE note 
    END AS note
  FROM ${DB_NAME}.run_summaries
  WHERE finished_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
  ORDER BY finished_at DESC
  LIMIT 15
" 2>/dev/null)

if [[ -n "$RESULT" ]]; then
  echo "$RESULT"
else
  echo -e "${YELLOW}(keine Scan-Läufe in den letzten 24 Stunden)${NC}"
fi

echo ""

# 4. ENV-Konfiguration prüfen
echo "⚙️  4. Service-Konfiguration"
echo "─────────────────────────────────────────────────────"

for SERVICE in nas nas-av; do
  ENV_FILE="/opt/apps/entropywatcher/config/${SERVICE}.env"
  if [[ -f "$ENV_FILE" ]]; then
    echo "[$SERVICE]"
    grep -E "^SOURCE_LABEL=|^SCAN_PATHS=|^CLAMAV_ENABLE=|^HEALTH_FLAGGED_MAX=|^HEALTH_WINDOW_MIN=|^HEALTH_SAFEAGE_MIN=" "$ENV_FILE" 2>/dev/null || echo "  (keine relevanten Einstellungen gefunden)"
    echo ""
  else
    echo -e "[$SERVICE] ${YELLOW}ENV nicht gefunden: $ENV_FILE${NC}"
    echo ""
  fi
done

# 5. Simuliere Status-Check für beide Services
echo "🔍 5. Status-Check Simulation"
echo "─────────────────────────────────────────────────────"

for SERVICE in nas nas-av; do
  ENV_FILE="/opt/apps/entropywatcher/config/${SERVICE}.env"
  COMMON_ENV="/opt/apps/entropywatcher/config/common.env"
  
  if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "[$SERVICE] ${YELLOW}Übersprungen (ENV fehlt)${NC}"
    echo ""
    continue
  fi
  
  echo "[$SERVICE]"
  
  # Versuche Status-Check mit Error-Handling
  if STATUS_OUTPUT=$(/opt/apps/entropywatcher/venv/bin/python /opt/apps/entropywatcher/main/entropywatcher.py \
    --env "$COMMON_ENV" \
    --env "$ENV_FILE" \
    status --debug 2>&1); then
    
    # Formatiere JSON Output
    if echo "$STATUS_OUTPUT" | python3 -m json.tool 2>/dev/null; then
      :  # JSON ist valid und wurde ausgegeben
    else
      echo "$STATUS_OUTPUT"  # Zeige Raw Output
    fi
  else
    echo -e "${YELLOW}Status-Check fehlgeschlagen:${NC}"
    echo "$STATUS_OUTPUT" | head -20  # Zeige erste 20 Zeilen des Fehlers
  fi
  
  echo ""
done

echo "═══════════════════════════════════════════════════════"

# Zusammenfassung
echo ""
echo "💡 Interpretation:"
echo "─────────────────────────────────────────────────────"

FLAGGED_NAS=$(mysql -N -e "SELECT COUNT(*) FROM ${DB_NAME}.files WHERE source='nas' AND flagged=1" 2>/dev/null || echo "?")
FLAGGED_NAS_AV=$(mysql -N -e "SELECT COUNT(*) FROM ${DB_NAME}.files WHERE source='nas-av' AND flagged=1" 2>/dev/null || echo "?")

echo "• nas: $FLAGGED_NAS flagged files (Entropy-Alarme)"
echo "• nas-av: $FLAGGED_NAS_AV flagged files (sollte 0 sein - ClamAV schreibt in av_events)"
echo ""

if [[ "$FLAGGED_NAS" != "0" && "$FLAGGED_NAS" != "?" ]]; then
  echo -e "${YELLOW}→ nas hat $FLAGGED_NAS flagged files (Steuerdateien?)${NC}"
  echo "  Lösung: EXEMPT_PATHS in config/nas.env setzen"
  echo ""
fi

if [[ "$FLAGGED_NAS_AV" != "0" && "$FLAGGED_NAS_AV" != "?" ]]; then
  echo -e "${YELLOW}⚠ WARNUNG: nas-av hat $FLAGGED_NAS_AV flagged files${NC}"
  echo "  Das sollte NICHT passieren - av-scan schreibt nicht in files Tabelle!"
  echo "  Mögliche Ursache: SOURCE_LABEL fehlt oder ist falsch"
  echo ""
fi

echo "═══════════════════════════════════════════════════════"
