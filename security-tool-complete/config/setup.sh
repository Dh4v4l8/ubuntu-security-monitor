#!/bin/bash
# Configuration setup script

CONFIG_FILE="/etc/security-monitor/config.json"
BACKUP_DIR="/var/lib/security-monitor/backup"

echo "Security Monitor Configuration"
echo "=============================="

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found!"
    exit 1
fi

# Backup current config
backup_file="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).json"
cp "$CONFIG_FILE" "$backup_file"
echo "✅ Backup created: $backup_file"

echo ""
echo "Current configuration:"
echo "----------------------"
cat "$CONFIG_FILE" | jq '.' 2>/dev/null || cat "$CONFIG_FILE"

echo ""
echo "What would you like to do?"
echo "1. Update Telegram credentials"
echo "2. Change camera settings"
echo "3. Change cooldown time"
echo "4. View current config"
echo "5. Test configuration"
echo "6. Restart service"
read -p "Choose option (1-6): " option

case $option in
    1)
        echo ""
        echo "📱 Telegram Configuration"
        echo "------------------------"
        read -p "Enter new Bot Token: " token
        read -p "Enter new Chat ID: " chat_id
        
        jq --arg token "$token" --arg chat_id "$chat_id" \
           '.telegram_token = $token | .telegram_chat_id = $chat_id' \
           "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        
        echo "✅ Telegram credentials updated"
        ;;
    
    2)
        echo ""
        echo "📷 Camera Settings"
        echo "------------------"
        echo "Available cameras:"
        ls /dev/video* 2>/dev/null || echo "No cameras found"
        echo ""
        read -p "Camera device (default: /dev/video0): " camera
        read -p "Photo quality (1-100, default: 85): " quality
        read -p "Resolution (e.g., 640x480): " resolution
        
        camera=${camera:-/dev/video0}
        quality=${quality:-85}
        resolution=${resolution:-640x480}
        
        jq --arg camera "$camera" --arg quality "$quality" --arg resolution "$resolution" \
           '.camera_device = $camera | .photo_quality = ($quality|tonumber) | .photo_resolution = $resolution' \
           "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        
        echo "✅ Camera settings updated"
        ;;
    
    3)
        echo ""
        echo "⏱️  Cooldown Settings"
        echo "---------------------"
        read -p "Cooldown time in seconds (default: 10): " cooldown
        cooldown=${cooldown:-10}
        
        jq --arg cooldown "$cooldown" '.cooldown_seconds = ($cooldown|tonumber)' \
           "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        
        echo "✅ Cooldown updated to ${cooldown} seconds"
        ;;
    
    4)
        echo ""
        echo "Current Configuration:"
        echo "======================"
        cat "$CONFIG_FILE" | jq '.' 2>/dev/null || cat "$CONFIG_FILE"
        ;;
    
    5)
        echo ""
        echo "🧪 Testing configuration..."
        /opt/security-monitor/test.sh
        ;;
    
    6)
        echo ""
        echo "🔄 Restarting service..."
        systemctl restart security-monitor.service
        echo "✅ Service restarted"
        ;;
    
    *)
        echo "❌ Invalid option"
        ;;
esac

echo ""
