 EntropyWatcher Installation Guide

Complete production deployment guide for EntropyWatcher & ClamAV Scanner.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Automated Installation](#automated-installation)
3. [Manual Installation](#manual-installation)
4. [Configuration](#configuration)
5. [Database Setup](#database-setup)
6. [systemd Integration](#systemd-integration)
7. [Honeyfile Setup](#honeyfile-setup)
8. [Verification](#verification)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

- **OS:** Debian 11+ or Ubuntu 20.04+
- **RAM:** 2 GB minimum (4 GB+ recommended)
- **Storage:** 5 GB free space for installation
- **User:** root access (sudo)

### Required Packages (auto-installed)

- Python 3.9+
- MariaDB Server 10.5+
- Git
- Build tools (gcc, make, etc.)
- auditd
- libmariadb-dev

### Optional Packages

- ClamAV (antivirus scanning)
- ClamAV daemon (clamd)

---

## Automated Installation

### Interactive Mode (Recommended)

```bash
sudo bash tools/install.sh --interactive
```

You'll be prompted for:
- MariaDB password
- SMTP configuration (host, port, user, password, admin email)
- Scan paths (NAS and OS)
- Optional components (ClamAV, Honeyfiles, systemd)

### Non-Interactive Mode

For CI/CD or scripted deployments:

```bash
sudo bash tools/install.sh --non-interactive \
  --db-password "secure_password" \
  --smtp-host mail.example.com \
  --smtp-user alerts@example.com \
  --smtp-password "smtp_password" \
  --admin-email admin@example.com \
  --install-clamav
```

### What Gets Installed

The installer automates:

| Component | Details |
|-----------|---------|
| **System Deps** | MariaDB, Python 3, git, auditd, build-essential |
| **ClamAV** | Optional antivirus with signature updates (--install-clamav) |
| **Database** | entropywatcher DB + dedicated user (entropyuser) |
| **Python venv** | Virtual environment with all dependencies |
| **systemd Units** | Service + timer files for automated execution |
| **auditd Rules** | Honeyfile detection (Tier 1/2/3) |
| **Honeyfiles** | Randomized credential traps with audit rules |
| **common.env** | Auto-generated configuration |

---

## Manual Installation

If you prefer step-by-step control or the automated installer doesn't suit your environment:

### 1. Install System Dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
  git \
  python3 python3-venv python3-dev \
  mariadb-server mariadb-client \
  libmariadb-dev \
  build-essential \
  curl wget \
  auditd audispd-plugins
```

### 2. Clone Repository

```bash
sudo mkdir -p /opt/apps/entropywatcher
sudo git clone https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner \
  /opt/apps/entropywatcher/main
cd /opt/apps/entropywatcher/main
```

### 3. Start and Setup MariaDB

```bash
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Create database and user
sudo mysql << EOF
CREATE DATABASE entropywatcher CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'entropyuser'@'localhost' IDENTIFIED BY 'your_secure_password';
GRANT ALL PRIVILEGES ON entropywatcher.* TO 'entropyuser'@'localhost';
FLUSH PRIVILEGES;
EOF
```

### 4. Initialize Database Schema

```bash
sudo mysql entropywatcher < sql/init_db.sql
```

### 5. Create Python Virtual Environment

```bash
cd /opt/apps/entropywatcher/main
sudo python3 -m venv venv
sudo venv/bin/pip install --upgrade pip
sudo venv/bin/pip install -r requirements.txt
```

### 6. Setup Configuration

```bash
# Copy template
sudo cp examples/config/common.env.example config/common.env

# Edit with your settings
sudo nano config/common.env
```

Edit these critical values:

```bash
DB_HOST=localhost
DB_PORT=3306
DB_NAME=entropywatcher
DB_USER=entropyuser
DB_PASS=your_secure_password

SMTP_HOST=mail.example.com
SMTP_PORT=587
SMTP_USER=alerts@example.com
SMTP_PASSWORD=your_smtp_password
ADMIN_EMAIL=admin@example.com
```

### 7. Optional: Install ClamAV

```bash
sudo apt-get install -y clamav clamav-daemon clamav-freshclam

# Update signatures
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam clamav-daemon
```

### 8. Optional: Setup Honeyfiles

```bash
sudo systemctl start auditd
sudo systemctl enable auditd

# Run setup script
sudo bash tools/setup_honeyfiles.sh

# Load auditd rules (output will show the command)
sudo auditctl -R /path/to/auditd_honeyfiles.rules
```

### 9. Setup systemd Services

```bash
# Copy service files
sudo cp systemd/*.service /etc/systemd/system/
sudo cp systemd/*.timer /etc/systemd/system/

# Remove .example extension if present
sudo rename 's/\.example$//' /etc/systemd/system/entropywatcher*.{service,timer} 2>/dev/null || true

# Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable entropywatcher-nas.timer
sudo systemctl enable entropywatcher-os.timer
sudo systemctl start entropywatcher-nas.timer
sudo systemctl start entropywatcher-os.timer
```

---

## Configuration

### Main Configuration (common.env)

```bash
sudo nano /opt/apps/entropywatcher/config/common.env
```

**Required settings:**

```bash
# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=entropywatcher
DB_USER=entropyuser
DB_PASS=your_secure_password

# Mail Alerts
MAIL_ENABLE=1
MAIL_SMTP_HOST=mail.example.com
MAIL_SMTP_PORT=587
MAIL_STARTTLS=1
MAIL_USER=alerts@example.com
MAIL_PASS='smtp_password'
MAIL_TO=admin@example.com

# Entropy Thresholds
ALERT_ENTROPY_ABS=7.8
ALERT_ENTROPY_JUMP=0.2
```

### Service-Specific Configuration

**NAS Scans:**

```bash
sudo nano /opt/apps/entropywatcher/config/nas.env
```

```bash
SCAN_PATHS="/srv/nas/User1,/srv/nas/Shared"
SCAN_EXCLUDES="/srv/nas/.snapshots,/srv/nas/.Recycle.Bin"
```

**OS Scans:**

```bash
sudo nano /opt/apps/entropywatcher/config/os.env
```

```bash
SCAN_PATHS="/home,/var,/etc"
SCAN_EXCLUDES="/var/cache,/var/log,/var/tmp"
```

---

## Database Setup

### Verify Schema

```bash
sudo mysql entropywatcher << EOF
SHOW TABLES;
DESCRIBE files;
DESCRIBE scan_summary;
DESCRIBE av_events;
DESCRIBE av_whitelist;
DESCRIBE run_summaries;
EOF
```

Expected: 5 tables with proper columns

### Test Connection

```bash
sudo mysql -u entropyuser -p -h localhost entropywatcher -e "SELECT 1;"
```

---

## systemd Integration

### Enable Services

```bash
# NAS and OS scans
sudo systemctl enable --now entropywatcher-nas.timer
sudo systemctl enable --now entropywatcher-os.timer

# ClamAV scans (optional)
sudo systemctl enable --now entropywatcher-nas-av.timer
sudo systemctl enable --now entropywatcher-os-av.timer

# Honeyfile monitoring (if installed)
sudo systemctl enable --now honeyfile-monitor.timer
```

### Check Status

```bash
systemctl list-timers | grep entropywatcher
journalctl -u entropywatcher-nas.service -f
```

---

## Honeyfile Setup

### Automatic Setup

```bash
sudo bash /opt/apps/entropywatcher/main/tools/setup_honeyfiles.sh
```

The script will:
- Create 7 honeypot files with randomized names
- Configure auditd detection rules (Tier 1/2/3)
- Output exclusion patterns for your config

### Manual Configuration

If you need custom paths, edit the script:

```bash
sudo nano /opt/apps/entropywatcher/main/tools/setup_honeyfiles.sh
```

Find and modify the `HONEYFILE_TEMPLATES` array, then run the setup.

### Add Exclusions to common.env

After setup, copy the output patterns into config:

```bash
sudo nano /opt/apps/entropywatcher/config/common.env
```

```bash
SCAN_EXCLUDES="/root/.aws/credentials_a7f3e_20251214,/root/.git-credentials_b8g2h_20251214,..."
```

---

## Verification

### 1. Python and Dependencies

```bash
sudo /opt/apps/entropywatcher/main/venv/bin/python3 -c \
  "import sys; sys.path.insert(0, '/opt/apps/entropywatcher/main'); from entropywatcher import *; print('✓ Import OK')"
```

### 2. Database Connection

```bash
sudo mysql -u entropyuser -p -h localhost entropywatcher << EOF
SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='entropywatcher';
EOF
```

### 3. Run a Test Scan

```bash
sudo /opt/apps/entropywatcher/main/venv/bin/python3 \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  init-scan --paths "/srv/nas"
```

### 4. Check systemd Services

```bash
sudo systemctl status entropywatcher-nas.timer
sudo journalctl -u entropywatcher-nas.service -n 50
```

### 5. Test Mail Configuration

```bash
sudo /opt/apps/entropywatcher/main/tools/test_mail_config.py
```

---

## Troubleshooting

### MariaDB Connection Failed

```bash
sudo systemctl restart mariadb
sudo mysql -u root -e "SHOW DATABASES;"
```

### Python Module ImportError

```bash
sudo /opt/apps/entropywatcher/main/venv/bin/pip install --upgrade mariadb
```

### systemd Timer Never Executes

```bash
# Check timer
sudo systemctl status entropywatcher-nas.timer

# View next scheduled run
sudo systemctl list-timers | grep entropywatcher

# Manually trigger
sudo systemctl start entropywatcher-nas.service

# Watch logs
sudo journalctl -u entropywatcher-nas.service -f
```

### Auditd Rules Not Applied

```bash
sudo systemctl restart auditd
sudo auditctl -l | grep honeyfile
```

### ClamAV Socket Not Found

```bash
sudo systemctl restart clamav-daemon
sudo ls -la /var/run/clamav/clamd.ctl
```

---

## Next Steps

1. Configure mail alerts in `common.env`
2. Adjust `NAS_SCAN_PATHS` and `OS_SCAN_PATHS` for your environment
3. Run baseline scans: `init-scan`
4. Monitor with `ew_status.sh`
5. Integrate with backup pipeline (RTB/pCloud)

See [CONFIG.md](CONFIG.md) for detailed configuration options.
