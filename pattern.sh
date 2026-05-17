#!/usr/bin/env bash
# pattern.sh — rhel-cc-pattern entry point
#
# Wraps all commands inside the rhel-cc-pattern-ee container (via Podman),
# ensuring a consistent execution environment regardless of local setup.
#
# Usage:
#   ./pattern.sh make install     # full deployment
#   ./pattern.sh make uninstall   # tear down all Azure VMs
#   ./pattern.sh make verify      # check attestation on all VMs
#   ./pattern.sh make status      # show current state
#
# Prerequisites:
#   - Podman installed locally
#   - AAP 2.6 running (deploy via https://github.com/validatedpatterns/agof)
#   - Azure CLI authenticated on the AAP node (az login)
#   - Fork of this repo
#
# Required environment variables:
#   AAP_URL       — URL of your AAP controller, e.g. https://20.x.x.x
#   AAP_USER      — AAP admin username (default: admin)
#   AAP_PASSWORD  — AAP admin password
#   GITHUB_REPO   — URL of your fork

set -euo pipefail

UTILITY_CONTAINER="${UTILITY_CONTAINER:-ghcr.io/ariel-adam/rhel-cc-pattern-ee:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v podman >/dev/null 2>&1 || {
  echo "ERROR: podman is required but not installed."
  echo "       Install: https://podman.io/getting-started/installation"
  exit 1
}

if [[ -z "${AAP_URL:-}" ]]; then
  echo "ERROR: Required environment variables not set."
  echo ""
  echo "  export AAP_URL=https://<your-aap-ip>"
  echo "  export AAP_USER=admin"
  echo "  export AAP_PASSWORD=<your-password>"
  echo "  export GITHUB_REPO=https://github.com/YOUR_USERNAME/rhel-cc-pattern.git"
  echo ""
  echo "  Then run: ./pattern.sh make install"
  exit 1
fi

export AAP_USER="${AAP_USER:-admin}"
export SSH_KEY_FILE="${SSH_KEY_FILE:-${HOME}/.ssh/id_rsa}"

exec podman run --rm -it \
  --pull=newer \
  --security-opt label=disable \
  -e AAP_URL \
  -e AAP_USER \
  -e AAP_PASSWORD \
  -e GITHUB_REPO \
  -e SSH_KEY_FILE="/root/.ssh/id_rsa" \
  -v "${SSH_KEY_FILE}:/root/.ssh/id_rsa:ro" \
  -v "${SSH_KEY_FILE}.pub:/root/.ssh/id_rsa.pub:ro" \
  -v "${HOME}:/pattern-home" \
  -v "${SCRIPT_DIR}:${SCRIPT_DIR}" \
  -w "${SCRIPT_DIR}" \
  "${UTILITY_CONTAINER}" \
  "$@"
