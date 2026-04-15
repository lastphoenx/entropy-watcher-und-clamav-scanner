#!/usr/bin/env bash
# =====================================================
# Show ClamAV Findings from EntropyWatcher Database
# =====================================================
# Queries av_events table to show recent malware detections

set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default: Zeige letzte 7 Tage
DAYS="${1:-7}"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   ClamAV Findings (letzte ${DAYS} Tage)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# MariaDB-Verbindung (nutzt .my.cnf oder Environment)
DB_NAME="entropywatcher"

# Prüfe ob Datenbank erreichbar
if ! mysql -e "USE ${DB_NAME}" 2>/dev/null; then
  echo -e "${RED}✗ Fehler: Datenbank '${DB_NAME}' nicht erreichbar${NC}"
  echo "Tipp: Prüfe ~/.my.cnf oder setze MYSQL_USER/MYSQL_PASSWORD"
  exit 1
fi

# 1. Zusammenfassung
echo -e "${YELLOW}📊 Zusammenfassung${NC}"
echo "─────────────────────────────────────────────────────────"

TOTAL=$(mysql -N -e "
  SELECT COUNT(*) FROM ${DB_NAME}.av_events 
  WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
" 2>/dev/null || echo "0")

QUARANTINED=$(mysql -N -e "
  SELECT COUNT(*) FROM ${DB_NAME}.av_events 
  WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
    AND action IN ('quarantine', 'move')
" 2>/dev/null || echo "0")

echo -e "Gesamt gefunden:    ${RED}${TOTAL}${NC}"
echo -e "Quarantiniert:      ${YELLOW}${QUARANTINED}${NC}"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
  echo -e "${GREEN}✓ Keine Funde in den letzten ${DAYS} Tagen${NC}"
  exit 0
fi

# 2. Funde nach Signatur gruppiert
echo -e "${YELLOW}🦠 Funde nach Signatur${NC}"
echo "─────────────────────────────────────────────────────────"

mysql -t -e "
  SELECT 
    signature AS 'Signatur',
    COUNT(*) AS 'Anzahl',
    MIN(DATE_FORMAT(detected_at, '%d.%m.%Y %H:%i')) AS 'Erste Erkennung',
    MAX(DATE_FORMAT(detected_at, '%d.%m.%Y %H:%i')) AS 'Letzte Erkennung'
  FROM ${DB_NAME}.av_events
  WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
  GROUP BY signature
  ORDER BY COUNT(*) DESC
" 2>/dev/null

echo ""

# 3. Detaillierte Funde
echo -e "${YELLOW}📁 Detaillierte Funde${NC}"
echo "─────────────────────────────────────────────────────────"

mysql -t -e "
  SELECT 
    DATE_FORMAT(detected_at, '%d.%m %H:%i') AS 'Zeitpunkt',
    source AS 'Quelle',
    signature AS 'Signatur',
    CASE 
      WHEN LENGTH(path) > 60 THEN CONCAT('...', RIGHT(path, 57))
      ELSE path 
    END AS 'Pfad',
    action AS 'Aktion'
  FROM ${DB_NAME}.av_events
  WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
  ORDER BY detected_at DESC
  LIMIT 50
" 2>/dev/null

echo ""

# 4. Betroffene Verzeichnisse
echo -e "${YELLOW}📂 Betroffene Verzeichnisse (Top 10)${NC}"
echo "─────────────────────────────────────────────────────────"

mysql -t -e "
  SELECT 
    SUBSTRING_INDEX(path, '/', 5) AS 'Verzeichnis (Top-Level)',
    COUNT(*) AS 'Anzahl Funde'
  FROM ${DB_NAME}.av_events
  WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
  GROUP BY SUBSTRING_INDEX(path, '/', 5)
  ORDER BY COUNT(*) DESC
  LIMIT 10
" 2>/dev/null

echo ""

# 5. Quarantäne-Pfade (falls vorhanden)
QUAR_COUNT=$(mysql -N -e "
  SELECT COUNT(*) FROM ${DB_NAME}.av_events 
  WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
    AND quarantine_path IS NOT NULL
" 2>/dev/null || echo "0")

if [[ "$QUAR_COUNT" -gt 0 ]]; then
  echo -e "${YELLOW}🔒 Quarantinierte Dateien${NC}"
  echo "─────────────────────────────────────────────────────────"
  
  mysql -t -e "
    SELECT 
      DATE_FORMAT(detected_at, '%d.%m %H:%i') AS 'Zeitpunkt',
      signature AS 'Signatur',
      quarantine_path AS 'Quarantäne-Pfad'
    FROM ${DB_NAME}.av_events
    WHERE detected_at >= DATE_SUB(NOW(), INTERVAL ${DAYS} DAY)
      AND quarantine_path IS NOT NULL
    ORDER BY detected_at DESC
    LIMIT 20
  " 2>/dev/null
  
  echo ""
fi

# 6. Empfehlungen
if [[ "$TOTAL" -gt 0 ]]; then
  echo -e "${YELLOW}💡 Empfehlungen${NC}"
  echo "─────────────────────────────────────────────────────────"
  echo "1. Vollständige Pfade anzeigen:"
  echo "   mysql entropywatcher -e \"SELECT detected_at, path, signature FROM av_events ORDER BY detected_at DESC LIMIT 10\""
  echo ""
  echo "2. Bestimmte Signatur whitelist (False-Positive):"
  echo "   mysql entropywatcher -e \"INSERT INTO av_whitelist (signature, reason) VALUES ('Signatur-Name', 'Begründung')\""
  echo ""
  echo "3. Quarantäne-Verzeichnis prüfen:"
  echo "   ls -lah /var/quarantine/clamav/"
  echo ""
  echo "4. ClamAV-Datenbank aktualisieren:"
  echo "   sudo freshclam"
  echo ""
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
