#!/usr/bin/env bash
# run-workflow.sh — Launch an AAP workflow and wait for completion
set -euo pipefail

: "${AAP_URL:?}" ; : "${AAP_USER:?}" ; : "${AAP_PASSWORD:?}"
WORKFLOW_NAME="${1:?Workflow name required}"
API="${AAP_URL}/api/controller/v2"

get()  { curl -sk -u "${AAP_USER}:${AAP_PASSWORD}" "${API}$1"; }
post() { curl -sk -u "${AAP_USER}:${AAP_PASSWORD}" -X POST \
         -H "Content-Type: application/json" "${API}$1" -d "${2:-{}}"; }

WF_ID=$(get "/workflow_job_templates/?name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${WORKFLOW_NAME}'))")" | \
  python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else 'NOT_FOUND')")

[[ "${WF_ID}" == "NOT_FOUND" ]] && { echo "ERROR: Workflow '${WORKFLOW_NAME}' not found. Run aap-setup.sh first."; exit 1; }

JOB_ID=$(post "/workflow_job_templates/${WF_ID}/launch/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
echo "  Workflow job ${JOB_ID} started"

ELAPSED=0
while true; do
  STATUS=$(get "/workflow_jobs/${JOB_ID}/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")
  printf "\r  [%ds] %-12s" "${ELAPSED}" "${STATUS}"
  case "${STATUS}" in
    successful) echo ""; echo "  ✓ Done"; break ;;
    failed|error|canceled)
      echo ""; echo "  ✗ ${STATUS}"
      get "/workflow_jobs/${JOB_ID}/workflow_nodes/?page_size=20" | python3 -c "
import sys,json
for n in json.load(sys.stdin)['results']:
  s=n.get('status','?'); nm=n.get('summary_fields',{}).get('unified_job_template',{}).get('name','').replace('rhel-cc-pattern: ','')
  print(f\"  {'✓' if s=='successful' else '✗' if s=='failed' else '?'} {nm} ({s})\")"
      exit 1 ;;
  esac
  sleep 10; ELAPSED=$((ELAPSED+10))
done
