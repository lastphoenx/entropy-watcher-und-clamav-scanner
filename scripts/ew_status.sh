#!/bin/bash
set -euo pipefail

CONFIG_DIR="${1:-/opt/apps/entropywatcher/config}"
MODE="${2:-dashboard}"
COMMON_ENV="${CONFIG_DIR}/common.env"

if [[ ! -f "$COMMON_ENV" ]]; then
  echo "ERROR: common.env nicht gefunden: $COMMON_ENV"
  exit 1
fi

source "$COMMON_ENV"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-entropywatcher}"
DB_USER="${DB_USER:-entropyuser}"
DB_PASS="${DB_PASS:-}"

# Get default from common.env
DEFAULT_HEALTH_WINDOW_MIN="${HEALTH_WINDOW_MIN:-120}"

declare -A SERVICES
declare -A WINDOWS

get_health_window_for_service() {
  local service_env="$1"
  local window="$DEFAULT_HEALTH_WINDOW_MIN"
  
  # Check if service-specific env has HEALTH_WINDOW_MIN
  if [[ -f "$service_env" ]]; then
    local service_val=$(grep -E '^HEALTH_WINDOW_MIN=' "$service_env" 2>/dev/null \
      | sed 's/^[^=]*=//' | sed 's/#.*$//' | tr -d ' ')
    [[ -n "$service_val" ]] && window="$service_val"
  fi
  
  echo "$window"
}

for env_file in "${CONFIG_DIR}"/*.env; do
  [[ "$env_file" == "$COMMON_ENV" ]] && continue
  
  if grep -q "^SOURCE_LABEL=" "$env_file" 2>/dev/null; then
    # Read SOURCE_LABEL without sourcing (to avoid variable pollution)
    SOURCE_LABEL=$(grep -E '^SOURCE_LABEL=' "$env_file" | sed 's/^[^=]*=//' | sed 's/#.*$//' | tr -d ' ')
    
    if [[ -n "$SOURCE_LABEL" ]]; then
      SERVICES["${SOURCE_LABEL}"]="$env_file"
      # Get correct window for THIS service
      WINDOWS["${SOURCE_LABEL}"]="$(get_health_window_for_service "$env_file")"
    fi
  fi
done

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "ERROR: Keine Services gefunden in $CONFIG_DIR"
  exit 1
fi

mysql_query() {
  if [[ -n "$DB_PASS" ]]; then
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "$1" 2>/dev/null || echo ""
  else
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" -se "$1" 2>/dev/null || echo ""
  fi
}

get_status_color() {
  local status="$1"
  case "$status" in
    GREEN) echo "#28a745" ;;
    YELLOW) echo "#ffc107" ;;
    RED) echo "#dc3545" ;;
    *) echo "#666666" ;;
  esac
}

get_status_icon() {
  local status="$1"
  case "$status" in
    GREEN) echo "✓" ;;
    YELLOW) echo "⚠" ;;
    RED) echo "✗" ;;
    *) echo "?" ;;
  esac
}

print_header() {
  echo "╔════════════════╦════════════╦═══════════════════╦═════════╦════════════╦═══════════════╗"
  echo "║ Service        ║ Status     ║ Last Scan         ║ Age Min ║ Window Min ║ Buffer übrig %║"
  echo "╠════════════════╬════════════╬═══════════════════╬═════════╬════════════╬═══════════════╣"
}

print_row() {
  local service="$1" status="$2" last_scan="$3" age_min="$4" window="$5" buffer="$6"
  printf "║ %-14s ║ %-10s ║ %-17s ║ %7d ║ %10d ║ %12s%% ║\n" \
    "$service" "$status" "$last_scan" "$age_min" "$window" "$buffer"
}

print_footer() {
  echo "╚════════════════╩════════════╩═══════════════════╩═════════╩════════════╩═══════════════╝"
}

print_html_header() {
  cat > "$1" << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>EntropyWatcher Status</title>
  <style>
    body { font-family: 'Courier New', monospace; background: #1e1e1e; color: #e0e0e0; margin: 20px; }
    .container { max-width: 1000px; margin: 0 auto; }
    h1 { color: #66bb6a; text-align: center; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th { background: #333; color: #66bb6a; padding: 12px; text-align: left; border-bottom: 2px solid #66bb6a; }
    td { padding: 10px; border-bottom: 1px solid #444; }
    tr:hover { background: #2a2a2a; }
    .status { font-weight: bold; text-align: center; width: 80px; }
    .green { color: #28a745; }
    .yellow { color: #ffc107; }
    .red { color: #dc3545; }
    .timestamp { color: #999; font-size: 0.9em; text-align: center; }
    .alert { background: #5c3a3a; border-left: 4px solid #dc3545; padding: 12px; margin: 20px 0; }
    .alert-title { color: #dc3545; font-weight: bold; }
  </style>
</head>
<body>
  <div class="container">
    <h1>EntropyWatcher Health Status</h1>
    <p class="timestamp">Aktualisiert: <span id="timestamp"></span></p>
    <table>
      <thead>
        <tr>
          <th>Service</th>
          <th class="status">Status</th>
          <th>Last Scan</th>
          <th style="width: 80px">Age (Min)</th>
          <th style="width: 100px">Window (Min)</th>
          <th style="width: 80px">Buffer %</th>
        </tr>
      </thead>
      <tbody id="status-rows">
EOF
}

print_html_row() {
  local html_file="$1" service="$2" status="$3" last_scan="$4" age_min="$5" window="$6" buffer="$7"
  local color_class=$(echo "$status" | tr '[:upper:]' '[:lower:]')
  
  cat >> "$html_file" << EOF
        <tr>
          <td><strong>$service</strong></td>
          <td class="status $color_class">$(get_status_icon "$status") $status</td>
          <td>$last_scan</td>
          <td style="text-align: right">$age_min</td>
          <td style="text-align: right">$window</td>
          <td style="text-align: right">$buffer%</td>
        </tr>
EOF
}

print_html_footer() {
  local html_file="$1"
  local alerts_html="$2"
  
  cat >> "$html_file" << 'EOF'
      </tbody>
    </table>
EOF

  if [[ -n "$alerts_html" ]]; then
    cat >> "$html_file" << EOF
    <div class="alert">
      <div class="alert-title">⚠️ ALERTS:</div>
      <ul>
$alerts_html
      </ul>
    </div>
EOF
  fi

  cat >> "$html_file" << 'EOF'
  </div>
  <script>
    document.getElementById('timestamp').textContent = new Date().toLocaleString('de-DE');
    setTimeout(() => location.reload(), 300000); // Auto-refresh alle 5 Min
  </script>
</body>
</html>
EOF
}

check_services() {
  local has_red=0
  local alerts=()
  local html_file="${3:-}"
  local html_mode=0
  
  if [[ -n "$html_file" ]]; then
    html_mode=1
    print_html_header "$html_file"
  else
    print_header
  fi
  
  for service in "${!SERVICES[@]}"; do
    window_min="${WINDOWS[$service]}"
    
    query="SELECT TIMESTAMPDIFF(MINUTE, MAX(finished_at), NOW()) FROM scan_summary WHERE source = '$service'"
    age_min=$(mysql_query "$query" | head -1)
    
    if [[ -z "$age_min" || "$age_min" == "NULL" ]]; then
      status="RED"
      last_scan="keine Daten"
      buffer="N/A"
      has_red=1
      alerts+=("$service: Noch kein Scan in DB")
    else
      age_min=${age_min:-0}
      three_quarter_window=$((window_min * 3 / 4))
      buffer=$((100 - (age_min * 100 / window_min)))
      
      if [[ $age_min -lt $three_quarter_window ]]; then
        status="GREEN"
      elif [[ $age_min -lt $window_min ]]; then
        status="YELLOW"
      else
        status="RED"
        has_red=1
        alerts+=("$service: ÜBERFÄLLIG um $((age_min - window_min)) Min")
      fi
      
      query="SELECT DATE_FORMAT(MAX(finished_at), '%d.%m.%Y %H:%i') FROM scan_summary WHERE source = '$service'"
      last_scan=$(mysql_query "$query" | head -1)
      last_scan="${last_scan:-?}"
    fi
    
    if [[ $html_mode -eq 1 ]]; then
      print_html_row "$html_file" "$service" "$status" "$last_scan" "$age_min" "$window_min" "$buffer"
    else
      print_row "$service" "$status" "$last_scan" "$age_min" "$window_min" "$buffer"
    fi
  done
  
  if [[ $html_mode -eq 1 ]]; then
    local alerts_html=""
    for alert in "${alerts[@]}"; do
      alerts_html+="        <li>$alert</li>"$'\n'
    done
    print_html_footer "$html_file" "$alerts_html"
  else
    print_footer
    
    if [[ $has_red -eq 1 ]]; then
      echo ""
      echo "⚠️  ALERTS:"
      for alert in "${alerts[@]}"; do
        echo "  - $alert"
      done
    fi
  fi
  
  [[ $has_red -eq 0 ]]
}

case "$MODE" in
  dashboard)
    check_services
    ;;
  html)
    html_out="${3:-/var/www/html/ew-status.html}"
    html_dir=$(dirname "$html_out")
    
    if [[ ! -d "$html_dir" ]]; then
      if ! sudo mkdir -p "$html_dir" 2>/dev/null; then
        mkdir -p "$html_dir" || {
          echo "ERROR: Kann Verzeichnis nicht erstellen: $html_dir"
          exit 1
        }
      fi
      if [[ -d /var/www/html ]] && [[ "$html_dir" == "/var/www/html" ]]; then
        sudo chown www-data:www-data "$html_dir" 2>/dev/null || true
        sudo chmod 755 "$html_dir" 2>/dev/null || true
      fi
    fi
    
    check_services "" "" "$html_out"
    echo "HTML report generated: $html_out"
    ;;
  cron)
    # Generate HTML report for email
    html_mail_file="/tmp/ew_status_mail.html"
    
    # Check services and capture exit code
    if ! check_services "" "" "$html_mail_file"; then
      # Also generate plain text for fallback
      check_services > /tmp/ew_status_report.txt 2>&1 || true
      
      if [[ "${MAIL_ENABLE:-0}" == "1" ]]; then
        MAIL_FROM="${MAIL_FROM:-entropywatcher@localhost}"
        MAIL_HOST="${MAIL_SMTP_HOST:-localhost}"
        MAIL_PORT="${MAIL_SMTP_PORT:-25}"
        MAIL_STARTTLS="${MAIL_STARTTLS:-0}"
        MAIL_SSL="${MAIL_SSL:-0}"
        
        python3 << PYTHONEOF
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
import sys

try:
    # Read HTML body
    with open('/tmp/ew_status_mail.html', 'r') as f:
        html_body = f.read()
    
    # Read plain text fallback
    try:
        with open('/tmp/ew_status_report.txt', 'r') as f:
            text_body = f.read()
    except:
        text_body = "EntropyWatcher Health Alert - siehe HTML-Version"
    
    # Create multipart message
    msg = MIMEMultipart('alternative')
    msg['From'] = '$MAIL_FROM'
    msg['To'] = '$MAIL_TO'
    msg['Subject'] = '$MAIL_SUBJECT_PREFIX Health Alert'
    
    part1 = MIMEText(text_body, 'plain', 'utf-8')
    msg.attach(part1)
    
    # Attach HTML (preferred)
    part2 = MIMEText(html_body, 'html', 'utf-8')
    msg.attach(part2)
    
    # Send mail
    ssl = int($MAIL_SSL)
    smtp_class = smtplib.SMTP_SSL if ssl else smtplib.SMTP
    
    with smtp_class('$MAIL_HOST', int($MAIL_PORT), timeout=10) as server:
        if $MAIL_STARTTLS and not ssl:
            server.starttls()
        if '$MAIL_USER' and '$MAIL_PASS':
            server.login('$MAIL_USER', '$MAIL_PASS')
        server.send_message(msg)
    
    print("HTML-Mail erfolgreich verschickt", file=sys.stderr)
except Exception as e:
    print(f'Mail error: {e}', file=sys.stderr)
    sys.exit(1)
PYTHONEOF
      fi
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [config_dir] [dashboard|html|cron] [html_output_path]"
    echo ""
    echo "Modes:"
    echo "  dashboard  - Terminal-Tabelle (für Hand-Abfragen)"
    echo "  html       - HTML-Report (für Browser, default: /var/www/html/ew-status.html)"
    echo "  cron       - Cron-Mode (Mail bei RED, exit 1 bei Fehler)"
    exit 1
    ;;
esac
