# EntropyWatcher - Nützliche Datenbank-Queries

## Verbindung herstellen

```bash
sudo mysql
```

```sql
USE entropywatcher;
```

---

## 📊 Dashboard / Overview

### Gesamtstatistik
```sql
SELECT 
    (SELECT COUNT(*) FROM files) AS total_files,
    (SELECT COUNT(*) FROM files WHERE flagged=1) AS flagged_files,
    (SELECT COUNT(*) FROM files WHERE missing_since IS NOT NULL) AS missing_files,
    (SELECT COUNT(*) FROM scans) AS total_scans,
    (SELECT COUNT(*) FROM av_events) AS av_detections;
```

### Letzte Scan-Aktivität (pro Source)
```sql
SELECT 
    source,
    COUNT(*) AS scanned_files,
    MAX(last_time) AS last_scan,
    TIMESTAMPDIFF(MINUTE, MAX(last_time), NOW()) AS minutes_ago
FROM files
GROUP BY source
ORDER BY last_scan DESC;
```

### Top 10 jüngste Änderungen
```sql
SELECT 
    source,
    path,
    last_entropy,
    note,
    last_time
FROM files
WHERE last_time > NOW() - INTERVAL 24 HOUR
ORDER BY last_time DESC
LIMIT 10;
```

---

## 🚨 Flagged Files (Anomalien)

### Alle geflaggten Dateien (aktuell)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 3) AS entropy,
    note,
    last_time,
    TIMESTAMPDIFF(DAY, last_time, NOW()) AS days_ago
FROM files
WHERE flagged = 1
ORDER BY last_time DESC;
```

### Nur absolute Entropy-Anomalien (>=7.8)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 3) AS entropy,
    note,
    last_time
FROM files
WHERE flagged = 1 
  AND note LIKE '%abs>=7.8%'
ORDER BY last_entropy DESC;
```

### Nur Jump-Anomalien (große Sprünge)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 3) AS entropy,
    note,
    last_time
FROM files
WHERE flagged = 1 
  AND note LIKE '%jump%'
  AND note NOT LIKE '%abs>=7.8%'
ORDER BY last_time DESC;
```

### Grouped by Note-Pattern
```sql
SELECT 
    CASE
        WHEN note LIKE '%abs>=7.8%' THEN 'High Entropy (>=7.8)'
        WHEN note LIKE '%jump%' THEN 'Entropy Jump'
        ELSE 'Other'
    END AS category,
    COUNT(*) AS count
FROM files
WHERE flagged = 1
GROUP BY category
ORDER BY count DESC;
```

---

## 📁 Missing Files (verschwundene Dateien)

### Aktuell fehlende Dateien (Top 20)
```sql
SELECT 
    source,
    path,
    missing_since,
    TIMESTAMPDIFF(DAY, missing_since, NOW()) AS days_missing
FROM files
WHERE missing_since IS NOT NULL
ORDER BY missing_since DESC
LIMIT 20;
```

### Missing Files gruppiert nach Base-Dir
```sql
SELECT
    SUBSTRING_INDEX(path, '/', 3) AS base_dir,
    COUNT(*) AS count,
    MIN(missing_since) AS first_missing,
    MAX(missing_since) AS last_missing
FROM files
WHERE missing_since IS NOT NULL
GROUP BY base_dir
ORDER BY count DESC
LIMIT 20;
```

### Kürzlich verschwundene Dateien (letzte 7 Tage)
```sql
SELECT 
    source,
    path,
    missing_since,
    ROUND(last_entropy, 3) AS last_entropy,
    flagged
FROM files
WHERE missing_since > NOW() - INTERVAL 7 DAY
ORDER BY missing_since DESC;
```

---

## 🔍 Entropy-Analyse

### Höchste Entropy-Werte (potentiell verschlüsselt)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 4) AS entropy,
    flagged,
    note,
    last_time
FROM files
WHERE last_entropy >= 7.5
ORDER BY last_entropy DESC
LIMIT 20;
```

### Niedrigste Entropy-Werte (Text/Daten)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 4) AS entropy,
    flagged,
    last_time
FROM files
WHERE last_entropy < 2.0
  AND missing_since IS NULL
ORDER BY last_entropy ASC
LIMIT 20;
```

### Entropy-Distribution (Histogram)
```sql
SELECT 
    CONCAT(FLOOR(last_entropy), '-', FLOOR(last_entropy) + 1) AS entropy_range,
    COUNT(*) AS count
FROM files
WHERE missing_since IS NULL
GROUP BY FLOOR(last_entropy)
ORDER BY FLOOR(last_entropy);
```

---

## 🦠 ClamAV Events

### Letzte Virusfunde (24h)
```sql
SELECT 
    detected_at,
    source,
    signature,
    action,
    path
FROM av_events
WHERE detected_at > NOW() - INTERVAL 24 HOUR
ORDER BY detected_at DESC;
```

### Alle Virusfunde (Überblick)
```sql
SELECT 
    detected_at,
    source,
    signature,
    action,
    path
FROM av_events
ORDER BY detected_at DESC
LIMIT 50;
```

### Virusfunde gruppiert nach Signature
```sql
SELECT 
    signature,
    COUNT(*) AS count,
    MIN(detected_at) AS first_seen,
    MAX(detected_at) AS last_seen,
    GROUP_CONCAT(DISTINCT source) AS sources
FROM av_events
GROUP BY signature
ORDER BY count DESC;
```

### AV-Events nach Source
```sql
SELECT 
    source,
    COUNT(*) AS events,
    COUNT(DISTINCT signature) AS unique_signatures
FROM av_events
GROUP BY source
ORDER BY events DESC;
```

---

## 🔧 Maintenance / Cleanup

### Flagged Test-Files clearen (wie in deinem Beispiel)
```sql
UPDATE files
SET flagged = 0, note = 'cleared: test files'
WHERE path LIKE '/usr/local/ew-test/%'
   OR path LIKE '/srv/nas/test/%';
```

### Alle Flags von bestimmtem Path-Prefix entfernen
```sql
-- DRY-RUN (zeige betroffene Files):
SELECT source, path, note 
FROM files 
WHERE path LIKE '/opt/apps/pcloud-tools/%' AND flagged = 1;

-- Dann ausführen:
UPDATE files
SET flagged = 0, note = CONCAT(note, ' | cleared manually')
WHERE path LIKE '/opt/apps/pcloud-tools/%' 
  AND flagged = 1;
```

### Alte Missing-Files löschen (>90 Tage)
```sql
-- DRY-RUN (zählen):
SELECT COUNT(*) 
FROM files 
WHERE missing_since < NOW() - INTERVAL 90 DAY;

-- Löschen:
DELETE FROM files
WHERE missing_since < NOW() - INTERVAL 90 DAY;
```

### Flags älter als X Tage zurücksetzen
```sql
-- DRY-RUN:
SELECT COUNT(*) 
FROM files 
WHERE flagged = 1 
  AND last_time < NOW() - INTERVAL 30 DAY;

-- Ausführen:
UPDATE files
SET flagged = 0, note = CONCAT(note, ' | auto-cleared (30d)')
WHERE flagged = 1 
  AND last_time < NOW() - INTERVAL 30 DAY;
```

---

## 📈 Performance & Statistics

### Dateien pro Source
```sql
SELECT 
    source,
    COUNT(*) AS total,
    SUM(flagged) AS flagged,
    SUM(CASE WHEN missing_since IS NOT NULL THEN 1 ELSE 0 END) AS missing,
    MAX(last_time) AS last_scan
FROM files
GROUP BY source;
```

### Top 20 Verzeichnisse (meiste Dateien)
```sql
SELECT
    SUBSTRING_INDEX(path, '/', 4) AS directory,
    COUNT(*) AS file_count,
    SUM(flagged) AS flagged_count
FROM files
WHERE missing_since IS NULL
GROUP BY directory
ORDER BY file_count DESC
LIMIT 20;
```

### Scan-Historie (letzte 10 Scans)
```sql
SELECT 
    scan_id,
    source,
    start_time,
    TIMESTAMPDIFF(MINUTE, start_time, NOW()) AS minutes_ago,
    files_scanned,
    files_flagged
FROM scans
ORDER BY start_time DESC
LIMIT 10;
```

---

## 🎯 Spezielle Use-Cases

### Neue Flags in letzten 24h (potentielle Ransomware-Aktivität)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 3) AS entropy,
    note,
    last_time,
    TIMESTAMPDIFF(MINUTE, last_time, NOW()) AS minutes_ago
FROM files
WHERE flagged = 1 
  AND last_time > NOW() - INTERVAL 24 HOUR
ORDER BY last_time DESC;
```

### Dateien mit hoher Entropy UND kürzlich geändert (KRITISCH!)
```sql
SELECT 
    source,
    path,
    ROUND(last_entropy, 4) AS entropy,
    note,
    last_time,
    TIMESTAMPDIFF(MINUTE, last_time, NOW()) AS minutes_ago
FROM files
WHERE last_entropy >= 7.8
  AND last_time > NOW() - INTERVAL 1 HOUR
  AND missing_since IS NULL
ORDER BY last_time DESC;
```

### Verdächtige Dateiendungen mit hoher Entropy
```sql
SELECT 
    SUBSTRING_INDEX(path, '.', -1) AS extension,
    COUNT(*) AS count,
    AVG(last_entropy) AS avg_entropy,
    MAX(last_entropy) AS max_entropy
FROM files
WHERE last_entropy >= 7.0
  AND missing_since IS NULL
  AND path LIKE '%.%'
GROUP BY extension
HAVING count > 5
ORDER BY avg_entropy DESC;
```

### Files die FLAG bekommen haben nach UNFLAGGED
```sql
SELECT 
    path,
    last_entropy,
    note,
    last_time
FROM files
WHERE note LIKE '%cleared%'
  AND last_time > NOW() - INTERVAL 7 DAY
ORDER BY last_time DESC;
```

---

## 💡 Tipps

### Alle Tabellen anzeigen
```sql
SHOW TABLES;
```

### Schema einer Tabelle
```sql
SHOW COLUMNS FROM files;
SHOW COLUMNS FROM av_events;
SHOW COLUMNS FROM av_whitelist;
SHOW COLUMNS FROM run_summaries;
SHOW COLUMNS FROM scan_summary;
```

### Alle Tabellen mit Spalten
```sql
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMN_KEY
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'entropywatcher'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

### Datenbank-Größe
```sql
SELECT 
    table_name AS 'Table',
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Size (MB)'
FROM information_schema.TABLES
WHERE table_schema = 'entropywatcher'
ORDER BY (data_length + index_length) DESC;
```

---

## 🚀 Quick-Access Script

Speichere diese Datei als `/opt/apps/entropywatcher/tools/db-interactive.sh`:

```bash
#!/bin/bash
# Quick-Access zu MariaDB mit vorgeladener DB
sudo mysql -D entropywatcher
```

Dann: `chmod +x /opt/apps/entropywatcher/tools/db-interactive.sh`

Aufruf: `bash /opt/apps/entropywatcher/tools/db-interactive.sh`

Dann bist du sofort in `entropywatcher` Datenbank! 🎯
