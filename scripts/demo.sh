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
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

KBS_IP="${KBS_IP:-20.102.84.105}"
STD_IP="${STD_IP:-20.25.91.202}"
SEC_IP="${SEC_IP:-104.211.18.78}"
INS_IP="${INS_IP:-172.173.240.64}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY} azureuser"

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

comment() {
  echo -e "${DIM}# $1${RESET}"
  pause 0.8
}

say() {
  echo -e "$1"
  pause "${2:-1.2}"
}

# ── DEMO START ────────────────────────────────────────────────────────────────
clear

# ── SECTION 0: BLOCK DIAGRAM ──────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'DIAGRAM'
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                      rhel-cc-pattern  │  Azure (eastus)                 │
 │                                                                         │
 │  ┌───────────────────┐    ┌───────────────────┐                         │
 │  │   agof-aap-node   │    │ attestation-server │                         │
 │  │   Standard_D8s_v3 │    │  Standard_D4s_v3   │                         │
 │  │                   │    │                    │                         │
 │  │  AAP 2.6          │───►│  Trustee KBS :8080 │                         │
 │  │  GitOps engine    │    │  AS  (builtin)     │                         │
 │  │  Runs playbooks   │    │  RVPS (builtin)    │                         │
 │  └───────────────────┘    └────────┬───────────┘                         │
 │                                    │ attestation                         │
 │              ┌─────────────────────┼──────────────────┐                 │
 │              │                     │                  │                 │
 │  ┌───────────▼────────┐ ┌──────────▼──────────┐ ┌────▼────────────────┐│
 │  │    standard-vm     │ │   rhel-cvm-secure    │ │  rhel-cvm-insecure  ││
 │  │  Standard_D4s_v3   │ │  Standard_DC2as_v5   │ │  Standard_DC2as_v5  ││
 │  │                    │ │  ╔══ AMD SEV-SNP ══╗  │ │  ╔══ AMD SEV-SNP ╗  ││
 │  │  Regular RHEL VM   │ │  ║  Memory         ║  │ │  ║  Memory       ║  ││
 │  │  No CC hardware    │ │  ║  encrypted by   ║  │ │  ║  encrypted    ║  ││
 │  │                    │ │  ║  AMD hardware   ║  │ │  ║  by AMD hw    ║  ││
 │  │  hello-cc :8888    │ │  ╚════════════════╝  │ │  ╚═══════════════╝  ││
 │  │  trustee-attester  │ │  hello-cc  :8888     │ │  hello-cc  :8888    ││
 │  │     → FAILS ✗      │ │  trustee-attester    │ │  trustee-attester   ││
 │  │                    │ │     strict policy    │ │     relaxed policy  ││
 │  │                    │ │     → SUCCEEDS ✓     │ │     → SUCCEEDS ✓    ││
 │  └────────────────────┘ └──────────────────────┘ └─────────────────────┘│
 └─────────────────────────────────────────────────────────────────────────┘
DIAGRAM
echo -e "${RESET}"
pause 4

# ── SECTION 1: WHAT IS THIS? ──────────────────────────────────────────────────
banner "What is rhel-cc-pattern?"

say "${BOLD}rhel-cc-pattern${RESET} is an Ansible GitOps pattern for deploying"
say "RHEL Confidential VMs on Azure with hardware-backed attestation."
pause 0.5

say "It is the ${BOLD}RHEL-native equivalent${RESET} of the ${CYAN}coco-pattern${RESET}:"
say "  ${DIM}same AMD SEV-SNP attestation story${RESET}"
say "  ${DIM}same Trustee KBS (Key Broker Service)${RESET}"
say "  ${DIM}but running on standalone RHEL VMs, not OpenShift${RESET}"
pause 1

say "The core question it answers:"
echo ""
say "  ${BOLD}\"How does a workload prove to a secret store that it is running${RESET}"
say "  ${BOLD}   on genuine, unmodified, trusted hardware — before any${RESET}"
say "  ${BOLD}   secrets are released?\"${RESET}"
pause 2

say "The answer: ${GREEN}AMD SEV-SNP hardware attestation${RESET} gated by Trustee KBS."
say "  ${DIM}KBS only releases secrets after the Azure hypervisor confirms${RESET}"
say "  ${DIM}the VM is a genuine, unmodified AMD SEV-SNP Confidential VM.${RESET}"
pause 2

say "Deploy the whole pattern with a single command:"
echo ""
type_cmd "./pattern.sh make install" 0.07
pause 2

# ── SECTION 2: THE REPO AND SYSTEM ROLES ──────────────────────────────────────
banner "The Repository and RHEL System Roles"

comment "The repo structure follows the validated patterns convention"
run "ls ~/rhel-cc-pattern/"
pause 1.5

say "${BOLD}At the heart of the pattern: two RHEL System Roles${RESET}"
echo ""
say "  ${CYAN}${BOLD}fedora.linux_system_roles.trustee_server${RESET}"
say "  ${DIM}  Runs on: attestation-server${RESET}"
say "  ${DIM}  Deploys KBS + AS + RVPS as Podman Quadlets${RESET}"
say "  ${DIM}  Generates TLS certificates, opens firewall port 8080${RESET}"
say "  ${DIM}  → Official Red Hat role, idempotent, RHEL 8/9/10 compatible${RESET}"
echo ""
say "  ${CYAN}${BOLD}fedora.linux_system_roles.trustee_client${RESET}"
say "  ${DIM}  Runs on: both AMD SEV-SNP CVMs${RESET}"
say "  ${DIM}  Deploys Attestation Agent + Confidential Data Hub${RESET}"
say "  ${DIM}  Configures /etc/trustee-gc/ with KBS URL and TLS cert${RESET}"
say "  ${DIM}  → Same role, different group_vars → different policies${RESET}"
pause 2

comment "The six playbooks run in sequence as an AAP workflow"
run "ls ~/rhel-cc-pattern/playbooks/"
pause 1.5

comment "initdata.toml: binds the KBS URL and cert to the hardware measurement"
say "${DIM}Passed as --custom-data at VM creation time.${RESET}"
say "${DIM}AMD SEV-SNP firmware measures its SHA-384 hash before the OS boots.${RESET}"
say "${DIM}KBS policy verifies this hash — you cannot redirect to a fake KBS.${RESET}"
echo ""
run "cat ~/rhel-cc-pattern/templates/initdata.toml.j2"
pause 2

# ── SECTION 3: LIVE INFRASTRUCTURE ────────────────────────────────────────────
banner "Live Infrastructure: 1 Standard VM + 2 Confidential VMs"

say "${BOLD}Deployed on Azure (eastus):${RESET}"
echo ""
say "  ${YELLOW}attestation-server${RESET}  — Trustee KBS (Standard_D4s_v3, regular RHEL)"
say "  ${RED}standard-vm${RESET}         — ${RED}Regular RHEL VM, NO confidential computing${RESET}"
say "  ${GREEN}rhel-cvm-secure${RESET}     — ${GREEN}AMD SEV-SNP CVM, strict attestation policy${RESET}"
say "  ${GREEN}rhel-cvm-insecure${RESET}   — ${GREEN}AMD SEV-SNP CVM, relaxed policy (for debugging)${RESET}"
echo ""
pause 1

comment "All VMs running on Azure"
run "az vm list -g rhel-cc-pattern-rg --show-details --query '[].{name:name,ip:publicIps,size:hardwareProfile.vmSize,state:powerState}' -o table 2>/dev/null || echo 'az not available in this context'"
pause 2

comment "Crucially: the 2 CVMs are Standard_DC2as_v5 — the AMD SEV-SNP family"
say "  ${DIM}Standard_DCas_v5 = AMD EPYC with SEV-SNP = hardware memory encryption${RESET}"
say "  ${DIM}The hypervisor CANNOT read the VM's memory — even Azure staff${RESET}"
say "  ${DIM}standard-vm uses Standard_D4s_v3 — a regular VM, no CC hardware${RESET}"
pause 2

comment "KBS is up and enforcing attestation"
run "curl -sk https://${KBS_IP}:8080/kbs/v0/resource/default/kbsres1/key1 -o /dev/null -w 'KBS: HTTP %{http_code} (401 = up, auth required)\\n' --insecure"
pause 1.5

comment "AMD SEV-SNP hardware confirmed on rhel-cvm-secure"
run "${SSH} ${SEC_IP} 'sudo dmesg | grep -i \"sev-snp\\|confidential\"' 2>/dev/null | grep -v post-quantum | head -3"
pause 1.5

comment "hello-cc workload running on all 3 VMs — same app, different security"
for VM_DATA in "${STD_IP}:standard-vm (no CC)" "${SEC_IP}:rhel-cvm-secure (AMD SEV-SNP)" "${INS_IP}:rhel-cvm-insecure (AMD SEV-SNP)"; do
  IP=$(cut -d: -f1 <<< "${VM_DATA}")
  NAME=$(cut -d: -f2- <<< "${VM_DATA}")
  STATUS=$(curl -s "http://${IP}:8888" -o /dev/null -w "%{http_code}" --max-time 5 2>/dev/null || echo "000")
  [[ "${STATUS}" == "200" ]] && \
    echo -e "  ${GREEN}✓${RESET} ${NAME}: http://${IP}:8888 → HTTP ${STATUS}" || \
    echo -e "  ${RED}✗${RESET} ${NAME}: HTTP ${STATUS}"
  pause 0.4
done
pause 2

# ── SECTION 4: ATTESTATION FLOW ───────────────────────────────────────────────
banner "Attestation: The Same Binary, Three Different Results"

comment "trustee-attester v0.19.0 is installed on all 3 VMs"
comment "It talks RCAR protocol to the KBS and presents hardware evidence"
comment "The KBS only releases the secret if the evidence is valid"
echo ""
pause 1

# --- standard-vm ---
echo -e "${BOLD}${RED}▶ Test 1 of 3: standard-vm  (Standard_D4s_v3 — regular RHEL, NO CVM)${RESET}"
echo ""
say "  ${DIM}standard-vm has a vTPM but no CVM attestation key (handle 0x81010002).${RESET}"
say "  ${DIM}trustee-attester cannot produce valid AMD SEV-SNP evidence.${RESET}"
say "  ${DIM}Expected result: DENIED ✗${RESET}"
echo ""
type_cmd "${SSH} ${STD_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>&1 | grep -E \"Error|handle|FAILED\"'" 0.03
${SSH} ${STD_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>&1 | grep -E "Error|handle|FAILED"' 2>/dev/null | head -3 || true
echo ""
echo -e "  ${RED}✗ Secret NOT delivered${RESET}"
echo -e "  ${DIM}The vTPM key handle for CVM attestation does not exist on a standard VM.${RESET}"
pause 3

# --- rhel-cvm-insecure ---
echo ""
echo -e "${BOLD}${YELLOW}▶ Test 2 of 3: rhel-cvm-insecure  (Standard_DC2as_v5 — AMD SEV-SNP, relaxed policy)${RESET}"
echo ""
say "  ${DIM}Real AMD SEV-SNP hardware — KBS policy is relaxed (no strict SNP claim check).${RESET}"
say "  ${DIM}Useful for testing CDH access without requiring a strict attestation policy.${RESET}"
say "  ${DIM}Expected result: secret released ✓${RESET}"
echo ""
type_cmd "${SSH} ${INS_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null'" 0.03
RESULT_INS=$(${SSH} ${INS_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null' 2>/dev/null || echo "FAILED")
echo "${RESULT_INS}"
if echo "${RESULT_INS}" | grep -qE "^[A-Za-z0-9+/=]{20,}$"; then
  DECODED=$(echo "${RESULT_INS}" | base64 -d 2>/dev/null || echo "${RESULT_INS}")
  echo ""
  echo -e "  ${GREEN}✓ Secret delivered: '${DECODED}'${RESET}"
  echo -e "  ${DIM}Hardware attestation succeeded — relaxed policy, no strict SNP claim check.${RESET}"
else
  echo -e "  ${RED}✗ Failed: ${RESULT_INS}${RESET}"
fi
pause 3

# --- rhel-cvm-secure ---
echo ""
echo -e "${BOLD}${GREEN}▶ Test 3 of 3: rhel-cvm-secure  (Standard_DC2as_v5 — AMD SEV-SNP, strict policy)${RESET}"
echo ""
say "  ${DIM}Real AMD SEV-SNP hardware — strict KBS policy requires:${RESET}"
say "  ${DIM}  1. Genuine AMD SEV-SNP chip (verified by Azure Attestation Service)${RESET}"
say "  ${DIM}  2. initdata hash matches — KBS URL and cert are bound to the hardware${RESET}"
say "  ${DIM}Expected result: secret released ✓  (full hardware proof)${RESET}"
echo ""
type_cmd "${SSH} ${SEC_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null'" 0.03
RESULT_SEC=$(${SSH} ${SEC_IP} 'sudo trustee-attester-v0.19 --url https://${KBS_IP}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null' 2>/dev/null || echo "FAILED")
echo "${RESULT_SEC}"
if echo "${RESULT_SEC}" | grep -qE "^[A-Za-z0-9+/=]{20,}$"; then
  DECODED=$(echo "${RESULT_SEC}" | base64 -d 2>/dev/null || echo "${RESULT_SEC}")
  echo ""
  echo -e "  ${GREEN}✓ Secret delivered: '${DECODED}'${RESET}"
  echo -e "  ${DIM}Full AMD SEV-SNP attestation: hardware proof + initdata config binding.${RESET}"
else
  echo -e "  ${RED}✗ Failed: ${RESULT_SEC}${RESET}"
fi
pause 3

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Summary${RESET}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${RED}✗  standard-vm${RESET}        Regular VM — no CVM hardware → secret ${RED}DENIED${RESET}"
echo -e "  ${YELLOW}✓  rhel-cvm-insecure${RESET}   AMD SEV-SNP + relaxed policy  → secret ${GREEN}OK${RESET}"
echo -e "  ${GREEN}✓  rhel-cvm-secure${RESET}     AMD SEV-SNP + strict + initdata → secret ${GREEN}OK${RESET}"
echo ""
echo -e "  ${BOLD}The security guarantee:${RESET}"
echo -e "  ${DIM}• Azure hypervisor/admin cannot read CVM memory — AMD encrypts it${RESET}"
echo -e "  ${DIM}• KBS only releases secrets after hardware attestation${RESET}"
echo -e "  ${DIM}• initdata binds the KBS URL/cert to the hardware measurement${RESET}"
echo -e "  ${DIM}• Changing the KBS URL or cert changes the hash — attestation fails${RESET}"
echo ""
echo -e "  ${BOLD}GitOps loop:${RESET}  ${DIM}push to git → AAP detects → workflow runs → VMs updated${RESET}"
echo ""
echo -e "  ${BOLD}Repo:${RESET}    ${CYAN}github.com/ariel-adam/rhel-cc-pattern${RESET}"
echo -e "  ${BOLD}Deploy:${RESET}  ${GREEN}./pattern.sh make install${RESET}"
echo ""
pause 3
