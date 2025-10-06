#!/usr/bin/env bash
#
# anonymize-server-configs.sh
# Lädt Config-Dateien vom Server und anonymisiert Secrets für lokale Dokumentation
#
# Nutzung (auf dem SERVER ausführen):
#   chmod +x anonymize-server-configs.sh
#   ./anonymize-server-configs.sh
#
# Das Skript muss auf dem SERVER (Debian) laufen
# Es erstellt anonymisierte Kopien in /tmp/anon-configs/
# Diese können dann per SCP lokal geholt werden
#

set -euo pipefail

OUTPUT_DIR="/tmp/server-config-examples"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "🔒 Anonymizing sensitive data..."
echo "📤 Output: $OUTPUT_DIR (für Prüfung und GitHub)"

# ============================================================================
# HILFSFUNKTION: Datei anonymisieren
# ============================================================================
anonymize_file() {
    local input_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$input_file" ]]; then
        echo "⚠️  Datei nicht gefunden: $input_file"
        return 1
    fi
    
    cp "$input_file" "$output_file"
    
    # --- .env Dateien ---
    # --- DB-Passwörter (verschiedene Varianten) ---
    sed -i 's/DB_PASSWORD=.*/DB_PASSWORD=<DB_PASSWORD>/g' "$output_file"
    sed -i 's/DB_PASS=.*/DB_PASS=<DB_PASSWORD>/g' "$output_file"
    sed -i 's/MYSQL_PASSWORD=.*/MYSQL_PASSWORD=<DB_PASSWORD>/g' "$output_file"
    sed -i 's/MARIADB_PASSWORD=.*/MARIADB_PASSWORD=<DB_PASSWORD>/g' "$output_file"
    
    # --- API-Tokens ---
    sed -i 's/PCLOUD_API_TOKEN=.*/PCLOUD_API_TOKEN=<PCLOUD_TOKEN>/g' "$output_file"
    sed -i 's/API_TOKEN=.*/API_TOKEN=<API_TOKEN>/g' "$output_file"
    sed -i 's/AUTH_TOKEN=.*/AUTH_TOKEN=<AUTH_TOKEN>/g' "$output_file"
    sed -i 's/TOKEN=.*/TOKEN=<TOKEN>/g' "$output_file"
    sed -i 's/BEARER_TOKEN=.*/BEARER_TOKEN=<BEARER_TOKEN>/g' "$output_file"
    
    # --- Tokens in Kommentaren (mit Anführungszeichen, JSON, etc) ---
    sed -i 's/"access_token":"[^"]*"/"access_token":"<TOKEN>"/g' "$output_file"
    sed -i 's/"token":"[^"]*"/"token":"<TOKEN>"/g' "$output_file"
    sed -i 's/^#.*token.*=.*/# token = <TOKEN>/gi' "$output_file"
    
    # --- E-Mail-Adressen ---
    sed -i 's/[a-zA-Z0-9._%+-]\+@[a-zA-Z0-9.-]\+\.[a-zA-Z]\{2,\}/<YOUR_EMAIL>/g' "$output_file"
    sed -i 's/MAIL_FROM=.*/MAIL_FROM=<YOUR_EMAIL>/g' "$output_file"
    sed -i 's/MAIL_TO=.*/MAIL_TO=<YOUR_EMAIL>/g' "$output_file"
    sed -i 's/SENDER=.*/SENDER=<YOUR_EMAIL>/g' "$output_file"
    
    # --- SMTP/Mail-Passwörter (verschiedene Varianten) ---
    sed -i 's/SMTP_PASSWORD=.*/SMTP_PASSWORD=<SMTP_PASSWORD>/g' "$output_file"
    sed -i 's/MAIL_PASSWORD=.*/MAIL_PASSWORD=<MAIL_PASSWORD>/g' "$output_file"
    sed -i 's/MAIL_PASS=.*/MAIL_PASS=<MAIL_PASSWORD>/g' "$output_file"
    
    # --- Benutzernamen / Hostnamen ---
    sed -i 's/DB_USER=.*/DB_USER=<DB_USER>/g' "$output_file"
    sed -i 's/DB_HOST=.*/DB_HOST=<DB_HOST>/g' "$output_file"
    
    # --- systemd User/Group (vorsichtig, nicht überall ersetzen) ---
    sed -i 's/^User=.*/User=<USER>/g' "$output_file"
    sed -i 's/^Group=.*/Group=<GROUP>/g' "$output_file"
    
    # SSH-Keys (mehrzeilig - schwierig, aber einfache Variante)
    sed -i '/^.*PRIVATE_KEY=/s/=.*/=<PRIVATE_KEY>/g' "$output_file"
    sed -i '/^.*SSH_KEY=/s/=.*/=<SSH_KEY>/g' "$output_file"
    
    # --- .service und .timer Dateien ---
    # ExecStart Zeilen mit sensiblen Flags
    sed -i 's/--api-key=[^ ]*/--api-key=<API_KEY>/g' "$output_file"
    sed -i 's/--token=[^ ]*/--token=<TOKEN>/g' "$output_file"
    sed -i 's/--password=[^ ]*/--password=<PASSWORD>/g' "$output_file"
    
    echo "✅ $(basename "$input_file")"
}

# ============================================================================
# ENTROPY-WATCHER Config Dateien
# ============================================================================
echo ""
echo "📁 entropy-watcher Config-Dateien..."
mkdir -p "$OUTPUT_DIR/entropy-watcher-und-clamav-scanner/.server-config/example/config"

shopt -s nullglob
for env_file in /opt/apps/entropywatcher/config/*.env; do
    if [[ -f "$env_file" ]]; then
        basename=$(basename "$env_file")
        anonymize_file "$env_file" "$OUTPUT_DIR/entropy-watcher-und-clamav-scanner/.server-config/example/config/$basename.example"
    fi
done
shopt -u nullglob

echo ""
echo "📁 entropy-watcher Services & Timers..."
mkdir -p "$OUTPUT_DIR/entropy-watcher-und-clamav-scanner/.server-config/example/systemd"

shopt -s nullglob
for service_file in /etc/systemd/system/entropywatcher*.service /etc/systemd/system/entropywatcher*.timer /etc/systemd/system/backup-pipeline*.service /etc/systemd/system/backup-pipeline*.timer; do
    if [[ -f "$service_file" ]]; then
        basename=$(basename "$service_file")
        anonymize_file "$service_file" "$OUTPUT_DIR/entropy-watcher-und-clamav-scanner/.server-config/example/systemd/$basename.example"
    fi
done
shopt -u nullglob

# ============================================================================
# PCLOUD-TOOLS Config-Dateien
# ============================================================================
echo ""
echo "📁 pcloud-tools Config-Dateien..."
mkdir -p "$OUTPUT_DIR/pcloud-tools/.server-config/example/config"

if [[ -f /opt/apps/pcloud-tools/main/.env ]]; then
    anonymize_file /opt/apps/pcloud-tools/main/.env "$OUTPUT_DIR/pcloud-tools/.server-config/example/config/.env.example"
fi

if [[ -d /opt/apps/pcloud-tools/main/config ]]; then
    shopt -s nullglob
    for env_file in /opt/apps/pcloud-tools/main/config/*.env; do
        if [[ -f "$env_file" ]]; then
            basename=$(basename "$env_file")
            anonymize_file "$env_file" "$OUTPUT_DIR/pcloud-tools/.server-config/example/config/$basename.example"
        fi
    done
    shopt -u nullglob
fi

# ============================================================================
# RTB Config-Dateien (falls vorhanden)
# ============================================================================
echo ""
echo "📁 rtb Config-Dateien..."
mkdir -p "$OUTPUT_DIR/rtb/.server-config/example/config"

if [[ -f /opt/apps/rtb/.env ]]; then
    anonymize_file /opt/apps/rtb/.env "$OUTPUT_DIR/rtb/.server-config/example/config/.env.example"
fi

if [[ -d /opt/apps/rtb/config ]]; then
    shopt -s nullglob
    for env_file in /opt/apps/rtb/config/*.env; do
        if [[ -f "$env_file" ]]; then
            basename=$(basename "$env_file")
            anonymize_file "$env_file" "$OUTPUT_DIR/rtb/.server-config/example/config/$basename.example"
        fi
    done
    shopt -u nullglob
fi

# ============================================================================
# NAS/SYSTEM Services (cleanup-samba-recycle, etc.)
# ============================================================================
echo ""
echo "📁 NAS/System Services & Timers..."
mkdir -p "$OUTPUT_DIR/.system-config/example/systemd"

shopt -s nullglob
for service_file in /etc/systemd/system/cleanup-samba*.service /etc/systemd/system/cleanup-samba*.timer; do
    if [[ -f "$service_file" ]]; then
        basename=$(basename "$service_file")
        anonymize_file "$service_file" "$OUTPUT_DIR/.system-config/example/systemd/$basename.example"
    fi
done
shopt -u nullglob

# ============================================================================
# Zusammenfassung
# ============================================================================
echo ""
echo "✨ Anonymisierung abgeschlossen!"
echo ""
echo "📋 Struktur in $OUTPUT_DIR:"
find "$OUTPUT_DIR" -type f | sort
echo ""
echo "📥 WORKFLOW:"
echo ""
echo "1️⃣  Auf deinem Windows-Rechner herunterladen:"
echo "   scp -r user@<SERVER>:$OUTPUT_DIR/* ."
echo ""
echo "   Das erzeugt lokal:"
echo "   ├── entropy-watcher-und-clamav-scanner/.server-config/example/"
echo "   ├── pcloud-tools/.server-config/example/"
echo "   ├── rtb/.server-config/example/"
echo "   └── .system-config/example/                   (NAS/System Services)"
echo ""
echo "2️⃣  Überprüfe die .example-Dateien auf nicht anonymisierte Werte:"
echo "   - Tokens, API-Keys, Passwörter"
echo "   - E-Mail-Adressen"
echo "   - Sensible Hostnamen/Pfade"
echo ""
echo "3️⃣  Gib mir Feedback (z.B. 'in common.env Zeile 5 steht noch ein Token')"
echo ""
echo "4️⃣  Wir tunen die Regex-Pattern im Skript bis es perfekt ist"
echo ""
echo "5️⃣  Dann kannst du die .example-Dateien auf GitHub pushen"
echo "   (als Template für andere, damit sie sehen, wie man das Projekt konfiguriert)"
echo ""
