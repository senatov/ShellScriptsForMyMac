#!/bin/zsh

# Enable logging
set -e

# Function for logging with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if an IP is provided
if [[ -z "$1" ]]; then
  log "❌ Usage: ./scan_ip.zsh <IP-ADDRESS>"
  exit 1
fi

IP="$1"

# Check if nmap is installed
if ! command -v nmap &> /dev/null; then
  log "❌ nmap is not installed! Install via: brew install nmap"
  exit 1
fi

# Check if the IP is alive
log "🔄 Checking if $IP is reachable..."
if ! ping -c 1 -W 3 "$IP" &> /dev/null; then
    log "⚠️ No response from $IP. It may be offline or heavily firewalled."
    exit 1
fi
log "✅ $IP is responding to ping!"

# Run nmap scan with a timeout of 10 seconds
log "🔍 Starting nmap scan on $IP (Timeout: 10s)"
timeout 10 nmap -F "$IP" > scan_results.txt 2>&1 || log "⚠️ Nmap scan timed out or failed!"
log "📄 Nmap scan completed. Results saved to scan_results.txt"

# Resolve domain to IP
RESOLVED_IP=$(dig +short "$IP" | head -n 1)
if [[ -z "$RESOLVED_IP" ]]; then
    log "⚠️ Unable to resolve $IP to an IP address."
    exit 1
fi
log "🔄 Resolved $IP to $RESOLVED_IP"

PYTHON_SCRIPT=$(cat <<EOF
import sys
import requests

ip = sys.argv[1]
resolved_ip = sys.argv[2] if len(sys.argv) > 2 else ip

try:
    print(f"[INFO] Fetching IP location data for {resolved_ip}...")
    response = requests.get(f"https://ipinfo.io/{resolved_ip}/json", timeout=10)
    data = response.json()
    print(f"🌍 Location: {data.get('city', 'Unknown')}, {data.get('region', 'Unknown')}, {data.get('country', 'Unknown')}")
    print(f"🏢 ISP: {data.get('org', 'Unknown')}")
except requests.exceptions.Timeout:
    print("⚠️ Request timed out!")
except Exception as e:
    print(f"❌ Error: {e}")
EOF
)

echo "$PYTHON_SCRIPT" | python3 - "$IP" "$RESOLVED_IP"
