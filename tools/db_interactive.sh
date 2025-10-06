#!/bin/bash
# Quick interactive MariaDB session with EntropyWatcher database
# Loads credentials from common.env and launches mysql client

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../common.env"

# Check if common.env exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Error: common.env not found at $ENV_FILE" >&2
    exit 1
fi

# Source the environment file
source "$ENV_FILE"

# Validate required variables
if [[ -z "${DB_HOST:-}" ]] || [[ -z "${DB_USER:-}" ]] || [[ -z "${DB_PASSWORD:-}" ]] || [[ -z "${DB_NAME:-}" ]]; then
    echo "❌ Error: Missing database configuration in common.env" >&2
    echo "   Required: DB_HOST, DB_USER, DB_PASSWORD, DB_NAME" >&2
    exit 1
fi

echo "🔍 Connecting to EntropyWatcher database..."
echo "   Host: $DB_HOST"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo ""
echo "💡 Quick commands:"
echo "   SHOW TABLES;"
echo "   SELECT * FROM scan_summary ORDER BY scan_start DESC LIMIT 5;"
echo "   SELECT * FROM av_events ORDER BY detected_at DESC LIMIT 10;"
echo ""

# Launch mysql client
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME"
