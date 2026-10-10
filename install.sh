#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_URL="https://github.com/cedar2025/xboard-node.git"
readonly REPO_BRANCH="compose"
readonly INSTALL_DIR="/root/xboard-node"
readonly CONFIG_FILE="${INSTALL_DIR}/config/config.yml"

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
die() { printf '[ERR ] %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage (12 values; no target IP or SSH password):
  bash install.sh PANEL_A TOKEN_A NODE_ID_A DOMAIN_A EMAIL_A CF_API_A \
    PANEL_B TOKEN_B NODE_ID_B DOMAIN_B EMAIL_B CF_API_B

USAGE
}

[[ $EUID -eq 0 ]] || die 'Run this installer as root on the VPS.'
[[ -r /etc/os-release ]] || die 'Cannot identify OS: /etc/os-release is missing.'
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "Unsupported OS '${ID:-unknown}'. Debian/Ubuntu are required." ;;
esac
command -v apt-get >/dev/null 2>&1 || die 'apt-get is required.'

[[ $# -eq 12 ]] || { usage; die "Expected exactly 12 arguments, received $#"; }
PANEL_A="$1"; TOKEN_A="$2"; NODE_ID_A="$3"; DOMAIN_A="$4"; EMAIL_A="$5"; CF_API_A="$6"
PANEL_B="$7"; TOKEN_B="$8"; NODE_ID_B="$9"; DOMAIN_B="${10}"; EMAIL_B="${11}"; CF_API_B="${12}"

for name in PANEL_A TOKEN_A NODE_ID_A DOMAIN_A EMAIL_A CF_API_A PANEL_B TOKEN_B NODE_ID_B DOMAIN_B EMAIL_B CF_API_B; do
    [[ -n "${!name}" ]] || die "$name must not be empty."
    [[ "${!name}" != *$'\n'* && "${!name}" != *$'\r'* ]] || die "$name must not contain line breaks."
done
for name in NODE_ID_A NODE_ID_B; do
    [[ "${!name}" =~ ^[0-9]+$ ]] || die "$name must be a number."
done
for name in DOMAIN_A DOMAIN_B; do
    [[ "${!name}" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || die "$name is not a valid domain name."
done
for name in PANEL_A PANEL_B; do
    [[ "${!name}" =~ ^https?:// ]] || die "$name must start with http:// or https://."
done

command -v docker >/dev/null 2>&1 || die 'Docker is missing. Install Docker before running this installer.'
docker info >/dev/null 2>&1 || die 'Docker daemon is not running or cannot be reached.'
docker compose version >/dev/null 2>&1 || die "Docker Compose plugin ('docker compose') is required."
command -v python3 >/dev/null 2>&1 || die 'python3 is required.'

if ! command -v git >/dev/null 2>&1; then
    info 'Installing git...'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y git
fi

if [[ ! -e "$INSTALL_DIR" ]]; then
    info "Cloning xboard-node (${REPO_BRANCH} branch)..."
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
elif [[ ! -d "$INSTALL_DIR/.git" ]]; then
    die "$INSTALL_DIR already exists and is not a Git repository; move it aside or inspect it before continuing."
else
    origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$origin" == "$REPO_URL" || "$origin" == "${REPO_URL%.git}" ]] || die "$INSTALL_DIR exists but its origin is not the expected xboard-node repository."
fi

mkdir -p "${INSTALL_DIR}/config"
chmod 700 "${INSTALL_DIR}/config"

export H22_PANEL_A="$PANEL_A" H22_TOKEN_A="$TOKEN_A" H22_NODE_ID_A="$NODE_ID_A"
export H22_DOMAIN_A="$DOMAIN_A" H22_EMAIL_A="$EMAIL_A" H22_CF_API_A="$CF_API_A"
export H22_PANEL_B="$PANEL_B" H22_TOKEN_B="$TOKEN_B" H22_NODE_ID_B="$NODE_ID_B"
export H22_DOMAIN_B="$DOMAIN_B" H22_EMAIL_B="$EMAIL_B" H22_CF_API_B="$CF_API_B"

python3 - "$CONFIG_FILE" <<'PY'
import json
import os
import sys

out = sys.argv[1]
def q(name):
    return json.dumps(os.environ[name], ensure_ascii=False)

def node_id(name):
    return str(int(os.environ[name]))

lines = [
    'kernel:',
    '  type: "singbox"',
    '  config_dir: "/etc/xboard-node"',
    '  log_level: "warn"',
    '',
    'log:',
    '  level: "info"',
    '  output: "stdout"',
    '',
    'instances:',
]
for suffix in ('A', 'B'):
    key = suffix.lower()
    lines += [
        '',
        '  - panel:',
        f'      url: {q("H22_PANEL_" + suffix)}',
        f'      token: {q("H22_TOKEN_" + suffix)}',
        f'      node_id: {node_id("H22_NODE_ID_" + suffix)}',
        '',
        '    cert:',
        '      cert_mode: "dns"',
        f'      domain: {q("H22_DOMAIN_" + suffix)}',
        f'      email: {q("H22_EMAIL_" + suffix)}',
        '      dns_provider: "cloudflare"',
        '      dns_env:',
        f'        CF_API_TOKEN: {q("H22_CF_API_" + suffix)}',
    ]
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
os.chmod(out, 0o600)
PY

info 'Starting/updating the dual HY2 node...'
(
    cd "$INSTALL_DIR"
    docker compose up -d
)
ok 'Deployment command completed.'
printf '\nContainer status:\n'
(cd "$INSTALL_DIR" && docker compose ps)
printf '\nRecent logs:\n'
(cd "$INSTALL_DIR" && docker compose logs --tail=30)
printf '\nConfig file: %s (permissions 600)\n' "$CONFIG_FILE"
