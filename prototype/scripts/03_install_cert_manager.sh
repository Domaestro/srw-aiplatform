#!/usr/bin/env bash
# Install cert-manager and provision a self-signed cluster-wide CA.
# Idempotent: re-running upgrades the release in place.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"
CERT_MANAGER_NS="cert-manager"

log "Ensuring namespace ${CERT_MANAGER_NS}"
kubectl get ns "${CERT_MANAGER_NS}" >/dev/null 2>&1 \
    || kubectl create namespace "${CERT_MANAGER_NS}"

log "Adding/updating Helm repo jetstack"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update jetstack >/dev/null

log "Installing/upgrading cert-manager ${CERT_MANAGER_VERSION}"
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace "${CERT_MANAGER_NS}" \
    --version "${CERT_MANAGER_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/cert-manager-values.yaml" \
    --wait --timeout 5m

log "Waiting for cert-manager pods to become ready"
kubectl --namespace "${CERT_MANAGER_NS}" wait --for=condition=Available \
    deployment/cert-manager deployment/cert-manager-webhook deployment/cert-manager-cainjector \
    --timeout=300s

log "Applying cluster-wide self-signed CA"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/cluster-ca.yaml"

log "Waiting for root CA certificate to be issued"
kubectl --namespace "${CERT_MANAGER_NS}" wait --for=condition=Ready \
    certificate/aiplatform-root-ca --timeout=120s

log "Verifying ClusterIssuer aiplatform-ca is Ready"
kubectl wait --for=condition=Ready clusterissuer/aiplatform-ca --timeout=60s

log "cert-manager installed. Root CA secret: cert-manager/aiplatform-root-ca"
log "To trust the CA on the host:"
log "  kubectl -n cert-manager get secret aiplatform-root-ca -o jsonpath='{.data.ca\\.crt}' | base64 -d > /tmp/aiplatform-ca.crt"
log "  sudo cp /tmp/aiplatform-ca.crt /usr/local/share/ca-certificates/aiplatform-root-ca.crt && sudo update-ca-certificates"
