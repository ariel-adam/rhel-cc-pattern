#!/usr/bin/env bash
# verify.sh — Run attestation tests and print demo results
set -uo pipefail

ip() { az vm show -g rhel-cc-pattern-rg -n "$1" --show-details --query publicIps -o tsv 2>/dev/null; }
KBS=$(ip attestation-server); STD=$(ip standard-vm); SEC=$(ip rhel-cvm-secure); INS=$(ip rhel-cvm-insecure)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           rhel-cc-pattern — Verification Results            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "1. KBS (${KBS})"
S=$(curl -sk https://${KBS}:8080/kbs/v0/resource/default/kbsres1/key1 -o /dev/null -w "%{http_code}" --insecure 2>/dev/null)
[[ "${S}" == "401" ]] && echo "   ✓ Running (HTTP 401 = auth required)" || echo "   ✗ Not reachable (${S})"

echo ""
echo "2. hello-cc workload"
for D in "standard-vm:${STD}:no CC" "rhel-cvm-secure:${SEC}:AMD SEV-SNP strict" "rhel-cvm-insecure:${INS}:AMD SEV-SNP relaxed"; do
  N=$(cut -d: -f1<<<$D); I=$(cut -d: -f2<<<$D); T=$(cut -d: -f3<<<$D)
  S=$(curl -s http://${I}:8888 -o /dev/null -w "%{http_code}" --max-time 5 2>/dev/null)
  [[ "${S}" == "200" ]] && echo "   ✓ ${N} (${T}): http://${I}:8888" || echo "   ✗ ${N}: unreachable"
done

echo ""
echo "3. Hardware Attestation"
for D in "standard-vm:${STD}:no CVM hardware" "rhel-cvm-secure:${SEC}:AMD SEV-SNP" "rhel-cvm-insecure:${INS}:AMD SEV-SNP relaxed"; do
  N=$(cut -d: -f1<<<$D); I=$(cut -d: -f2<<<$D); T=$(cut -d: -f3<<<$D)
  R=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 azureuser@${I} \
    "sudo /usr/local/bin/trustee-attester-v0.19 --url https://${KBS}:8080 --cert-file ~/kbs-ca.crt get-resource --path default/kbsres1/key3 2>/dev/null" 2>/dev/null || echo "FAILED")
  if echo "${R}" | grep -qE "^[A-Za-z0-9+/=]{20,}$"; then
    echo "   ✓ ${N} (${T}) → secret: '$(echo ${R}|base64 -d 2>/dev/null||echo ${R})'"
  else
    echo "   ✗ ${N} (${T}) → no secret (expected for non-CVM)"
  fi
done

echo ""
echo "  Demo UI: http://${STD}:8888  |  http://${SEC}:8888  |  http://${INS}:8888"
echo ""
