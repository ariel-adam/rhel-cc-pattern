# Building trustee-attester v0.19.0 from Source

## Why This Is Needed

The `trustee-guest-components` RPM in RHEL 9.6/10 RHUI repos is version `0.10.0`
(RCAR protocol 0.1.1), incompatible with KBS 1.1 (expects 0.4.0).

Playbook 06 builds `trustee-attester` v0.19.0 automatically. This takes ~15 min
on a Standard_DC2as_v5 (2 vCPU). The result is installed idempotently at
`/usr/local/bin/trustee-attester-v0.19`.

## Manual Build (if needed)

```bash
# Install build deps
sudo dnf install -y gcc gcc-c++ make openssl-devel pkg-config perl tpm2-tss-devel
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env

# Download source + vendor deps
curl -L -o /tmp/gc-src.tar.gz \
  https://github.com/confidential-containers/guest-components/archive/refs/tags/v0.19.0.tar.gz
curl -L -o /tmp/gc-vendor.tar.gz \
  https://github.com/confidential-containers/guest-components/releases/download/v0.19.0/guest-components-v0.19.0-vendor.tar.gz

cd /tmp && tar xzf gc-src.tar.gz && tar xzf gc-vendor.tar.gz

# Configure offline vendor
mkdir -p /tmp/guest-components-0.19.0/.cargo
cat > /tmp/guest-components-0.19.0/.cargo/config.toml << 'EOF'
[source.crates-io]
replace-with = "vendored-sources"
[source.vendored-sources]
directory = "/tmp/vendor"
EOF

# Build
cd /tmp/guest-components-0.19.0
cargo build --release --offline \
  --manifest-path attestation-agent/kbs_protocol/Cargo.toml \
  --bin trustee-attester \
  --features "bin,az-snp-vtpm-attester"

sudo install -m755 target/release/trustee-attester /usr/local/bin/trustee-attester-v0.19
```

## When This Will No Longer Be Needed

When Red Hat ships `trustee-guest-components >= 0.19.0` in the RHEL RHUI repos.
Check: `sudo dnf info trustee-guest-components | grep Version`
