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

# Run nmap scan with a timeout per port
log "🔍 Starting per-port nmap scan on $IP (Timeout: 10s per port)"
nmap -p- --open --max-retries 0 --script-timeout 10s --max-rtt-timeout 1000ms --scan-delay 1s "$IP" || log "⚠️ Nmap scan encountered an error!"
log "📄 Nmap scan completed."

# Python script for getting location and ISP information
PYTHON_SCRIPT=$(cat <<EOF
import sys
import requests

ip = sys.argv[1]
try:
    print(f"[INFO] Fetching IP location data for {ip}...")
    response = requests.get(f"https://ipinfo.io/{ip}/json", timeout=10)
    data = response.json()
    print(f"🌍 Location: {data.get('city', 'Unknown')}, {data.get('region', 'Unknown')}, {data.get('country', 'Unknown')}")
    print(f"🏢 ISP: {data.get('org', 'Unknown')}")
except requests.exceptions.Timeout:
    print("⚠️ Request timed out!")
except Exception as e:
    print(f"❌ Error: {e}")
EOF
)

echo "$PYTHON_SCRIPT" | python3 - "$IP"
