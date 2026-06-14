#!/usr/bin/env bash
# Install Istio service mesh:
#  - istio-system  : base CRDs + istiod control plane
#  - istio-ingress : ingress gateway listening on host ports 8080/8443 (via k3d serverlb)
# Idempotent: re-applying upgrades each chart in place.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

ISTIO_VERSION="${ISTIO_VERSION:-1.24.6}"

log "Adding/updating Istio helm repo"
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update istio >/dev/null 2>&1 || true

log "Ensuring namespaces istio-system, istio-ingress"
kubectl get ns istio-system >/dev/null 2>&1 \
    || kubectl create namespace istio-system

# istio-ingress is created by the gateway chart; label the namespace so PSA stays sane.
if ! kubectl get ns istio-ingress >/dev/null 2>&1; then
    kubectl create namespace istio-ingress
fi
# Ingress gateway needs to bind to ports — keep at 'baseline'.
kubectl label namespace istio-ingress \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite

log "Installing istio/base ${ISTIO_VERSION} (CRDs)"
helm upgrade --install istio-base istio/base \
    --namespace istio-system \
    --version "${ISTIO_VERSION}" \
    --wait --timeout 3m

log "Installing istio/cni ${ISTIO_VERSION} (replaces per-pod NET_ADMIN initContainer)"
helm upgrade --install istio-cni istio/cni \
    --namespace istio-system \
    --version "${ISTIO_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/istio-cni-values.yaml" \
    --wait --timeout 3m

log "Installing istio/istiod ${ISTIO_VERSION} (control plane)"
helm upgrade --install istiod istio/istiod \
    --namespace istio-system \
    --version "${ISTIO_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/istiod-values.yaml" \
    --wait --timeout 5m

log "Installing istio/gateway ${ISTIO_VERSION} (ingress)"
helm upgrade --install istio-ingressgateway istio/gateway \
    --namespace istio-ingress \
    --version "${ISTIO_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/istio-gateway-values.yaml" \
    --wait --timeout 3m

log "Status:"
kubectl -n istio-system get pods
kubectl -n istio-ingress get pods,svc
