#!/usr/bin/env bash
# Install oauth2-proxy in front of MLflow.
# - Reads the oauth2-proxy client secret previously rotated in Keycloak.
# - Generates a random 32-byte cookie secret (required by oauth2-proxy).
# - Mirrors the platform CA so oauth2-proxy can validate Keycloak's TLS.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

MLFLOW_NS="mlflow"
CHART_VERSION="${OAUTH2_PROXY_CHART_VERSION:-10.4.3}"

SECRETS_DIR="${LOCAL_STATE_DIR}/secrets"
mkdir -p "${SECRETS_DIR}"; chmod 700 "${SECRETS_DIR}"

# Cookie secret must be exactly 16, 24 or 32 bytes for AES-encrypted session cookies.
COOKIE_FILE="${SECRETS_DIR}/oauth2-proxy-cookie.secret"
if [[ ! -s "${COOKIE_FILE}" ]]; then
    # 32 base64-encoded bytes -> meets oauth2-proxy "32 bytes" requirement.
    openssl rand -base64 32 | tr -d '\n' > "${COOKIE_FILE}"
    chmod 600 "${COOKIE_FILE}"
fi

CLIENT_SECRET="$(cat "${SECRETS_DIR}/oauth2-proxy-client.secret")"
COOKIE_SECRET="$(cat "${COOKIE_FILE}")"

log "Creating oauth2-proxy credentials Secret in ns=${MLFLOW_NS}"
kubectl create secret generic oauth2-proxy-credentials \
    --namespace "${MLFLOW_NS}" \
    --from-literal=client-id="oauth2-proxy" \
    --from-literal=client-secret="${CLIENT_SECRET}" \
    --from-literal=cookie-secret="${COOKIE_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Adding/updating oauth2-proxy helm repo"
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests >/dev/null 2>&1 || true
helm repo update oauth2-proxy >/dev/null 2>&1 || true

log "Installing/upgrading oauth2-proxy chart ${CHART_VERSION}"
helm upgrade --install oauth2-proxy oauth2-proxy/oauth2-proxy \
    --namespace "${MLFLOW_NS}" \
    --version "${CHART_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/oauth2-proxy-values.yaml" \
    --wait --timeout 3m

log "Applying NetworkPolicies for oauth2-proxy"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/oauth2-proxy-netpol.yaml"

log "Applying VirtualService for mlflow.aiplatform.local"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/mlflow-virtualservice.yaml"

log "Status:"
kubectl --namespace "${MLFLOW_NS}" get pods -l app.kubernetes.io/name=oauth2-proxy
kubectl --namespace "${MLFLOW_NS}" get virtualservice,svc -l app.kubernetes.io/name=oauth2-proxy 2>/dev/null || true
kubectl --namespace "${MLFLOW_NS}" get virtualservice

log "Done. Open https://mlflow.aiplatform.local through the Istio gateway."
log "You will be redirected to Keycloak for login (alice/bob/eve)."
