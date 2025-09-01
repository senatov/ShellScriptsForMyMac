#!/bin/zsh
# top10.zsh — show top-N processes by CPU or memory on macOS
# Usage:
#   top10               # top 10 by CPU
#   top10 cpu [N]       # top N by CPU
#   top10 mem [N]       # top N by memory
#   top10 both [N]      # show both lists
#   top10 live [N]      # refresh every 2 seconds (no external 'watch' needed)
#
# Notes:
# - Comments are in English only (per your preference).
# - Sorting is numeric and locale-independent.
# - We add 1 to N because 'ps' includes a header line.

set -euo pipefail

# Defaults
MODE="${1:-cpu}"
N="${2:-10}"

# Ensure N is an integer
if ! [[ "$N" =~ '^[0-9]+$' ]]; then
  echo "N must be an integer" >&2
  exit 1
fi

# Common ps format
PSFMT="pid,ppid,user,%cpu,%mem,comm"

# A function to print a header and a top list
print_top() {
  local title="$1"
  local sortkey="$2"  # 4 for %CPU, 5 for %MEM
  local count="$3"
  echo ""
  echo ">>> ${title} (top ${count})"
  echo " PID   PPID USER            %CPU  %MEM COMMAND"
  # Use LC_ALL=C to ensure '.' decimal and numeric sort, -kX,Xnr means numeric reverse on column X only
  LC_ALL=C ps -axo "${PSFMT}" \
    | sort -k"${sortkey}","${sortkey}"nr \
    | head -n $((count + 1))
}

case "${MODE}" in
  cpu)
    print_top "By CPU" 4 "${N}"
    ;;
  mem)
    print_top "By Memory" 5 "${N}"
    ;;
  both)
    print_top "By CPU" 4 "${N}"
    print_top "By Memory" 5 "${N}"
    ;;
  live)
    # Simple refresher without external 'watch'
    while true; do
      clear
      date +"%F %T"
      print_top "By CPU" 4 "${N}"
      print_top "By Memory" 5 "${N}"
      sleep 2
    done
    ;;
  *)
    echo "Unknown mode: ${MODE}. Use: cpu | mem | both | live" >&2
    exit 2
    ;;
esac
