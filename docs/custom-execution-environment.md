# Custom Execution Environment

## Pre-built Image

```
ghcr.io/ariel-adam/rhel-cc-pattern-ee:latest
```

Contains:
- `az` CLI 2.86.0 (Azure CLI)
- `fedora.linux_system_roles` collection
- `ansible.posix` collection
- All dependencies from `quay.io/ansible/awx-ee:latest`

This EE is registered in AAP by `scripts/aap-setup.sh` automatically.

## Rebuilding

```bash
ansible-builder build \
  --file ee/execution-environment.yml \
  --tag ghcr.io/ariel-adam/rhel-cc-pattern-ee:latest

podman push ghcr.io/ariel-adam/rhel-cc-pattern-ee:latest
```

Requires a Red Hat registry service account to pull `quay.io/ansible/awx-ee`.
Build takes ~5-10 minutes depending on network speed.
