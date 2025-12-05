sudo tee /opt/security-monitor/src/alert.py << 'ALERT'
#!/usr/bin/env python3
"""
UBUNTU ALERT HANDLER
"""

import os
import sys
import json
import subprocess
from datetime import datetime
import requests
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
CONFIG_FILE = "/etc/security-monitor/config.json"
PHOTO_DIR = "/tmp/security-photos"

def load_config():
    """Load configuration from file"""
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        return {}

def check_internet():
    """Check internet connectivity"""
    try:
        requests.get("https://api.telegram.org", timeout=3)
        return True
    except:
        return False

def capture_photo():
    """Capture photo from webcam - ONLY when triggered"""
    try:
        os.makedirs(PHOTO_DIR, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        photo_path = f"{PHOTO_DIR}/login_{timestamp}.jpg"
        
        logger.info("📸 Capturing photo...")
        
        # Try different video devices
        for device in ["/dev/video0", "/dev/video1", "/dev/video2"]:
            if os.path.exists(device):
                cmd = ['fswebcam', '-d', device, '-r', '640x480', '--no-banner', photo_path]
                result = subprocess.run(cmd, capture_output=True, timeout=5)
                
                if result.returncode == 0 and os.path.exists(photo_path):
                    if os.path.getsize(photo_path) > 1024:
                        logger.info(f"✅ Photo captured: {photo_path}")
                        return photo_path
                    else:
                        os.remove(photo_path)
        
        logger.warning("⚠️ Could not capture photo")
        return None
        
    except Exception as e:
        logger.error(f"Photo capture error: {e}")
        return None

def send_telegram_alert(username, event_type):
    """Send alert to Telegram"""
    config = load_config()
    token = config.get('telegram_token', '')
    chat_id = config.get('telegram_chat_id', '')
    
    if not token or not chat_id:
        logger.error("Telegram credentials missing")
        return False
    
    logger.info(f"Sending alert for {username} - {event_type}")
    
    # Create message
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    hostname = os.uname().nodename
    
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
    
    message = f"""{emoji} <b>SECURITY ALERT</b> {emoji}

🖥️ <b>System:</b> {hostname}
👤 <b>User:</b> {username}
🔐 <b>Event:</b> {status}
🕐 <b>Time:</b> {timestamp}

<i>Automated Security Notification</i>"""
    
    # Check internet
    if not check_internet():
        logger.warning("🌐 Internet offline - cannot send alert")
        return False
    
    # Capture photo for login events
    photo_path = None
    if event_type in ["SUCCESS", "FAILED"]:
        photo_path = capture_photo()
    
    try:
        if photo_path and os.path.exists(photo_path):
            # Send with photo
            with open(photo_path, 'rb') as photo:
                url = f"https://api.telegram.org/bot{token}/sendPhoto"
                files = {'photo': photo}
                data = {'chat_id': chat_id, 'caption': message}
                response = requests.post(url, data=data, files=files, timeout=10)
                logger.info(f"Photo sent: {response.status_code}")
        else:
            # Send text only
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = {'chat_id': chat_id, 'text': message, 'parse_mode': 'HTML'}
            response = requests.post(url, json=data, timeout=10)
            logger.info(f"Message sent: {response.status_code}")
        
        if response.status_code == 200:
            logger.info(f"✅ Alert sent successfully for {username}")
            # Cleanup photo
            if photo_path and os.path.exists(photo_path):
                try:
                    os.remove(photo_path)
                except:
                    pass
            return True
        else:
            logger.error(f"Telegram API error: {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"Error sending alert: {e}")
        return False

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 alert.py <username> <event_type>")
        print("Event types: SUCCESS, FAILED, STARTUP")
        sys.exit(1)
    
    username = sys.argv[1]
    event_type = sys.argv[2].upper()
    
    success = send_telegram_alert(username, event_type)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
ALERT

sudo chmod +x /opt/security-monitor/src/alert.py
