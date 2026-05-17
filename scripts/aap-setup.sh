#!/usr/bin/env bash
# aap-setup.sh — Bootstrap rhel-cc-pattern in AAP
# Creates: EE, SSH credential, SCM project, inventory, 6 JTs, 2 workflows
#
# Usage:
#   export AAP_URL=https://<aap-ip>
#   export AAP_USER=admin
#   export AAP_PASSWORD=<password>
#   export GITHUB_REPO=https://github.com/YOUR_USERNAME/rhel-cc-pattern.git
#   export SSH_KEY_FILE=~/.ssh/id_rsa   (optional, default: ~/.ssh/id_rsa)
#   bash scripts/aap-setup.sh

set -euo pipefail

: "${AAP_URL:?Set AAP_URL}"
: "${AAP_USER:?Set AAP_USER}"
: "${AAP_PASSWORD:?Set AAP_PASSWORD}"
: "${GITHUB_REPO:?Set GITHUB_REPO to your fork URL}"

SSH_KEY_FILE="${SSH_KEY_FILE:-${HOME}/.ssh/id_rsa}"
API="${AAP_URL}/api/controller/v2"
CURL=(curl -sk -u "${AAP_USER}:${AAP_PASSWORD}" -H "Content-Type: application/json")

post() { "${CURL[@]}" -X POST "${API}$1" -d "${2:-{}}"; }
get()  { "${CURL[@]}" "${API}$1"; }
patch(){ "${CURL[@]}" -X PATCH "${API}$1" -d "${2:-{}}"; }
id_of(){ python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))"; }

echo "=== rhel-cc-pattern AAP Bootstrap ==="
echo "AAP:  ${AAP_URL}"
echo "Repo: ${GITHUB_REPO}"
echo ""

# 1. Execution Environment
echo "[1/7] Execution Environment..."
EE_ID=$(post "/execution_environments/" '{
  "name":"rhel-cc-pattern-ee",
  "image":"ghcr.io/ariel-adam/rhel-cc-pattern-ee:latest",
  "pull":"always",
  "description":"rhel-cc-pattern EE — az CLI 2.86 + fedora.linux_system_roles"
}' | id_of)
echo "   EE ID: ${EE_ID}"

# 2. SSH Credential
echo "[2/7] SSH Machine Credential..."
SSH_KEY=$(cat "${SSH_KEY_FILE}")
SSH_PUB=$(cat "${SSH_KEY_FILE}.pub")
CRED_ID=$(python3 -c "
import json, subprocess
data = json.dumps({
  'name': 'rhel-cc-pattern-ssh',
  'credential_type': 1,
  'organization': 1,
  'inputs': {'username': 'azureuser', 'ssh_key_data': open('${SSH_KEY_FILE}').read()}
})
print(data)
" | post "/credentials/" | id_of)
echo "   Credential ID: ${CRED_ID}"

# 3. SCM Project
echo "[3/7] Project..."
PROJ_ID=$(post "/projects/" "$(python3 -c "
import json
print(json.dumps({
  'name': 'rhel-cc-pattern',
  'scm_type': 'git',
  'scm_url': '${GITHUB_REPO}',
  'scm_branch': 'main',
  'scm_update_on_launch': True,
  'scm_update_cache_timeout': 60,
  'organization': 1
}))
")" | id_of)
echo "   Project ID: ${PROJ_ID}"
echo "   Waiting for sync..."
for i in $(seq 1 30); do
  sleep 5
  STATUS=$(get "/projects/${PROJ_ID}/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")
  echo "   [${i}] ${STATUS}"
  [[ "${STATUS}" == "successful" || "${STATUS}" == "failed" ]] && break
done

# 4. Inventory
echo "[4/7] Inventory..."
INV_ID=$(post "/inventories/" "$(python3 -c "
import json
print(json.dumps({
  'name': 'rhel-cc-pattern',
  'organization': 1,
  'variables': json.dumps({
    'vm_ssh_pubkey': open('${SSH_KEY_FILE}.pub').read().strip(),
    'resource_group': 'rhel-cc-pattern-rg',
    'location': 'eastus',
    'aap_controller_url': '${AAP_URL}',
    'aap_admin_user': '${AAP_USER}',
    'aap_admin_password': '${AAP_PASSWORD}',
    'aap_inventory_id_num': '__PLACEHOLDER__'
  }, indent=2)
}))
")" | id_of)
echo "   Inventory ID: ${INV_ID}"

# Update with self-reference
patch "/inventories/${INV_ID}/" "$(python3 -c "
import json
print(json.dumps({'variables': json.dumps({
  'vm_ssh_pubkey': open('${SSH_KEY_FILE}.pub').read().strip(),
  'resource_group': 'rhel-cc-pattern-rg',
  'location': 'eastus',
  'aap_controller_url': '${AAP_URL}',
  'aap_admin_user': '${AAP_USER}',
  'aap_admin_password': '${AAP_PASSWORD}',
  'aap_inventory_id_num': '${INV_ID}'
}, indent=2)}))
")" > /dev/null

# Add placeholder hosts
for HOST in "agof-aap-node:aap_controllers" "attestation-server:attestation_servers" \
            "standard-vm:standard_vms" "rhel-cvm-secure:rhel_cvms_secure" \
            "rhel-cvm-insecure:rhel_cvms_insecure"; do
  NAME=$(echo "${HOST}" | cut -d: -f1)
  post "/hosts/" "{\"name\":\"${NAME}\",\"inventory\":${INV_ID},\"variables\":\"{}\"}" > /dev/null
  echo "   Host: ${NAME}"
done

# 5. Job Templates
echo "[5/7] Job Templates..."
JT_IDS=()
for PB in \
  "01 - Provision Attestation Server:playbooks/01_provision_attestation_server.yml" \
  "02 - Deploy Attestation Server:playbooks/02_deploy_attestation_server.yml" \
  "03 - Generate initdata:playbooks/03_generate_initdata.yml" \
  "04 - Provision VMs:playbooks/04_provision_vms.yml" \
  "05 - Deploy Standard VM:playbooks/05_deploy_standard_vm.yml" \
  "06 - Deploy RHEL CVMs:playbooks/06_deploy_rhel_cvms.yml"; do
  NAME=$(echo "${PB}" | cut -d: -f1)
  PLAYBOOK=$(echo "${PB}" | cut -d: -f2)
  JT_ID=$(post "/job_templates/" "$(python3 -c "
import json
print(json.dumps({'name':'rhel-cc-pattern: ${NAME}','job_type':'run',
  'inventory':${INV_ID},'project':${PROJ_ID},'playbook':'${PLAYBOOK}',
  'execution_environment':${EE_ID}}))
")" | id_of)
  post "/job_templates/${JT_ID}/credentials/" "{\"id\":${CRED_ID}}" > /dev/null
  JT_IDS+=("${JT_ID}")
  echo "   JT ${JT_ID}: ${NAME}"
done

# 6. Full workflow (all 6 steps)
echo "[6/7] Full Workflow..."
WF_ID=$(post "/workflow_job_templates/" '{
  "name":"rhel-cc-pattern: Deploy Full Pattern",
  "description":"GitOps: full deployment — runs on git push",
  "organization":1
}' | id_of)
PREV=""
for i in "${!JT_IDS[@]}"; do
  NODE=$(post "/workflow_job_templates/${WF_ID}/workflow_nodes/" \
    "{\"unified_job_template\":${JT_IDS[$i]},\"identifier\":\"step-$(printf '%02d' $((i+1)))\"}" | \
    id_of)
  [[ -n "${PREV}" ]] && post "/workflow_job_template_nodes/${PREV}/success_nodes/" "{\"id\":${NODE}}" > /dev/null
  PREV="${NODE}"
  echo "   Step $((i+1)): JT ${JT_IDS[$i]} → node ${NODE}"
done

# 7. Phase 1 workflow (steps 01+02 only — for first run)
echo "[7/7] Phase 1 Workflow (first-run bootstrap)..."
WF1_ID=$(post "/workflow_job_templates/" '{
  "name":"rhel-cc-pattern: Phase 1 - Bootstrap Attestation Server",
  "description":"FIRST RUN: provisions attestation-server and deploys KBS. Run before full workflow.",
  "organization":1
}' | id_of)
N1=$(post "/workflow_job_templates/${WF1_ID}/workflow_nodes/" \
  "{\"unified_job_template\":${JT_IDS[0]},\"identifier\":\"step-01\"}" | id_of)
N2=$(post "/workflow_job_templates/${WF1_ID}/workflow_nodes/" \
  "{\"unified_job_template\":${JT_IDS[1]},\"identifier\":\"step-02\"}" | id_of)
post "/workflow_job_template_nodes/${N1}/success_nodes/" "{\"id\":${N2}}" > /dev/null

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  AAP bootstrap complete!                                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Next: run make install (handled automatically)              ║"
echo "║  Or manually:                                                ║"
echo "║  1. Run 'Phase 1 - Bootstrap Attestation Server'             ║"
echo "║  2. Run 'Deploy Full Pattern'                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
