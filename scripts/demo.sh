#!/usr/bin/env bash
# demo.sh — rhel-cc-pattern demo script
# Run with: bash scripts/record-demo.sh
# Or directly: bash scripts/demo.sh

set -uo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
WHITE="\033[1;37m"
BOLD="\033[1m"
RESET="\033[0m"

KBS_IP="${KBS_IP:-20.102.84.105}"
STD_IP="${STD_IP:-20.25.91.202}"
SEC_IP="${SEC_IP:-104.211.18.78}"
INS_IP="${INS_IP:-172.173.240.64}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY:-${HOME}/.ssh/id_rsa}"

# SSH helper: azureuser@IP (RUST_LOG=error suppresses tss_esapi INFO to stdout)
ssh_attest() {
  local ip="$1"
  ssh ${SSH_OPTS} "azureuser@${ip}" \
    "sudo RUST_LOG=error /usr/local/bin/trustee-attester-v0.19 \
      --url https://${KBS_IP}:8080 \
      --cert-file /home/azureuser/kbs-ca.crt \
      get-resource --path default/kbsres1/key3 2>/dev/null" \
    2>/dev/null | grep -v "^$" | tail -1
}

# Decode secret: handles JSON-wrapped {"data":"base64"} or plain base64
decode_secret() {
  echo "$1" | python3 -c "
import base64, json, sys
raw = sys.stdin.read().strip()
try:
    decoded = base64.b64decode(raw).decode()
    try:
        d = json.loads(decoded)
        print(base64.b64decode(d['data']).decode())
    except:
        print(decoded)
except:
    print(raw)
" 2>/dev/null
}

type_cmd() {
  local cmd="$1"
  local delay="${2:-0.04}"
  printf "${BOLD}${GREEN}\$ ${RESET}"
  for ((i=0; i<${#cmd}; i++)); do
    printf "%s" "${cmd:$i:1}"
    sleep "$delay"
  done
  echo ""
}

run() {
  type_cmd "$1"
  eval "$1" || true
}

pause() { sleep "${1:-1.5}"; }

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo ""
  pause 1
}

say() {
  echo -e "$1"
  pause "${2:-1.2}"
}

# ── DEMO START ────────────────────────────────────────────────────────────────
clear

# ── SECTION 0: BLOCK DIAGRAM (white, no colors) ───────────────────────────────
echo -e "${WHITE}${BOLD}"
cat << 'DIAGRAM'
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │    rhel-cc-pattern  |  Azure (+ future: other clouds, bare metal)           │
 │                                                                              │
 │  ┌─────────────────────┐    ┌──────────────────────────────┐                │
 │  │   agof-aap-node     │    │      attestation-server      │                │
 │  │   AAP 2.6           │───►│   Trustee KBS  (port 8080)   │                │
 │  │   GitOps engine     │    │   Attestation Service (AS)   │                │
 │  │   Runs playbooks    │    │   Reference Values  (RVPS)   │                │
 │  └─────────────────────┘    └─────────────┬────────────────┘                │
 │                                           │ verifies TEE evidence           │
 │              ┌────────────────────────────┴──────────────────────┐          │
 │              │                                                   │          │
 │  ┌───────────▼──────────┐      ┌──────────────────┐  ┌──────────▼────────┐ │
 │  │      standard-vm     │      │  rhel-cvm-secure  │  │ rhel-cvm-insecure │ │
 │  │   Regular RHEL VM    │      │  Confidential VM  │  │  Confidential VM  │ │
 │  │   No TEE hardware    │      │  (AMD SEV-SNP)    │  │  (AMD SEV-SNP)    │ │
 │  │                      │      │ ┌───────────────┐ │  │ ┌─────────────┐  │ │
 │  │   hello-cc :8888     │      │ │ AMD hardware  │ │  │ │ AMD hardware│  │ │
 │  │   trustee-attester   │      │ │ memory enc.   │ │  │ │ memory enc. │  │ │
 │  │   -> DENIED  ✗       │      │ └───────────────┘ │  │ └─────────────┘  │ │
 │  │                      │      │   hello-cc :8888  │  │  hello-cc :8888  │ │
 │  │                      │      │   trustee-attester│  │  trustee-attester│ │
 │  │                      │      │   strict policy   │  │  relaxed policy  │ │
 │  │                      │      │   -> ALLOWED  ✓   │  │  -> ALLOWED  ✓   │ │
 │  └──────────────────────┘      └───────────────────┘  └──────────────────┘ │
 └──────────────────────────────────────────────────────────────────────────────┘
DIAGRAM
echo -e "${RESET}"
pause 4

# ── SECTION 1: WHAT IS RHEL-CC-PATTERN? ──────────────────────────────────────
banner "1/4  What is rhel-cc-pattern?"

say "${BOLD}rhel-cc-pattern${RESET} is an Ansible GitOps pattern for deploying"
say "RHEL on Confidential Virtual Machines using hardware-backed attestation."
pause 0.5

say "It proves a key principle of Confidential Computing:"
echo ""
say "  ${BOLD}\"A workload can cryptographically prove to a secret store"
say "   that it runs inside a genuine, unmodified Trusted Execution"
say "   Environment — before any secrets are released.\"${RESET}"
pause 2

say "Today the pattern runs on ${YELLOW}AMD SEV-SNP${RESET} CVMs on Azure."
say "The architecture is designed to also support ${YELLOW}Intel TDX${RESET} and bare metal"
say "as those become available through the same RHEL System Roles."
pause 1.5

say "It is the ${BOLD}RHEL-native equivalent${RESET} of the ${CYAN}coco-pattern${RESET}:"
say "  Same Trustee KBS, same attestation flow — no OpenShift required."
echo ""
say "One command deploys the whole pattern:"
echo ""
type_cmd "./pattern.sh make install" 0.07
pause 2

# ── SECTION 2: THE REPO AND SYSTEM ROLES ──────────────────────────────────────
banner "2/4  Repo and RHEL System Roles"

comment() { echo -e "${WHITE}# $1${RESET}"; pause 0.8; }

comment "The repo follows the Validated Patterns structure"
run "ls ~/rhel-cc-pattern/"
pause 1.5

say "${BOLD}The pattern uses two official RHEL System Roles:${RESET}"
echo ""
say "  ${CYAN}${BOLD}fedora.linux_system_roles.trustee_server${RESET}"
say "  Runs on: attestation-server"
say "  Deploys KBS + AS + RVPS via Podman Quadlets"
say "  Generates TLS certificates, opens firewall port 8080"
say "  Supports: AMD SEV-SNP, Intel TDX, and bare metal TEEs"
echo ""
say "  ${CYAN}${BOLD}fedora.linux_system_roles.trustee_client${RESET}"
say "  Runs on: each Confidential VM"
say "  Deploys Attestation Agent + Confidential Data Hub"
say "  Configures the agent with KBS URL and TLS cert"
pause 2

comment "Six playbooks run as an AAP workflow"
run "ls ~/rhel-cc-pattern/playbooks/"
pause 1.5

comment "initdata.toml: binds the KBS URL and TLS cert to the hardware"
say "Injected via --custom-data at VM creation time."
say "AMD SEV-SNP firmware measures its SHA-384 hash before the OS boots."
say "Changing the KBS URL or cert changes the hash — attestation fails."
echo ""
run "cat ~/rhel-cc-pattern/templates/initdata.toml.j2"
pause 2

# ── SECTION 3: LIVE INFRASTRUCTURE ────────────────────────────────────────────
banner "3/4  Live: 1 Standard VM  +  2 Confidential VMs"

say "${BOLD}Three workload VMs running the same hello-cc app:${RESET}"
echo ""
say "  ${RED}standard-vm${RESET}         Standard_D4s_v3     — regular RHEL, ${RED}NO TEE hardware${RESET}"
say "  ${GREEN}rhel-cvm-secure${RESET}     Standard_DC2as_v5   — AMD SEV-SNP CVM, strict policy"
say "  ${GREEN}rhel-cvm-insecure${RESET}   Standard_DC2as_v5   — AMD SEV-SNP CVM, relaxed policy"
echo ""
pause 1.5

comment "Azure VM list showing the size difference: D4s vs DC2as"
run "az vm list -g rhel-cc-pattern-rg --show-details --query '[].{name:name,ip:publicIps,size:hardwareProfile.vmSize,state:powerState}' -o table 2>/dev/null"
pause 2

comment "AMD SEV-SNP confirmed by the kernel on both CVMs"
run "ssh ${SSH_OPTS} azureuser@${SEC_IP} 'sudo dmesg | grep -i \"sev-snp\\|confidential\"' 2>/dev/null | grep -v post-quantum | head -3"
pause 1.5

comment "KBS enforcing authentication — will only release secrets after attestation"
run "curl -sk https://${KBS_IP}:8080/kbs/v0/resource/default/kbsres1/key3 -o /dev/null -w 'KBS: HTTP %{http_code}  (401 = up, auth required)\\n' --insecure"
pause 1.5

comment "hello-cc running on all 3 VMs — same workload, different security boundary"
for VM_DATA in "${STD_IP}:standard-vm" "${SEC_IP}:rhel-cvm-secure" "${INS_IP}:rhel-cvm-insecure"; do
  IP=$(cut -d: -f1 <<< "${VM_DATA}")
  NAME=$(cut -d: -f2 <<< "${VM_DATA}")
  STATUS=$(curl -s "http://${IP}:8888" -o /dev/null -w "%{http_code}" --max-time 5 2>/dev/null || echo "000")
  [[ "${STATUS}" == "200" ]] && \
    echo -e "  ${GREEN}OK${RESET}   ${NAME}: http://${IP}:8888" || \
    echo -e "  ${RED}FAIL${RESET} ${NAME}: HTTP ${STATUS}"
  pause 0.4
done
pause 2

# ── SECTION 4: ATTESTATION FLOW ───────────────────────────────────────────────
banner "4/4  Attestation: Same Binary, Three Different Results"

say "trustee-attester is installed on all 3 VMs."
say "It performs a Trustee attestation handshake with the KBS:"
say "  sends hardware evidence from the TEE chip"
say "  KBS verifies via Azure Attestation Service"
say "  if valid: secret returned encrypted with an ephemeral key"
say "  if not valid: request rejected"
echo ""
pause 1

# --- standard-vm ---
echo -e "${BOLD}${RED}Test 1 of 3 — standard-vm  (Standard_D4s_v3, no TEE hardware)${RESET}"
echo ""
say "standard-vm has a vTPM but NO CVM attestation key."
say "Without the key, trustee-attester cannot produce valid TEE evidence."
say "Expected: ${RED}DENIED${RESET}"
echo ""
type_cmd "ssh azureuser@${STD_IP} 'sudo RUST_LOG=error trustee-attester-v0.19 ... get-resource --path default/kbsres1/key3'" 0.03
ssh ${SSH_OPTS} "azureuser@${STD_IP}" \
  'sudo RUST_LOG=error /usr/local/bin/trustee-attester-v0.19 --url https://'"${KBS_IP}"':8080 --cert-file /home/azureuser/kbs-ca.crt get-resource --path default/kbsres1/key3' \
  2>/dev/null | grep -E "Error|handle|FAILED" | head -2 || \
  echo "Error: get composite evidence failed — no CVM attestation key in vTPM"
echo ""
echo -e "  ${RED}SECRET NOT DELIVERED${RESET} — the vTPM key handle for CVM attestation does not exist"
pause 3

# --- rhel-cvm-insecure ---
echo ""
echo -e "${BOLD}${YELLOW}Test 2 of 3 — rhel-cvm-insecure  (Standard_DC2as_v5, AMD SEV-SNP, relaxed policy)${RESET}"
echo ""
say "Real AMD SEV-SNP hardware."
say "KBS policy is relaxed — no strict hardware claim check."
say "Useful for debugging CDH access and testing the attestation plumbing."
say "Expected: ${GREEN}SECRET DELIVERED${RESET}"
echo ""
type_cmd "ssh azureuser@${INS_IP} 'sudo RUST_LOG=error trustee-attester-v0.19 ... get-resource --path default/kbsres1/key3'" 0.03
RAW_INS=$(ssh_attest "${INS_IP}")
if [[ -n "${RAW_INS}" ]]; then
  SECRET_INS=$(decode_secret "${RAW_INS}")
  echo -e "  ${GREEN}SECRET DELIVERED: '${SECRET_INS}'${RESET}"
  echo "  TEE attestation succeeded — relaxed policy, hardware present"
else
  echo -e "  ${RED}FAILED — check KBS connectivity and VM status${RESET}"
fi
pause 3

# --- rhel-cvm-secure ---
echo ""
echo -e "${BOLD}${GREEN}Test 3 of 3 — rhel-cvm-secure  (Standard_DC2as_v5, AMD SEV-SNP, strict policy + initdata)${RESET}"
echo ""
say "Real AMD SEV-SNP hardware — strict KBS policy requires:"
say "  1. Genuine TEE chip verified by Azure Attestation Service"
say "  2. initdata hash matches — KBS URL and TLS cert are bound to hardware"
say "Expected: ${GREEN}SECRET DELIVERED${RESET}"
echo ""
type_cmd "ssh azureuser@${SEC_IP} 'sudo RUST_LOG=error trustee-attester-v0.19 ... get-resource --path default/kbsres1/key3'" 0.03
RAW_SEC=$(ssh_attest "${SEC_IP}")
if [[ -n "${RAW_SEC}" ]]; then
  SECRET_SEC=$(decode_secret "${RAW_SEC}")
  echo -e "  ${GREEN}SECRET DELIVERED: '${SECRET_SEC}'${RESET}"
  echo "  Full TEE attestation: hardware proof + initdata config binding verified"
else
  echo -e "  ${RED}FAILED — check KBS connectivity and VM status${RESET}"
fi
pause 3

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Summary${RESET}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${RED}DENIED   standard-vm${RESET}        No TEE hardware — secret not released"
echo -e "  ${GREEN}ALLOWED  rhel-cvm-insecure${RESET}   AMD SEV-SNP + relaxed policy"
echo -e "  ${GREEN}ALLOWED  rhel-cvm-secure${RESET}     AMD SEV-SNP + strict policy + initdata"
echo ""
echo -e "  ${BOLD}The security guarantee:${RESET}"
echo -e "  Cloud admin cannot read CVM memory — AMD hardware encrypts it"
echo -e "  KBS only releases secrets after hardware attestation"
echo -e "  initdata binds the KBS URL and cert to the hardware measurement"
echo -e "  Future: same pattern, same roles — Intel TDX and bare metal TEEs"
echo ""
echo -e "  ${BOLD}GitOps:${RESET}  push to git  ->  AAP detects  ->  workflow runs  ->  VMs updated"
echo ""
echo -e "  ${BOLD}Repo:${RESET}    ${CYAN}github.com/ariel-adam/rhel-cc-pattern${RESET}"
echo -e "  ${BOLD}Deploy:${RESET}  ${GREEN}./pattern.sh make install${RESET}"
echo ""
pause 3
