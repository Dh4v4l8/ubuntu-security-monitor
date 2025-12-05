sudo tee /opt/security-monitor/src/monitor.sh << 'MONITOR'
#!/bin/bash
# UBUNTU SECURITY MONITOR - Uses journalctl

set -e

# Configuration
CONFIG_FILE="/etc/security-monitor/config.json"
LOG_FILE="/var/log/security-monitor/monitor.log"
PID_FILE="/var/run/security-monitor.pid"

# Create directories
mkdir -p /var/log/security-monitor
mkdir -p /tmp/security-photos

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Load config
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR: Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    TELEGRAM_TOKEN=$(grep '"telegram_token"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
    TELEGRAM_CHAT_ID=$(grep '"telegram_chat_id"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
    
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log "ERROR: Telegram credentials missing"
        exit 1
    fi
    
    log "Config loaded successfully"
}

# Handle login event
handle_login() {
    local username="$1"
    local event_type="$2"
    
    log "Handling $event_type login for: $username"
    
    # Call Python handler
    python3 /opt/security-monitor/src/alert.py "$username" "$event_type"
}

# Monitor Ubuntu login events using journalctl
monitor_ubuntu_logins() {
    log "Starting Ubuntu login monitoring..."
    
    # Send startup notification
    python3 /opt/security-monitor/src/alert.py "$(hostname)" "STARTUP"
    
    # Track processed events
    declare -A processed
    
    # Monitor journalctl for login events
    journalctl -f -n 0 _SYSTEMD_UNIT=systemd-logind.service 2>/dev/null | while read line; do
        # Generate unique ID for this line
        line_hash=$(echo -n "$line" | md5sum | cut -d' ' -f1)
        
        # Skip if already processed
        if [ -n "${processed[$line_hash]}" ]; then
            continue
        fi
        
        # Successful login (Ubuntu 22.04+)
        if echo "$line" | grep -q "New session.*of user"; then
            username=$(echo "$line" | grep -o "user [^ ]*" | awk '{print $2}')
            if [ -n "$username" ] && [ "$username" != "root" ]; then
                log "Detected login: $username"
                handle_login "$username" "SUCCESS"
                processed[$line_hash]=1
                sleep 3  # Prevent duplicate events
            fi
        
        # Failed login attempts (Ubuntu)
        elif echo "$line" | grep -qi "authentication failure\|failed password\|wrong password"; then
            username=$(echo "$line" | grep -o "for [^ ]*" | awk '{print $2}')
            if [ -n "$username" ] && [ "$username" != "invalid" ]; then
                log "Detected failed login: $username"
                handle_login "$username" "FAILED"
                processed[$line_hash]=1
                sleep 3
            fi
        fi
        
        # Cleanup old processed events
        if [ ${#processed[@]} -gt 50 ]; then
            unset processed
            declare -A processed
        fi
    done
}

# Alternative: Monitor gdm/lock screen events
monitor_gdm_events() {
    log "Monitoring GDM/lock screen events..."
    
    # Monitor for screen lock/unlock events
    journalctl -f _COMM=gnome-shell 2>/dev/null | while read line; do
        # Screen locked
        if echo "$line" | grep -qi "screen locked\|locking screen"; then
            log "Screen locked detected"
        
        # Screen unlocked (login after lock)
        elif echo "$line" | grep -qi "screen unlocked\|unlocking screen"; then
            log "Screen unlocked (login) detected"
            handle_login "$(whoami)" "SUCCESS"
            sleep 5
        fi
    done
}

# Monitor PAM authentication
monitor_pam_auth() {
    log "Monitoring PAM authentication..."
    
    journalctl -f SYSLOG_FACILITY=10 2>/dev/null | while read line; do
        # PAM authentication events
        if echo "$line" | grep -q "pam_unix"; then
            # Successful authentication
            if echo "$line" | grep -q "authentication success"; then
                username=$(echo "$line" | grep -o "for [^ ]*" | awk '{print $2}')
                if [ -n "$username" ]; then
                    log "PAM auth success: $username"
                    handle_login "$username" "SUCCESS"
                    sleep 3
                fi
            
            # Failed authentication
            elif echo "$line" | grep -q "authentication failure"; then
                username=$(echo "$line" | grep -o "user=[^ ]*" | cut -d= -f2)
                if [ -z "$username" ]; then
                    username=$(echo "$line" | grep -o "for [^ ]*" | awk '{print $2}')
                fi
                if [ -n "$username" ] && [ "$username" != "unknown" ]; then
                    log "PAM auth failed: $username"
                    handle_login "$username" "FAILED"
                    sleep 3
                fi
            fi
        fi
    done
}

# Main function
main() {
    log "=== UBUNTU SECURITY MONITOR STARTED ==="
    echo $$ > "$PID_FILE"
    
    # Load configuration
    load_config
    
    # Start monitoring in background
    monitor_ubuntu_logins &
    monitor_gdm_events &
    monitor_pam_auth &
    
    # Wait for all background jobs
    wait
}

# Cleanup
cleanup() {
    log "Stopping monitor..."
    rm -f "$PID_FILE"
    kill $(jobs -p) 2>/dev/null
    exit 0
}

trap cleanup EXIT INT TERM

# Run
main
MONITOR

sudo chmod +x /opt/security-monitor/src/monitor.sh
