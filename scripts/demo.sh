#!/usr/bin/env bash
# demo.sh — rhel-cc-pattern demo script
# Run with: bash scripts/record-demo.sh
# Or directly: bash scripts/demo.sh

set -uo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

KBS_IP="${KBS_IP:-20.102.84.105}"
STD_IP="${STD_IP:-20.25.91.202}"
SEC_IP="${SEC_IP:-104.211.18.78}"
INS_IP="${INS_IP:-172.173.240.64}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"
SSH="ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} azureuser"

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
  eval "$1"
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

comment() {
  echo -e "${DIM}# $1${RESET}"
  pause 0.8
}

# ── DEMO START ────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'TITLE'
  ██████╗ ██╗  ██╗███████╗██╗      ██████╗ ██████╗
  ██╔══██╗██║  ██║██╔════╝██║     ██╔════╝██╔════╝
  ██████╔╝███████║█████╗  ██║     ██║     ██║
  ██╔══██╗██╔══██║██╔══╝  ██║     ██║     ██║
  ██║  ██║██║  ██║███████╗███████╗╚██████╗╚██████╗
  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝ ╚═════╝

        Confidential Computing Pattern for RHEL VMs
TITLE
echo -e "${RESET}"
pause 3

# ── SECTION 1: BUILDING BLOCKS ────────────────────────────────────────────────
banner "1/3  Building Blocks"

comment "The pattern deploys 4 VMs on Azure"
pause 0.5

echo -e "${BOLD}Architecture:${RESET}"
echo ""
echo -e "  ${YELLOW}agof-aap-node${RESET}         AAP 2.6 — GitOps engine"
echo -e "  ${YELLOW}attestation-server${RESET}    Trustee KBS — releases secrets after hardware proof"
echo -e "  ${RED}standard-vm${RESET}           Regular RHEL — ${RED}NO confidential computing${RESET}"
echo -e "  ${GREEN}rhel-cvm-secure${RESET}       AMD SEV-SNP CVM — ${GREEN}strict attestation${RESET}"
echo -e "  ${GREEN}rhel-cvm-insecure${RESET}     AMD SEV-SNP CVM — ${YELLOW}relaxed policy (debug)${RESET}"
echo ""
pause 2

comment "The repo structure"
run "ls ~/rhel-cc-pattern/"
pause 1.5

comment "One command deploys everything"
type_cmd "./pattern.sh make install" 0.06
pause 1

comment "Six Ansible playbooks run in sequence via AAP"
run "ls ~/rhel-cc-pattern/playbooks/"
pause 1.5

comment "The two RHEL System Roles at the heart of the pattern"
echo ""
echo -e "  ${CYAN}fedora.linux_system_roles.trustee_server${RESET}"
echo -e "  ${DIM}  → Deploys KBS + AS + RVPS on attestation-server${RESET}"
echo -e "  ${DIM}  → Via Podman Quadlets — systemd-managed containers${RESET}"
echo ""
echo -e "  ${CYAN}fedora.linux_system_roles.trustee_client${RESET}"
echo -e "  ${DIM}  → Deploys Attestation Agent + CDH on each CVM${RESET}"
echo -e "  ${DIM}  → Configures /etc/trustee-gc/ with KBS URL + cert${RESET}"
echo ""
pause 2

comment "initdata.toml — binds KBS URL and cert to the hardware measurement"
run "cat ~/rhel-cc-pattern/templates/initdata.toml.j2"
pause 2

comment "This file is passed as --custom-data when creating the CVM"
comment "The AMD SEV-SNP firmware measures its SHA-384 hash before the OS boots"
comment "KBS policy verifies this hash — preventing config tampering"
pause 2

# ── SECTION 2: INFRASTRUCTURE ─────────────────────────────────────────────────
banner "2/3  Live Infrastructure"

comment "All 4 VMs running on Azure"
run "az vm list -g rhel-cc-pattern-rg --show-details --query '[].{name:name,ip:publicIps,size:hardwareProfile.vmSize,state:powerState}' -o table"
pause 2

comment "KBS responding on attestation-server — requires hardware proof before releasing secrets"
run "curl -sk https://${KBS_IP}:8080/kbs/v0/resource/default/kbsres1/key3 -o /dev/null -w 'KBS: HTTP %{http_code} (401 = up, auth required)\n' --insecure"
pause 1.5

comment "AMD SEV-SNP hardware confirmed on both CVMs"
run "${SSH} ${SEC_IP} 'sudo dmesg | grep -i \"sev-snp\|confidential\"' 2>/dev/null | grep -v post-quantum"
pause 1.5

comment "hello-cc workload running on all 3 VMs"
for VM_DATA in "${STD_IP}:standard-vm" "${SEC_IP}:rhel-cvm-secure" "${INS_IP}:rhel-cvm-insecure"; do
  IP=$(cut -d: -f1 <<< "${VM_DATA}")
  NAME=$(cut -d: -f2 <<< "${VM_DATA}")
  STATUS=$(curl -s http://${IP}:8888 -o /dev/null -w "%{http_code}" --max-time 5 2>/dev/null)
  [[ "${STATUS}" == "200" ]] && \
    echo -e "  ${GREEN}✓${RESET} ${NAME}: http://${IP}:8888 → HTTP ${STATUS}" || \
    echo -e "  ${RED}✗${RESET} ${NAME}: HTTP ${STATUS}"
  pause 0.3
done
pause 2

# ── SECTION 3: ATTESTATION FLOW ───────────────────────────────────────────────
banner "3/3  Attestation Flow"

comment "The same trustee-attester binary runs on all 3 VMs"
comment "Only AMD SEV-SNP CVMs can produce valid hardware evidence"
echo ""
pause 1

# --- standard-vm ---
echo -e "${BOLD}${RED}Test 1: standard-vm (no confidential computing)${RESET}"
echo ""
comment "standard-vm has a vTPM but no CVM attestation key"
comment "trustee-attester cannot produce valid hardware evidence → DENIED"
echo ""
type_cmd "${SSH} ${STD_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>&1 | grep -E \"Error|handle|attester\"'" 0.03
${SSH} ${STD_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>&1 | grep -E "Error|handle|attester"' 2>/dev/null | head -5
echo ""
echo -e "  ${RED}✗ Secret NOT delivered — no valid AMD SEV-SNP evidence${RESET}"
pause 3

# --- rhel-cvm-insecure ---
echo ""
echo -e "${BOLD}${YELLOW}Test 2: rhel-cvm-insecure (AMD SEV-SNP, relaxed policy)${RESET}"
echo ""
comment "Real AMD SEV-SNP hardware — but KBS policy is relaxed (no claim check)"
comment "Secret released for testing/debugging CDH access"
echo ""
type_cmd "${SSH} ${INS_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null'" 0.03
RESULT_INS=$(${SSH} ${INS_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null' 2>/dev/null || echo "FAILED")
echo "${RESULT_INS}"
if echo "${RESULT_INS}" | grep -qE "^[A-Za-z0-9+/=]{20,}$"; then
  DECODED=$(echo "${RESULT_INS}" | base64 -d 2>/dev/null)
  echo ""
  echo -e "  ${GREEN}✓ Secret delivered: '${DECODED}'${RESET}"
  echo -e "  ${DIM}(relaxed policy — hardware present but no strict SNP claim check)${RESET}"
else
  echo -e "  ${RED}✗ Failed${RESET}"
fi
pause 3

# --- rhel-cvm-secure ---
echo ""
echo -e "${BOLD}${GREEN}Test 3: rhel-cvm-secure (AMD SEV-SNP, strict policy + initdata)${RESET}"
echo ""
comment "Real AMD SEV-SNP hardware — strict policy requires:"
comment "  1. Genuine AMD SEV-SNP chip (verified by Azure)"
comment "  2. initdata hash matches (KBS URL/cert bound to hardware)"
echo ""
type_cmd "${SSH} ${SEC_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null'" 0.03
RESULT_SEC=$(${SSH} ${SEC_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null' 2>/dev/null || echo "FAILED")
echo "${RESULT_SEC}"
if echo "${RESULT_SEC}" | grep -qE "^[A-Za-z0-9+/=]{20,}$"; then
  DECODED=$(echo "${RESULT_SEC}" | base64 -d 2>/dev/null)
  echo ""
  echo -e "  ${GREEN}✓ Secret delivered: '${DECODED}'${RESET}"
  echo -e "  ${DIM}(full AMD SEV-SNP attestation — hardware proof + config binding)${RESET}"
else
  echo -e "  ${RED}✗ Failed${RESET}"
fi
pause 3

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Summary${RESET}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${RED}✗ standard-vm${RESET}       No CVM hardware → secret DENIED"
echo -e "  ${YELLOW}✓ rhel-cvm-insecure${RESET}  AMD SEV-SNP + relaxed policy → secret OK"
echo -e "  ${GREEN}✓ rhel-cvm-secure${RESET}    AMD SEV-SNP + strict policy + initdata → secret OK"
echo ""
echo -e "  ${BOLD}The security boundary:${RESET}"
echo -e "  ${DIM}Azure hypervisor/admin CANNOT read secrets — memory is encrypted${RESET}"
echo -e "  ${DIM}KBS only releases secrets after hardware attestation${RESET}"
echo -e "  ${DIM}initdata binds KBS URL/cert to the hardware measurement${RESET}"
echo ""
echo -e "  ${BOLD}Repo:${RESET} ${CYAN}github.com/ariel-adam/rhel-cc-pattern${RESET}"
echo -e "  ${BOLD}Deploy:${RESET} ${GREEN}./pattern.sh make install${RESET}"
echo ""
pause 3
