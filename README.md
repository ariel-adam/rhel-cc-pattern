# rhel-cc-pattern

An Ansible GitOps pattern for **RHEL Confidential VMs** on Azure using
[Trustee](https://confidentialcontainers.org/docs/attestation/) (KBS) for
hardware-backed AMD SEV-SNP attestation.

The **RHEL-native equivalent** of [coco-pattern](https://github.com/validatedpatterns/coco-pattern):
same attestation story, same Trustee KBS — but running on standalone RHEL VMs
managed by [AGOF](https://github.com/validatedpatterns/agof) / AAP
instead of ArgoCD / OpenShift.

---

## Quick Start

```bash
# 1. Fork this repo on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/rhel-cc-pattern && cd rhel-cc-pattern

# 2. Set four environment variables
export AAP_URL=https://<your-aap-ip>       # AAP 2.6 instance (deploy via AGOF)
export AAP_USER=admin
export AAP_PASSWORD=<your-aap-password>
export GITHUB_REPO=https://github.com/YOUR_USERNAME/rhel-cc-pattern.git

# 3. Deploy
./pattern.sh make install
```

That's it. The script handles everything else.

---

## Demo

![Demo: block diagram, RHEL System Roles, and live attestation on 3 VMs](docs/demo.gif)

*2m 54s at 3× speed — architecture overview, RHEL System Roles, and live attestation
flow: standard VM (denied) vs two AMD SEV-SNP CVMs (secret delivered).*

▶ Watch at full speed: [asciinema.org/a/0JuQDRqzL8NbpwwT](https://asciinema.org/a/0JuQDRqzL8NbpwwT)

To re-record on your own deployment:
```bash
bash scripts/record-demo.sh
```

---

## What It Deploys

Four Azure VMs, three running the same workload (`hello-cc`) to show the
security boundary:

| VM | Type | Attestation | Secret delivered? |
|----|------|-------------|-------------------|
| `attestation-server` | Standard_D4s_v3 | Runs KBS | — |
| `standard-vm` | Standard_D4s_v3 | None | ❌ No hardware evidence |
| `rhel-cvm-secure` | Standard_DC2as_v5 (AMD SEV-SNP) | **Strict** | ✅ After hardware proof |
| `rhel-cvm-insecure` | Standard_DC2as_v5 (AMD SEV-SNP) | **Relaxed** | ✅ Without hardware check |

`trustee-attester` on `standard-vm` fails because it cannot produce valid
AMD SEV-SNP hardware evidence. The two CVMs succeed because the Azure hypervisor
confirms their hardware identity before KBS releases the secret.

---

## Architecture

```
agof-aap-node (AAP 2.6)
  └─ GitOps engine — watches this repo, runs playbooks on change

attestation-server (Standard_D4s_v3)
  └─ KBS :8080 — only releases secrets after hardware attestation
  └─ AS (builtin) — verifies AMD SEV-SNP reports
  └─ RVPS (builtin) — stores PCR reference values

standard-vm (Standard_D4s_v3)          rhel-cvm-secure / rhel-cvm-insecure
  └─ hello-cc :8888                       (Standard_DC2as_v5 — AMD SEV-SNP)
  └─ trustee-attester → FAILS ✗           └─ hello-cc :8888
                                          └─ trustee-attester → SUCCESS ✓
                                          └─ trustee_client (AA + CDH)
```

---

## Prerequisites

**1. AAP 2.6 running**
Deploy via [github.com/validatedpatterns/agof](https://github.com/validatedpatterns/agof).

**2. Azure CLI authenticated on the AAP node**
```bash
ssh azureuser@<aap-node-ip>
az login
exit
```

**3. Azure quota for Standard DCASv5**
Azure Portal → Subscriptions → Usage + quotas → request at least 4 vCPUs
for the `Standard DCASv5` family.

---

## RHEL System Roles

This pattern uses two **[RHEL System Roles](https://access.redhat.com/articles/3050101)**:

| Role | Runs on | What it does |
|------|---------|--------------|
| `fedora.linux_system_roles.trustee_server` | `attestation-server` | Deploys KBS + AS + RVPS via Podman Quadlets, generates TLS certs, opens firewall |
| `fedora.linux_system_roles.trustee_client` | both CVMs | Deploys Attestation Agent + CDH via Podman Quadlets, configures `/etc/trustee-gc/` |

---

## Other Commands

```bash
./pattern.sh make verify     # run attestation tests, show results
./pattern.sh make status     # show VM and service status
./pattern.sh make uninstall  # destroy all Azure VMs
```

---

## GitOps Loop

Once deployed, any change pushed to your fork triggers a redeployment:

```bash
vim inventory/group_vars/rhel_cvms_secure.yml  # make a change
git push
# AAP detects change in ~60s → runs workflow → VMs updated
```

---

## Comparison with coco-pattern

| | [coco-pattern](https://github.com/validatedpatterns/coco-pattern) | rhel-cc-pattern |
|---|---|---|
| **Install** | `./pattern.sh make install` | `./pattern.sh make install` |
| **Platform** | OpenShift 4.19+ | RHEL 9.6 VMs |
| **GitOps engine** | ArgoCD | AAP / AGOF |
| **TEE boundary** | Per pod (Kata CVM) | Per VM |
| **KBS deployment** | Trustee Operator (OCP) | `trustee_server` system role |
| **initdata injection** | Kyverno MutatingWebhook | `az vm create --custom-data` |
| **Prerequisite** | OpenShift cluster | AAP instance |

---

## Repository Structure

```
rhel-cc-pattern/
├── pattern.sh              ← entry point (./pattern.sh make install)
├── Makefile                ← install / uninstall / verify / status
├── inventory/
│   ├── hosts.ini           ← VM groups (IPs set in AAP, not here)
│   └── group_vars/         ← per-group Ansible variables
├── playbooks/              ← 6 playbooks (one per workflow step)
├── workload/               ← hello-cc source (Containerfile + server.py)
├── scripts/
│   ├── aap-setup.sh        ← one-shot AAP bootstrap
│   ├── run-workflow.sh     ← launch + wait for AAP workflow
│   └── verify.sh           ← attestation tests
├── ee/
│   └── execution-environment.yml  ← custom EE definition
│       (published: ghcr.io/ariel-adam/rhel-cc-pattern-ee — az CLI 2.86)
├── collections/
│   └── requirements.yml
├── templates/
│   └── initdata.toml.j2
└── docs/
    ├── trustee-attester-build.md
    └── custom-execution-environment.md
```

---

## Known Limitation

The RHEL RHUI repos ship `trustee-guest-components` v0.10.0 (RCAR protocol 0.1.1)
which is incompatible with KBS 1.1 (expects 0.4.0). Playbook 06 builds
`trustee-attester` v0.19.0 from source automatically (~15 min per CVM on first run).
See [docs/trustee-attester-build.md](docs/trustee-attester-build.md).

---

## License

Apache 2.0
