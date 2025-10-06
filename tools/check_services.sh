#!/bin/bash
# Quick health check for all EntropyWatcher services and timers
# Displays status, next run times, and recent failures

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Services to check
SERVICES=(
    "ew-nas.service"
    "ew-nas-av.service"
    "ew-nas-av-weekly.service"
    "ew-os.service"
    "ew-os-av.service"
    "ew-os-av-weekly.service"
    "honeyfile-monitor.service"
)

TIMERS=(
    "ew-nas.timer"
    "ew-nas-av.timer"
    "ew-nas-av-weekly.timer"
    "ew-os.timer"
    "ew-os-av.timer"
    "ew-os-av-weekly.timer"
    "honeyfile-monitor.timer"
)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  EntropyWatcher Health Check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check systemd timers
echo -e "${BLUE}⏰ Timer Status:${NC}"
echo ""
for timer in "${TIMERS[@]}"; do
    if systemctl is-active --quiet "$timer"; then
        status="${GREEN}●${NC} ACTIVE"
        
        # Get next run time
        next_run=$(systemctl status "$timer" 2>/dev/null | grep -oP 'Trigger: \K.*' | head -1)
        if [[ -z "$next_run" ]]; then
            next_run="unknown"
        fi
        
        printf "  %-30s %b  Next: %s\n" "$timer" "$status" "$next_run"
    else
        status="${RED}○${NC} INACTIVE"
        printf "  %-30s %b\n" "$timer" "$status"
    fi
done

echo ""
echo -e "${BLUE}⚙️  Service Status:${NC}"
echo ""

# Check services
for service in "${SERVICES[@]}"; do
    # Check if service exists
    if ! systemctl list-unit-files "$service" &>/dev/null; then
        printf "  %-30s ${YELLOW}?${NC} NOT FOUND\n" "$service"
        continue
    fi
    
    # Get service status
    if systemctl is-active --quiet "$service"; then
        status="${GREEN}●${NC} RUNNING"
    elif systemctl is-failed --quiet "$service"; then
        status="${RED}●${NC} FAILED"
    else
        status="${YELLOW}○${NC} INACTIVE"
    fi
    
    # Get last exit code
    exit_code=$(systemctl show "$service" -p ExecMainStatus --value)
    
    # Get last runtime
    last_trigger=$(systemctl show "$service" -p ExecMainStartTimestamp --value)
    if [[ -n "$last_trigger" && "$last_trigger" != "n/a" ]]; then
        last_run="Last: $last_trigger"
    else
        last_run="Never run"
    fi
    
    printf "  %-30s %b  Exit: %-3s  %s\n" "$service" "$status" "$exit_code" "$last_run"
done

echo ""
echo -e "${BLUE}🚨 Recent Failures (last 24h):${NC}"
echo ""

# Check for recent failures in journal
failures=$(journalctl --since "24 hours ago" -u "ew-*.service" -u "honeyfile-monitor.service" -p err -o cat --no-pager 2>/dev/null | wc -l)

if [[ $failures -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} No errors in the last 24 hours"
else
    echo -e "  ${YELLOW}⚠${NC}  Found $failures error entries:"
    echo ""
    journalctl --since "24 hours ago" -u "ew-*.service" -u "honeyfile-monitor.service" -p err --no-pager | tail -20
fi

echo ""
echo -e "${BLUE}📊 Quick Stats:${NC}"
echo ""

# Count active vs inactive
active_timers=$(systemctl is-active "${TIMERS[@]}" 2>/dev/null | grep -c "^active$" || true)
total_timers=${#TIMERS[@]}

active_services=0
failed_services=0
for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        ((active_services++))
    fi
    if systemctl is-failed --quiet "$service"; then
        ((failed_services++))
    fi
done

echo -e "  Timers:   ${active_timers}/${total_timers} active"
echo -e "  Services: ${active_services} running, ${failed_services} failed"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Exit with error if any service failed
if [[ $failed_services -gt 0 ]]; then
    echo -e "${RED}⚠  Warning: $failed_services service(s) in failed state${NC}"
    exit 1
fi

exit 0
