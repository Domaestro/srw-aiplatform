#!/usr/bin/env bash
# Install host-level prerequisites: k3d, helm.
# Idempotent: re-running on an already-prepared host is a no-op.
source "$(dirname "$0")/lib.sh"

K3D_VERSION="${K3D_VERSION:-v5.7.4}"
HELM_VERSION="${HELM_VERSION:-v3.16.3}"

install_k3d() {
    if command -v k3d >/dev/null 2>&1; then
        log "k3d already installed: $(k3d version | head -n1)"
        return 0
    fi
    log "Installing k3d ${K3D_VERSION}"
    curl -fsSL "https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh" \
        | TAG="${K3D_VERSION}" bash
}

install_helm() {
    if command -v helm >/dev/null 2>&1; then
        log "helm already installed: $(helm version --short)"
        return 0
    fi
    log "Installing helm ${HELM_VERSION}"
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz
    tar -xzf /tmp/helm.tar.gz -C /tmp
    sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
}

require_cmd docker
require_cmd curl
require_cmd kubectl

install_k3d
install_helm

log "Prerequisites installed."
