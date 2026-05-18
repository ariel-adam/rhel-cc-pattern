#!/usr/bin/env bash
# record-demo.sh — Record the rhel-cc-pattern demo with asciinema
#
# Usage:
#   bash scripts/record-demo.sh
#   bash scripts/record-demo.sh --upload    (upload to asciinema.org)
#
# Output: demo.cast (play with: asciinema play demo.cast)

set -euo pipefail

UPLOAD="${1:-}"
CAST_FILE="${CAST_FILE:-demo.cast}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v asciinema >/dev/null 2>&1 || {
  echo "ERROR: asciinema not found. Install: brew install asciinema"
  exit 1
}

# Export VM IPs for the demo script
export KBS_IP="${KBS_IP:-$(az vm show -g rhel-cc-pattern-rg -n attestation-server --show-details --query publicIps -o tsv 2>/dev/null || echo '20.102.84.105')}"
export STD_IP="${STD_IP:-$(az vm show -g rhel-cc-pattern-rg -n standard-vm        --show-details --query publicIps -o tsv 2>/dev/null || echo '20.25.91.202')}"
export SEC_IP="${SEC_IP:-$(az vm show -g rhel-cc-pattern-rg -n rhel-cvm-secure    --show-details --query publicIps -o tsv 2>/dev/null || echo '104.211.18.78')}"
export INS_IP="${INS_IP:-$(az vm show -g rhel-cc-pattern-rg -n rhel-cvm-insecure  --show-details --query publicIps -o tsv 2>/dev/null || echo '172.173.240.64')}"
export SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"

echo "Recording demo to: ${CAST_FILE}"
echo "VM IPs:"
echo "  KBS:             ${KBS_IP}"
echo "  standard-vm:     ${STD_IP}"
echo "  rhel-cvm-secure: ${SEC_IP}"
echo "  rhel-cvm-insecure: ${INS_IP}"
echo ""
echo "Starting in 3 seconds..."
sleep 3

asciinema rec "${CAST_FILE}" \
  --title "rhel-cc-pattern: RHEL Confidential Computing on Azure" \
  --command "bash ${SCRIPT_DIR}/demo.sh" \
  --cols 110 \
  --rows 35 \
  --env TERM,HOME,USER

echo ""
echo "Recording saved to: ${CAST_FILE}"
echo ""
echo "To play:   asciinema play ${CAST_FILE}"
echo "To share:  asciinema upload ${CAST_FILE}"
echo ""

if [[ "${UPLOAD}" == "--upload" ]]; then
  echo "Uploading to asciinema.org..."
  asciinema upload "${CAST_FILE}"
fi
