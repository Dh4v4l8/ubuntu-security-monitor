#!/bin/bash
# SECURITY MONITOR - INSTALLATION SCRIPT
# Run: sudo bash install.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════╗
║    SECURITY MONITOR INSTALLATION     ║
╚══════════════════════════════════════╝
EOF
echo -e "${NC}"

# ========== CHECK ROOT ==========
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo $0${NC}"
    exit 1
fi

# ========== STEP 1: CHECK SYSTEM ==========
echo -e "${YELLOW}[1/8] Checking system requirements...${NC}"

# Check OS
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}❌ Unsupported OS${NC}"
    exit 1
fi

. /etc/os-release
echo -e "${BLUE}✓ OS: $PRETTY_NAME${NC}"

# Check Python
if command -v python3 >/dev/null 2>&1; then
    echo -e "${BLUE}✓ Python3: $(python3 --version)${NC}"
else
    echo -e "${YELLOW}⚠ Installing Python3...${NC}"
    apt update && apt install -y python3 python3-pip
fi

# ========== STEP 2: INSTALL DEPENDENCIES ==========
echo -e "${YELLOW}[2/8] Installing dependencies...${NC}"

apt update
apt install -y fswebcam curl wget git jq

# Install Python packages
if [ -f "requirements.txt" ]; then
    echo -e "${BLUE}Installing Python packages...${NC}"
    pip3 install -r requirements.txt
else
    echo -e "${BLUE}Installing Python packages...${NC}"
    pip3 install requests python-telegram-bot pillow
fi

# ========== STEP 3: CREATE DIRECTORIES ==========
echo -e "${YELLOW}[3/8] Creating directories...${NC}"

INSTALL_DIR="/opt/security-monitor"
CONFIG_DIR="/etc/security-monitor"
LOG_DIR="/var/log/security-monitor"
DATA_DIR="/var/lib/security-monitor"
PHOTO_DIR="/tmp/security-photos"

mkdir -p $INSTALL_DIR/src
mkdir -p $CONFIG_DIR
mkdir -p $LOG_DIR
mkdir -p $DATA_DIR/{pending,backup}
mkdir -p $PHOTO_DIR

echo -e "${BLUE}✓ Created all directories${NC}"

# ========== STEP 4: TELEGRAM SETUP ==========
echo -e "${YELLOW}[4/8] Telegram Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -f "$CONFIG_DIR/config.json" ]; then
    echo -e "${YELLOW}⚠ Existing configuration found.${NC}"
    read -p "Keep existing config? (y/n): " keep_config
    if [ "$keep_config" = "y" ] || [ "$keep_config" = "Y" ]; then
        echo -e "${BLUE}✓ Keeping existing configuration${NC}"
    else
        get_new_config=true
    fi
else
    get_new_config=true
fi

if [ "$get_new_config" = true ]; then
    echo ""
    echo -e "${YELLOW}📱 TELEGRAM BOT SETUP:${NC}"
    echo "1. Open Telegram, search @BotFather"
    echo "2. Send: /newbot"
    echo "3. Choose bot name and username"
    echo "4. Copy the token (format: 1234567890:ABCdefGHIjkl...)"
    echo ""
    read -p "Enter Bot Token: " TELEGRAM_TOKEN
    read -p "Enter Chat ID: " TELEGRAM_CHAT_ID
    
    # Validate token format
    if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
        echo -e "${YELLOW}⚠ Token format warning (continuing anyway)${NC}"
    fi
fi

# ========== STEP 5: COPY FILES ==========
echo -e "${YELLOW}[5/8] Installing files...${NC}"

# Copy source files
cp -f src/monitor.sh $INSTALL_DIR/src/

# Create alert.py file
cat > $INSTALL_DIR/src/alert.py << 'ALERTPY'
#!/usr/bin/env python3
"""
Security Monitor - Alert Handler
Handles photo capture and Telegram notifications
"""

import os
import sys
import json
import time
import logging
import subprocess
from datetime import datetime
from pathlib import Path
import requests
from typing import Optional

# Paths
CONFIG_FILE = "/etc/security-monitor/config.json"
LOG_FILE = "/var/log/security-monitor/alert.log"
PENDING_DIR = "/var/lib/security-monitor/pending"
PHOTO_DIR = "/tmp/security-photos"

# Setup logging
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class AlertHandler:
    def __init__(self):
        self.config = self.load_config()
        
    def load_config(self):
        """Load configuration"""
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return {}
    
    def check_internet(self):
        """Check internet connectivity"""
        try:
            requests.get("https://api.telegram.org", timeout=3)
            return True
        except:
            return False
    
    def capture_photo(self) -> Optional[str]:
        """
        Capture photo from webcam
        Camera only turns on during this function
        """
        try:
            os.makedirs(PHOTO_DIR, exist_ok=True)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            photo_path = f"{PHOTO_DIR}/login_{timestamp}.jpg"
            
            # Camera command - only runs when triggered
            cmd = [
                'fswebcam',
                '-d', self.config.get('camera_device', '/dev/video0'),
                '-r', self.config.get('photo_resolution', '640x480'),
                '--no-banner',
                '--jpeg', str(self.config.get('photo_quality', 85)),
                '--save', photo_path,
                '--quiet'
            ]
            
            logger.info("📸 Capturing photo...")
            result = subprocess.run(cmd, capture_output=True, timeout=5)
            
            if result.returncode == 0 and os.path.exists(photo_path):
                # Check if photo has content
                if os.path.getsize(photo_path) > 1024:
                    logger.info(f"✅ Photo captured: {photo_path}")
                    return photo_path
                else:
                    logger.warning("⚠️  Photo captured but file is too small")
                    os.remove(photo_path)
                    return None
            else:
                logger.error(f"❌ Photo capture failed: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            logger.error("❌ Photo capture timeout")
            return None
        except Exception as e:
            logger.error(f"❌ Error capturing photo: {e}")
            return None
    
    def send_alert(self, username: str, event_type: str):
        """Send alert to Telegram"""
        token = self.config.get('telegram_token')
        chat_id = self.config.get('telegram_chat_id')
        
        if not token or not chat_id:
            logger.error("❌ Telegram credentials missing")
            return False
        
        # Create message
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        hostname = os.uname().nodename
        ip_address = self.get_ip_address()
        
        if event_type == "SUCCESS":
            emoji = "✅"
            status = "LOGIN SUCCESS"
        elif event_type == "FAILED":
            emoji = "🚨"
            status = "LOGIN FAILED"
        elif event_type == "STARTUP":
            emoji = "🟢"
            status = "SYSTEM STARTED"
        else:
            emoji = "⚠️"
            status = event_type
        
        message = f"""
{emoji} <b>SECURITY ALERT</b> {emoji}

🖥️ <b>System:</b> {hostname}
👤 <b>User:</b> {username}
🔐 <b>Event:</b> {status}
🕐 <b>Time:</b> {timestamp}
📍 <b>IP:</b> {ip_address}

<i>Automated Security Notification</i>
"""
        # Capture photo if enabled and not startup
        photo_path = None
        if self.config.get('enable_photos', True) and event_type != "STARTUP":
            photo_path = self.capture_photo()
        
        # Check internet
        if not self.check_internet():
            logger.info("🌐 Internet offline, storing pending alert")
            self.store_pending(message, photo_path)
            return False
        
        # Send to Telegram
        try:
            if photo_path and os.path.exists(photo_path):
                # Send with photo
                with open(photo_path, 'rb') as photo:
                    url = f"https://api.telegram.org/bot{token}/sendPhoto"
                    files = {'photo': photo}
                    data = {'chat_id': chat_id, 'caption': message}
                    response = requests.post(url, data=data, files=files, timeout=10)
            else:
                # Send text only
                url = f"https://api.gram.org/bot{token}/sendMessage"
                data = {'chat_id': chat_id, 'text': message, 'parse_mode': 'HTML'}
                response = requests.post(url, json=data, timeout=10)
            
            if response.status_code == 200:
                logger.info(f"✅ Alert sent for {username}")
                
                # Cleanup photo
                if photo_path and os.path.exists(photo_path):
                    try:
                        os.remove(photo_path)
                    except:
                        pass
                
                # Send pending alerts
                self.send_pending_alerts()
                return True
            else:
                logger.error(f"❌ Telegram API error: {response.text}")
                self.store_pending(message, photo_path)
                return False
                
        except Exception as e:
            logger.error(f"❌ Error sending alert: {e}")
            self.store_pending(message, photo_path)
            return False
    
    def get_ip_address(self):
        """Get system IP address"""
        try:
            result = subprocess.run(['hostname', '-I'], capture_output=True, text=True)
            return result.stdout.strip().split()[0] if result.stdout.strip() else "N/A"
        except:
            return "N/A"
    
    def store_pending(self, message: str, photo_path: Optional[str] = None):
        """Store alert for later sending"""
        try:
            os.makedirs(PENDING_DIR, exist_ok=True)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            pending_file = f"{PENDING_DIR}/alert_{timestamp}.json"
            
            data = {
                'timestamp': timestamp,
                'message': message,
                'photo_path': photo_path if photo_path and os.path.exists(photo_path) else None
            }
            
            with open(pending_file, 'w') as f:
                json.dump(data, f)
            
            logger.info(f"💾 Stored pending alert: {pending_file}")
            
        except Exception as e:
            logger.error(f"❌ Error storing pending alert: {e}")
    
    def send_pending_alerts(self):
        """Send any pending alerts"""
        if not self.check_internet():
            return
        
        try:
            pending_files = list(Path(PENDING_DIR).glob("alert_*.json"))
            for pending_file in sorted(pending_files):
                try:
                    with open(pending_file, 'r') as f:
                        data = json.load(f)
                    
                    token = self.config.get('telegram_token')
                    chat_id = self.config.get('telegram_chat_id')
                    photo_path = data.get('photo_path')
                    
                    if photo_path and os.path.exists(photo_path):
                        with open(photo_path, 'rb') as photo:
                            url = f"https://api.telegram.org/bot{token}/sendPhoto"
                            files = {'photo': photo}
                            data_msg = {'chat_id': chat_id, 'caption': data['message']}
                            response = requests.post(url, data=data_msg, files=files, timeout=10)
                    else:
                        url = f"https://api.telegram.org/bot{token}/sendMessage"
                        data_msg = {'chat_id': chat_id, 'text': data['message'], 'parse_mode': 'HTML'}
                        response = requests.post(url, json=data_msg, timeout=10)
                    
                    if response.status_code == 200:
                        # Delete pending file
                        os.remove(pending_file)
                        
                        # Delete photo if exists
                        if photo_path and os.path.exists(photo_path):
                            try:
                                os.remove(photo_path)
                            except:
                                pass
                        
                        logger.info(f"✅ Sent pending alert: {pending_file}")
                        
                except Exception as e:
                    logger.error(f"❌ Error sending pending alert: {e}")
                    
        except Exception as e:
            logger.error(f"❌ Error in send_pending_alerts: {e}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 alert.py <username> <event_type>")
        print("Event types: SUCCESS, FAILED, STARTUP")
        sys.exit(1)
    
    username = sys.argv[1]
    event_type = sys.argv[2].upper()
    
    handler = AlertHandler()
    handler.send_alert(username, event_type)

if __name__ == "__main__":
    main()
ALERTPY

chmod +x $INSTALL_DIR/src/alert.py

# Copy configuration setup
if [ -f "config/setup.sh" ]; then
    cp -f config/setup.sh $INSTALL_DIR/
    chmod +x $INSTALL_DIR/setup.sh
fi

# Create configuration
if [ "$get_new_config" = true ]; then
    cat > $CONFIG_DIR/config.json << EOF
{
    "telegram_token": "$TELEGRAM_TOKEN",
    "telegram_chat_id": "$TELEGRAM_CHAT_ID",
    "camera_device": "/dev/video0",
    "photo_quality": 85,
    "photo_resolution": "640x480",
    "cooldown_seconds": 10,
    "enable_photos": true,
    "log_level": "INFO"
}
EOF
    chmod 600 $CONFIG_DIR/config.json
fi

# Copy systemd service
if [ -f "scripts/security-monitor.service" ]; then
    cp -f scripts/security-monitor.service /etc/systemd/system/
else
    # Create service file if not exists
    cat > /etc/systemd/system/security-monitor.service << 'SERVICE'
[Unit]
Description=Security Monitor Service
Documentation=https://github.com/yourusername/security-monitor
After=network.target multi-user.target
Wants=network.target
Requires=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/security-monitor
ExecStart=/bin/bash /opt/security-monitor/src/monitor.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security
ProtectSystem=strict
ReadWritePaths=/tmp/security-photos /var/log/security-monitor /var/lib/security-monitor
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE
fi

# Copy requirements.txt
if [ -f "requirements.txt" ]; then
    cp -f requirements.txt $INSTALL_DIR/
fi

# Create test script
cat > $INSTALL_DIR/test.sh << 'TEST'
#!/bin/bash
# Test script for security monitor

CONFIG_FILE="/etc/security-monitor/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found!"
    exit 1
fi

# Try jq first, then fallback to grep
if command -v jq >/dev/null 2>&1; then
    TOKEN=$(jq -r '.telegram_token' "$CONFIG_FILE" 2>/dev/null)
    CHAT_ID=$(jq -r '.telegram_chat_id' "$CONFIG_FILE" 2>/dev/null)
else
    TOKEN=$(grep '"telegram_token"' "$CONFIG_FILE" | cut -d'"' -f4)
    CHAT_ID=$(grep '"telegram_chat_id"' "$CONFIG_FILE" | cut -d'"' -f4)
fi

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Telegram credentials not found in config"
    exit 1
fi

echo "Sending test alert..."
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="✅ Test Alert from Security Monitor
Time: $(date)
Host: $(hostname)
Status: Working correctly" \
    -d parse_mode="HTML"

if [ $? -eq 0 ]; then
    echo "✅ Test alert sent successfully!"
else
    echo "❌ Failed to send test alert"
fi
TEST

chmod +x $INSTALL_DIR/test.sh

# Set permissions
chmod 755 $INSTALL_DIR/src/*
chmod 644 $CONFIG_DIR/config.json

echo -e "${BLUE}✓ Files installed${NC}"

# ========== STEP 6: SYSTEMD SERVICE ==========
echo -e "${YELLOW}[6/8] Setting up system service...${NC}"

systemctl daemon-reload
systemctl enable security-monitor.service

echo -e "${BLUE}✓ Systemd service configured${NC}"

# ========== STEP 7: WEB CAMERA CHECK ==========
echo -e "${YELLOW}[7/8] Checking webcam...${NC}"

if [ -e "/dev/video0" ]; then
    echo -e "${BLUE}✓ Webcam detected: /dev/video0${NC}"
    
    # Test webcam
    if command -v fswebcam >/dev/null 2>&1; then
        timeout 5 fswebcam --no-banner $PHOTO_DIR/test.jpg 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${BLUE}✓ Webcam test successful${NC}"
            rm -f $PHOTO_DIR/test.jpg
        else
            echo -e "${YELLOW}⚠ Webcam test failed (may require permissions)${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ No webcam detected at /dev/video0${NC}"
    echo -e "${YELLOW}Note: You can change device in config later${NC}"
fi

# ========== STEP 8: FINAL SETUP ==========
echo -e "${YELLOW}[8/8] Finalizing installation...${NC}"

# Start service
systemctl start security-monitor.service

# Wait a moment
sleep 2

# Check service status
if systemctl is-active --quiet security-monitor.service; then
    echo -e "${GREEN}✅ Service started successfully${NC}"
else
    echo -e "${YELLOW}⚠ Service may need troubleshooting${NC}"
    echo -e "${YELLOW}Run: sudo systemctl status security-monitor.service${NC}"
fi

# ========== INSTALLATION COMPLETE ==========
echo -e "${GREEN}"
echo "╔══════════════════════════════════════╗"
echo "║     INSTALLATION COMPLETE!           ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BLUE}📊 INSTALLATION SUMMARY:${NC}"
echo "────────────────────────────────"
echo -e "Installation dir: ${INSTALL_DIR}"
echo -e "Configuration:    ${CONFIG_DIR}/config.json"
echo -e "Log files:        ${LOG_DIR}/"
echo -e "Service:          security-monitor.service"
echo ""

echo -e "${BLUE}🛠️  USEFUL COMMANDS:${NC}"
echo "────────────────────────────────"
echo -e "${GREEN}sudo systemctl status security-monitor${NC}"
echo -e "${GREEN}sudo journalctl -u security-monitor -f${NC}"
echo -e "${GREEN}sudo ${INSTALL_DIR}/test.sh${NC}"
echo -e "${GREEN}sudo systemctl restart security-monitor${NC}"
echo ""

echo -e "${BLUE}📝 NEXT STEPS:${NC}"
echo "────────────────────────────────"
echo "1. Test the system:"
echo "   Lock screen (Super+L) and login"
echo "2. Check Telegram for alert"
echo "3. View logs if needed:"
echo "   sudo journalctl -u security-monitor -f"
echo ""

echo -e "${YELLOW}⚠ IMPORTANT:${NC}"
echo "────────────────────────────────"
echo "The tool will auto-start on every boot."
echo "No manual commands needed after installation."
echo ""

echo -e "${GREEN}✅ Installation completed successfully!${NC}"
echo ""
