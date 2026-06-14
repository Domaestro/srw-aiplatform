# Shared helpers for prototype scripts.
# Source this file from every script: `source "$(dirname "$0")/lib.sh"`

set -Eeuo pipefail

# Resolve repository paths once.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
PROTOTYPE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECONDSTEP_DIR="$(cd "${PROTOTYPE_DIR}/.." && pwd)"
LOCAL_STATE_DIR="${PROTOTYPE_DIR}/.local"
mkdir -p "${LOCAL_STATE_DIR}"

CLUSTER_NAME="${CLUSTER_NAME:-aiplatform}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.31.4-k3s1}"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '\033[1;33m[%s WARN]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '\033[1;31m[%s ERR ]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# Shared 'ensure_secret_file' helper used by every installer script.
# Reads 32 random bytes via openssl (no pipes that could SIGPIPE under set -e + pipefail).
ensure_secret_file() {
    local f="$1"
    if [[ ! -s "${f}" ]]; then
        openssl rand -hex 16 > "${f}"
        chmod 600 "${f}"
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Required command '$1' is not installed. Run scripts/00_install_prereqs.sh first."
        exit 1
    fi
}

# Render a manifest, replacing PROTOTYPE_DIR placeholder with the resolved path.
# Usage: render_manifest src dst
render_manifest() {
    local src="$1" dst="$2"
    sed "s|PROTOTYPE_DIR|${PROTOTYPE_DIR}|g" "${src}" > "${dst}"
}

# Wait for all pods in a namespace to become Ready (or to disappear, e.g. completed jobs).
# Usage: wait_for_namespace_ready <namespace> [timeout_seconds]
wait_for_namespace_ready() {
    local ns="$1" timeout="${2:-300}"
    log "Waiting up to ${timeout}s for pods in namespace ${ns} to be ready"
    kubectl --namespace "${ns}" wait --for=condition=Ready pod --all --timeout="${timeout}s" \
        || { warn "Not all pods in ${ns} became Ready within ${timeout}s"; kubectl --namespace "${ns}" get pods; return 1; }
}
