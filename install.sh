#!/usr/bin/env bash
#
# install.sh - Interactive/Non-Interactive EntropyWatcher Installation
#
# Usage:
#   sudo ./install.sh --interactive
#   sudo ./install.sh --non-interactive --db-password "..." --smtp-host "..." [OPTIONS]
#
# Options:
#   --interactive              Interactive mode (prompts for all values)
#   --non-interactive          Automated mode (requires all params)
#   --db-password PASSWORD     MariaDB password for entropyuser
#   --smtp-host HOST           SMTP server hostname
#   --smtp-port PORT           SMTP port (default: 587)
#   --smtp-user USER           SMTP username
#   --smtp-password PASS       SMTP password
#   --smtp-from EMAIL          From address (default: entropywatch@$(hostname))
#   --admin-email EMAIL        Admin email for alerts
#   --nas-paths PATHS          NAS scan paths (comma-separated)
#   --os-paths PATHS           OS scan paths (comma-separated)
#   --install-clamav           Install ClamAV + Daemon
#   --skip-clamav              Skip ClamAV installation
#   --install-honeyfiles       Install Honeyfiles + Auditd
#   --skip-honeyfiles          Skip Honeyfiles installation
#   --skip-systemd             Skip systemd service installation
#   --skip-db-init             Skip database initialization
#   --install-dir PATH         Installation directory (default: /opt/apps/entropywatcher)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
INTERACTIVE=0
INSTALL_CLAMAV=""
INSTALL_HONEYFILES=""
INSTALL_SYSTEMD=1
INIT_DATABASE=1

INSTALL_DIR="/opt/apps/entropywatcher"
GITHUB_REPO="https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner.git"

DB_HOST="localhost"
DB_PORT="3306"
DB_NAME="entropywatcher"
DB_USER="entropyuser"
DB_PASSWORD=""

SMTP_HOST=""
SMTP_PORT="587"
SMTP_USER=""
SMTP_PASSWORD=""
SMTP_FROM=""
ADMIN_EMAIL=""

NAS_PATHS="/srv/nas/data,/srv/nas/media"
OS_PATHS="/,/boot,/home"

# ============================================================================
# Colors
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    printf "%s[%s]%s %s\n" "$GREEN" "$(date '+%F %T')" "$NC" "$*"
}

error() {
    printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$*" >&2
}

warn() {
    printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"
}

info() {
    printf "%s[INFO]%s %s\n" "$BLUE" "$NC" "$*"
}

# ============================================================================
# Helper Functions (P2 Fix)
# ============================================================================
cd_safe() {
    if ! cd "$1" 2>/dev/null; then
        error "Cannot change directory to $1"
        exit 1
    fi
}

start_service_if_not_running() {
    local service="$1"
    if ! systemctl is-active --quiet "$service"; then
        log "Starting $service..."
        systemctl start "$service" || warn "Failed to start $service (might be unavailable on this system)"
    else
        info "$service is already running"
    fi
}

enable_service_if_not_enabled() {
    local service="$1"
    if ! systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl enable "$service" >/dev/null 2>&1 || warn "Failed to enable $service (might be unavailable on this system)"
    fi
}

# ============================================================================
# Parse Arguments
# ============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --interactive)
            INTERACTIVE=1
            shift
            ;;
        --non-interactive)
            INTERACTIVE=0
            shift
            ;;
        --db-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --smtp-host)
            SMTP_HOST="$2"
            shift 2
            ;;
        --smtp-port)
            SMTP_PORT="$2"
            shift 2
            ;;
        --smtp-user)
            SMTP_USER="$2"
            shift 2
            ;;
        --smtp-password)
            SMTP_PASSWORD="$2"
            shift 2
            ;;
        --smtp-from)
            SMTP_FROM="$2"
            shift 2
            ;;
        --admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --nas-paths)
            NAS_PATHS="$2"
            shift 2
            ;;
        --os-paths)
            OS_PATHS="$2"
            shift 2
            ;;
        --install-clamav)
            INSTALL_CLAMAV=1
            shift
            ;;
        --skip-clamav)
            INSTALL_CLAMAV=0
            shift
            ;;
        --install-honeyfiles)
            INSTALL_HONEYFILES=1
            shift
            ;;
        --skip-honeyfiles)
            INSTALL_HONEYFILES=0
            shift
            ;;
        --skip-systemd)
            INSTALL_SYSTEMD=0
            shift
            ;;
        --skip-db-init)
            INIT_DATABASE=0
            shift
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Root Check
# ============================================================================
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# ============================================================================
# P3 Fix: Installation Logging
# ============================================================================
INSTALL_LOG="/var/log/entropywatcher-install.log"
info "Installation log: $INSTALL_LOG"
exec > >(tee -a "$INSTALL_LOG")
exec 2>&1

# ============================================================================
# Interactive Prompts
# ============================================================================
if [[ $INTERACTIVE -eq 1 ]]; then
    log "═══════════════════════════════════════════════════════════"
    log "EntropyWatcher Installation - Interactive Mode"
    log "═══════════════════════════════════════════════════════════"
    echo

    # MariaDB Password
    read -sp "MariaDB password for user 'entropyuser': " DB_PASSWORD
    echo
    if [[ -z "$DB_PASSWORD" ]]; then
        error "Database password cannot be empty"
        exit 1
    fi

    # SMTP Configuration
    read -p "SMTP Host (e.g., smtp.gmail.com): " SMTP_HOST
    read -p "SMTP Port [587]: " SMTP_PORT_INPUT
    SMTP_PORT="${SMTP_PORT_INPUT:-587}"
    read -p "SMTP User: " SMTP_USER
    read -sp "SMTP Password: " SMTP_PASSWORD
    echo
    read -p "Admin Email: " ADMIN_EMAIL

    # Scan Paths
    read -p "NAS Scan Paths [${NAS_PATHS}]: " NAS_PATHS_INPUT
    NAS_PATHS="${NAS_PATHS_INPUT:-$NAS_PATHS}"
    read -p "OS Scan Paths [${OS_PATHS}]: " OS_PATHS_INPUT
    OS_PATHS="${OS_PATHS_INPUT:-$OS_PATHS}"

    # Optional Components
    read -p "Install ClamAV? [Y/n]: " CLAMAV_CHOICE
    case "$CLAMAV_CHOICE" in
        [Nn]*) INSTALL_CLAMAV=0 ;;
        *) INSTALL_CLAMAV=1 ;;
    esac

    read -p "Install Honeyfiles + Auditd? [Y/n]: " HONEYFILE_CHOICE
    case "$HONEYFILE_CHOICE" in
        [Nn]*) INSTALL_HONEYFILES=0 ;;
        *) INSTALL_HONEYFILES=1 ;;
    esac

    echo
fi

# ============================================================================
# Validation (Non-Interactive)
# ============================================================================
if [[ $INTERACTIVE -eq 0 ]]; then
    if [[ -z "$DB_PASSWORD" ]]; then
        error "Non-interactive mode requires --db-password"
        exit 1
    fi
    if [[ -z "$SMTP_HOST" ]] || [[ -z "$SMTP_USER" ]] || [[ -z "$SMTP_PASSWORD" ]] || [[ -z "$ADMIN_EMAIL" ]]; then
        warn "SMTP configuration incomplete. Email alerts will not work."
        warn "Provide: --smtp-host, --smtp-user, --smtp-password, --admin-email"
    fi
    # Auto-decide on optional components if not specified
    if [[ -z "$INSTALL_CLAMAV" ]]; then
        INSTALL_CLAMAV=1  # Default: install
    fi
    if [[ -z "$INSTALL_HONEYFILES" ]]; then
        INSTALL_HONEYFILES=1  # Default: install
    fi
fi

# Default SMTP_FROM
if [[ -z "$SMTP_FROM" ]]; then
    SMTP_FROM="entropywatch@$(hostname -f)"
fi

# ============================================================================
# Summary
# ============================================================================
log "═══════════════════════════════════════════════════════════"
log "Installation Summary"
log "═══════════════════════════════════════════════════════════"
info "Install Directory: $INSTALL_DIR"
info "Database: $DB_NAME (User: $DB_USER)"
info "SMTP: $SMTP_HOST:$SMTP_PORT (User: $SMTP_USER)"
info "Admin Email: $ADMIN_EMAIL"
info "NAS Paths: $NAS_PATHS"
info "OS Paths: $OS_PATHS"
info "Install ClamAV: $([ "$INSTALL_CLAMAV" -eq 1 ] && echo 'YES' || echo 'NO')"
info "Install Honeyfiles: $([ "$INSTALL_HONEYFILES" -eq 1 ] && echo 'YES' || echo 'NO')"
info "Install Systemd Services: $([ "$INSTALL_SYSTEMD" -eq 1 ] && echo 'YES' || echo 'NO')"
log "═══════════════════════════════════════════════════════════"
echo

if [[ $INTERACTIVE -eq 1 ]]; then
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    case "$CONFIRM" in
        [Nn]*) 
            warn "Installation cancelled by user"
            exit 0
            ;;
    esac
fi

# ============================================================================
# STEP 0: Clone Repository (if needed)
# ============================================================================
if [[ ! -d "$INSTALL_DIR/main" ]]; then
    log "STEP 0: Cloning repository..."
    
    # Install git first if not available
    if ! command -v git &> /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq git
    fi
    
    # Create directory structure
    mkdir -p "$INSTALL_DIR"
    
    # Clone repository
    log "Cloning from $GITHUB_REPO..."
    if ! git clone "$GITHUB_REPO" "$INSTALL_DIR/main"; then
        error "Failed to clone repository from $GITHUB_REPO"
        exit 1
    fi
    
    log "✓ Repository cloned to $INSTALL_DIR/main"
else
    info "Repository already exists at $INSTALL_DIR/main (skipping clone)"
fi

# ============================================================================
# STEP 1: Install System Packages
# ============================================================================
log "STEP 1: Installing system packages..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
    git \
    python3 \
    python3-venv \
    python3-pip \
    mariadb-server \
    mariadb-client \
    libmariadb-dev \
    pkg-config \
    build-essential \
    curl \
    wget

log "✓ Base packages installed"

# ClamAV
if [[ $INSTALL_CLAMAV -eq 1 ]]; then
    log "Installing ClamAV..."
    apt-get install -y -qq \
        clamav \
        clamav-daemon \
        clamav-freshclam
    log "✓ ClamAV installed"
fi

# Auditd
if [[ $INSTALL_HONEYFILES -eq 1 ]]; then
    log "Installing Auditd..."
    apt-get install -y -qq auditd audispd-plugins
    log "✓ Auditd installed"
fi

# ============================================================================
# STEP 2: MariaDB Setup
# ============================================================================
if [[ $INIT_DATABASE -eq 1 ]]; then
    log "STEP 2: Setting up MariaDB..."

    # P2 Fix: Idempotent Service Start
    enable_service_if_not_enabled mariadb
    start_service_if_not_running mariadb

    # P1 Fix: Test MySQL connection first
    if ! mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        error "Cannot connect to MySQL as root. Check if MariaDB is secured or already configured."
        error "If root password exists, run: mysql_secure_installation"
        exit 1
    fi

    # Create Database + User
    log "Creating database and user..."
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} 
  CHARACTER SET utf8mb4 
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' 
  IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

    log "✓ Database initialized"
else
    warn "Skipping database initialization (--skip-db-init)"
fi

# ============================================================================
# STEP 3: Python Virtual Environment
# ============================================================================
log "STEP 3: Setting up Python virtual environment..."

# P2 Fix: Use cd_safe helper
cd_safe "$INSTALL_DIR/main"

python3 -m venv venv

# P3 Fix: Direct Python calls instead of source (non-interactive safe)
./venv/bin/pip install --quiet --upgrade pip
./venv/bin/pip install --quiet -r requirements.txt

log "✓ Python environment ready"

# ============================================================================
# STEP 4: Create common.env
# ============================================================================
log "STEP 4: Creating common.env..."

# Ensure config directory exists
mkdir -p "$INSTALL_DIR/main/config"

cat > "$INSTALL_DIR/main/config/common.env" <<'EOFCONFIG'
# ============================================================================
# EntropyWatcher Configuration
# Generated: TIMESTAMP_PLACEHOLDER
# ============================================================================

# ============================================================================
# DATABASE
# ============================================================================
DB_HOST=DB_HOST_PLACEHOLDER
DB_PORT=DB_PORT_PLACEHOLDER
DB_NAME=DB_NAME_PLACEHOLDER
DB_USER=DB_USER_PLACEHOLDER
DB_PASSWORD=DB_PASSWORD_PLACEHOLDER

# ============================================================================
# MAIL ALERTS
# ============================================================================
SMTP_HOST=SMTP_HOST_PLACEHOLDER
SMTP_PORT=SMTP_PORT_PLACEHOLDER
SMTP_USER=SMTP_USER_PLACEHOLDER
SMTP_PASSWORD=SMTP_PASSWORD_PLACEHOLDER
SMTP_FROM=SMTP_FROM_PLACEHOLDER
ADMIN_EMAIL=ADMIN_EMAIL_PLACEHOLDER

# ============================================================================
# SCAN PATHS
# ============================================================================
NAS_SCAN_PATHS=NAS_PATHS_PLACEHOLDER
NAS_SCAN_EXCLUDES=**/.git/**,**/*.swp,**/token.env,**/.Trash-*/**,**/@Recycle/**

OS_SCAN_PATHS=OS_PATHS_PLACEHOLDER
OS_SCAN_EXCLUDES=/proc/**,/sys/**,/dev/**,/run/**,/tmp/**,/var/cache/**,/var/tmp/**,/snap/**,**/.git/**

# ============================================================================
# CLAMAV
# ============================================================================
CLAMAV_ENABLED=CLAMAV_ENABLED_PLACEHOLDER
CLAMSCAN_BIN=/usr/bin/clamdscan
CLAMD_SOCKET=/var/run/clamav/clamd.ctl

# ============================================================================
# SAFETY GATE
# ============================================================================
SAFETY_GATE_FILE=/run/entropywatcher-safety-gate
SAFETY_GATE_LOCKFILE=/run/backup_pipeline.lock

# ============================================================================
# HONEYFILES
# ============================================================================
HONEYFILE_PATHS_FILE=INSTALL_DIR_PLACEHOLDER/config/honeyfile_paths
AUDITD_RULES_FILE=INSTALL_DIR_PLACEHOLDER/config/auditd_honeyfiles.rules
EOFCONFIG

# Substitute placeholders with actual values using sed
sed -i "s|TIMESTAMP_PLACEHOLDER|$(date '+%F %T')|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|DB_HOST_PLACEHOLDER|${DB_HOST}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|DB_PORT_PLACEHOLDER|${DB_PORT}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|DB_NAME_PLACEHOLDER|${DB_NAME}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|DB_USER_PLACEHOLDER|${DB_USER}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|DB_PASSWORD_PLACEHOLDER|${DB_PASSWORD}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|SMTP_HOST_PLACEHOLDER|${SMTP_HOST}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|SMTP_PORT_PLACEHOLDER|${SMTP_PORT}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|SMTP_USER_PLACEHOLDER|${SMTP_USER}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|SMTP_PASSWORD_PLACEHOLDER|${SMTP_PASSWORD}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|SMTP_FROM_PLACEHOLDER|${SMTP_FROM}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|ADMIN_EMAIL_PLACEHOLDER|${ADMIN_EMAIL}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|NAS_PATHS_PLACEHOLDER|${NAS_PATHS}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|OS_PATHS_PLACEHOLDER|${OS_PATHS}|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|CLAMAV_ENABLED_PLACEHOLDER|$([ "$INSTALL_CLAMAV" -eq 1 ] && echo 'true' || echo 'false')|g" "$INSTALL_DIR/main/config/common.env"
sed -i "s|INSTALL_DIR_PLACEHOLDER|${INSTALL_DIR}|g" "$INSTALL_DIR/main/config/common.env"

chmod 600 "$INSTALL_DIR/main/config/common.env"
log "✓ common.env created (chmod 600)"

# Copy other .env.example files to .env (without .example extension)
log "Processing config .env.example files..."
for example_file in "$INSTALL_DIR/main/config"/*.env.example; do
    if [[ -f "$example_file" ]]; then
        target_file="${example_file%.example}"
        cp "$example_file" "$target_file"
        chmod 600 "$target_file"
        log "  ✓ $(basename "$target_file")"
    fi
done

# ============================================================================
# STEP 5: ClamAV Setup
# ============================================================================
if [[ $INSTALL_CLAMAV -eq 1 ]]; then
    log "STEP 5: Configuring ClamAV..."

    # Stop freshclam service
    systemctl stop clamav-freshclam || true

    # Update signatures (timeout after 10 minutes)
    log "Updating ClamAV signatures (this may take 5-10 minutes)..."
    timeout 600 freshclam || {
        warn "Freshclam timeout or failed. Signatures might be outdated."
    }

    # Start services (idempotent)
    enable_service_if_not_enabled clamav-freshclam
    start_service_if_not_running clamav-freshclam
    enable_service_if_not_enabled clamav-daemon
    start_service_if_not_running clamav-daemon

    # Wait for socket
    for i in {1..30}; do
        if [[ -S /var/run/clamav/clamd.ctl ]]; then
            log "✓ ClamAV daemon ready"
            break
        fi
        sleep 1
    done

    if [[ ! -S /var/run/clamav/clamd.ctl ]]; then
        warn "ClamAV socket not found. Check: systemctl status clamav-daemon"
    fi
fi

# ============================================================================
# STEP 6: Honeyfiles + Auditd
# ============================================================================
if [[ $INSTALL_HONEYFILES -eq 1 ]]; then
    log "STEP 6: Setting up Honeyfiles + Auditd..."

    # Start Auditd (idempotent)
    enable_service_if_not_enabled auditd
    start_service_if_not_running auditd

    # Create config directory
    mkdir -p "$INSTALL_DIR/config"

    # Run setup_honeyfiles.sh
    if [[ -x "$INSTALL_DIR/main/tools/setup_honeyfiles.sh" ]]; then
        "$INSTALL_DIR/main/tools/setup_honeyfiles.sh" || {
            warn "setup_honeyfiles.sh failed - honeyfiles might not be created"
        }
        log "✓ Honeyfiles setup completed"
    else
        warn "setup_honeyfiles.sh not found or not executable"
    fi

    # Load auditd rules
    if [[ -f "$INSTALL_DIR/config/auditd_honeyfiles.rules" ]]; then
        auditctl -R "$INSTALL_DIR/config/auditd_honeyfiles.rules" || {
            warn "Failed to load auditd rules"
        }
        # Make persistent
        cp "$INSTALL_DIR/config/auditd_honeyfiles.rules" /etc/audit/rules.d/honeyfiles.rules
        log "✓ Auditd rules loaded"
    fi
fi

# ============================================================================
# STEP 7: Initialize Database Tables
# ============================================================================
log "STEP 7: Initializing database tables..."

cd_safe "$INSTALL_DIR/main"

# Use sql/init_db.sql if available
if [[ -f "$INSTALL_DIR/main/sql/init_db.sql" ]]; then
    mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$INSTALL_DIR/main/sql/init_db.sql" 2>/dev/null || {
        warn "Failed to initialize database from sql/init_db.sql"
    }
fi

# Verify tables exist
TABLES=$(mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SHOW TABLES;" 2>/dev/null | wc -l)
if [[ $TABLES -ge 5 ]]; then
    log "✓ Database tables created (${TABLES} tables)"
else
    warn "Database tables might not be created. Check sql/init_db.sql"
fi

# ============================================================================
# STEP 8: Install Systemd Services
# ============================================================================
if [[ $INSTALL_SYSTEMD -eq 1 ]]; then
    log "STEP 8: Installing systemd services..."

    SYSTEMD_DIR="$INSTALL_DIR/main/systemd"
    if [[ -d "$SYSTEMD_DIR" ]]; then
        # Rename .example files to actual service/timer files
        for file in "$SYSTEMD_DIR"/*.example; do
            if [[ -f "$file" ]]; then
                dest="/etc/systemd/system/$(basename "$file" .example)"
                cp "$file" "$dest"
            fi
        done

        systemctl daemon-reload

        # Enable timers
        systemctl enable entropywatcher-nas.timer >/dev/null 2>&1 || true
        systemctl start entropywatcher-nas.timer || warn "Failed to start entropywatcher-nas.timer"

        systemctl enable entropywatcher-os.timer >/dev/null 2>&1 || true
        systemctl start entropywatcher-os.timer || warn "Failed to start entropywatcher-os.timer"

        if [[ $INSTALL_CLAMAV -eq 1 ]]; then
            systemctl enable entropywatcher-nas-av.timer >/dev/null 2>&1 || true
            systemctl start entropywatcher-nas-av.timer || warn "Failed to start entropywatcher-nas-av.timer"

            systemctl enable entropywatcher-os-av.timer >/dev/null 2>&1 || true
            systemctl start entropywatcher-os-av.timer || warn "Failed to start entropywatcher-os-av.timer"
        fi

        log "✓ Systemd services installed and started"
    else
        warn "Systemd directory not found: $SYSTEMD_DIR"
    fi
fi

# ============================================================================
# STEP 9: Test Installation
# ============================================================================
log "STEP 9: Testing installation..."

# Test DB connection
cd_safe "$INSTALL_DIR/main"

DB_TEST=$(mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" "$DB_NAME" -se "SELECT 1;" 2>/dev/null || echo "FAIL")
if [[ "$DB_TEST" == "1" ]]; then
    log "✓ Database connection OK"
else
    error "✗ Database connection FAILED"
fi

# Test ClamAV (if installed)
if [[ $INSTALL_CLAMAV -eq 1 ]] && [[ -S /var/run/clamav/clamd.ctl ]]; then
    log "✓ ClamAV daemon OK"
else
    if [[ $INSTALL_CLAMAV -eq 1 ]]; then
        warn "✗ ClamAV daemon not running"
    fi
fi

# Test Auditd (if installed)
if [[ $INSTALL_HONEYFILES -eq 1 ]]; then
    AUDIT_RULES=$(auditctl -l 2>/dev/null | grep -c honeyfile || true)
    if [[ $AUDIT_RULES -gt 0 ]]; then
        log "✓ Auditd rules active (${AUDIT_RULES} rules)"
    else
        warn "✗ Auditd rules not loaded (expected in WSL)"
    fi
fi

# ============================================================================
# P1 Fix: Cleanup Sensitive Variables
# ============================================================================
# Passwort erst NACH allen DB-Operationen (STEP 2, 4, 7, 9) löschen
unset DB_PASSWORD
unset SMTP_PASSWORD

# ============================================================================
# DONE
# ============================================================================
log "═══════════════════════════════════════════════════════════"
log "✅ Installation Complete!"
log "═══════════════════════════════════════════════════════════"
echo
info "Next steps:"
info "  1. Review configuration: $INSTALL_DIR/main/config/common.env"
info "  2. Test mail alerts: python3 $INSTALL_DIR/main/tools/test_mail_config.py"
info "  3. Check timer status: sudo systemctl list-timers 'entropywatcher*'"
info "  4. View service logs: sudo journalctl -u entropywatcher-nas.service -f"
info "  5. Read full documentation: $INSTALL_DIR/main/docs/INSTALLATION.md"
echo
log "Installation log: /var/log/entropywatcher-install.log"
log "═══════════════════════════════════════════════════════════"

exit 0
