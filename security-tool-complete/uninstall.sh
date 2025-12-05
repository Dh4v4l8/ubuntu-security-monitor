#!/bin/bash
# SECURITY MONITOR - UNINSTALLATION SCRIPT
# Run: sudo bash uninstall.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${RED}"
cat << "EOF"
╔══════════════════════════════════════╗
║    SECURITY MONITOR UNINSTALL        ║
╚══════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo $0${NC}"
    exit 1
fi

echo -e "${YELLOW}This will completely remove Security Monitor.${NC}"
echo ""
echo "The following will be removed:"
echo "1. Security Monitor service"
echo "2. /opt/security-monitor/"
echo "3. /etc/security-monitor/"
echo "4. Systemd service files"
echo ""

read -p "Are you sure? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}[1/6] Stopping service...${NC}"
systemctl stop security-monitor.service 2>/dev/null
sleep 2

echo -e "${YELLOW}[2/6] Disabling service...${NC}"
systemctl disable security-monitor.service 2>/dev/null

echo -e "${YELLOW}[3/6] Removing systemd service...${NC}"
rm -f /etc/systemd/system/security-monitor.service
systemctl daemon-reload 2>/dev/null

echo -e "${YELLOW}[4/6] Removing directories...${NC}"
rm -rf /opt/security-monitor
rm -rf /etc/security-monitor
rm -rf /var/lib/security-monitor

echo -e "${YELLOW}[5/6] Removing log files...${NC}"
rm -rf /var/log/security-monitor 2>/dev/null
rm -rf /tmp/security-photos 2>/dev/null

echo -e "${YELLOW}[6/6] Cleaning up...${NC}"
# Remove commands if any
rm -f /usr/local/bin/security-monitor 2>/dev/null
rm -f /usr/local/bin/security-config 2>/dev/null

echo ""
echo -e "${GREEN}✅ SECURITY MONITOR COMPLETELY REMOVED${NC}"
echo ""
echo -e "${YELLOW}Note: Configuration and logs have been deleted.${NC}"
echo ""
