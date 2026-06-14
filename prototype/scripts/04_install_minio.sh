#!/usr/bin/env bash
# Install MinIO standalone (official chart minio/minio) with TLS and three default buckets.
#
# Credentials:
#   - root password is generated locally on first run, persisted under .local/secrets/
#     and re-used on subsequent runs (idempotent).
#   - service users with bucket-scoped policies are provisioned in Iter 3, when MLflow
#     actually consumes them.
#
# TLS:
#   - leaf certificate is issued by cert-manager, ClusterIssuer 'aiplatform-ca'.
#   - the same Secret 'minio-tls' is used both as the server cert and as the trust
#     bundle for the embedded mc client (see trustedCertsSecret in values).
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

MINIO_NS="minio"
MINIO_CHART_VERSION="${MINIO_CHART_VERSION:-5.4.0}"

SECRETS_DIR="${LOCAL_STATE_DIR}/secrets"
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

ensure_secret_file() {
    local f="$1"
    if [[ ! -s "${f}" ]]; then
        tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32 > "${f}"
        chmod 600 "${f}"
    fi
}

ensure_secret_file "${SECRETS_DIR}/minio-root.pass"

log "Issuing TLS certificate for MinIO (ClusterIssuer aiplatform-ca)"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/minio-cert.yaml"
kubectl --namespace "${MINIO_NS}" wait --for=condition=Ready certificate/minio-tls --timeout=120s

# Official chart expects keys named exactly 'rootUser' and 'rootPassword'.
log "Creating/updating root credentials Secret in ns=${MINIO_NS}"
kubectl create secret generic minio-root-credentials \
    --namespace "${MINIO_NS}" \
    --from-literal=rootUser="aiplatform-root" \
    --from-literal=rootPassword="$(cat "${SECRETS_DIR}/minio-root.pass")" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Applying NetworkPolicy BEFORE helm install (chart post-job needs egress to MinIO)"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/minio-netpol.yaml"

log "Adding/updating MinIO helm repo"
helm repo add minio https://charts.min.io/ >/dev/null 2>&1 || true
helm repo update minio >/dev/null 2>&1 || true

log "Installing/upgrading MinIO chart minio/minio version ${MINIO_CHART_VERSION}"
helm upgrade --install minio minio/minio \
    --namespace "${MINIO_NS}" \
    --version "${MINIO_CHART_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/minio-values.yaml" \
    --wait --timeout 5m

log "MinIO deployment status:"
kubectl --namespace "${MINIO_NS}" get pods,svc,certificate
echo
log "Default buckets: mlflow-artifacts, kubeflow-pipelines, model-registry"
log "Root credentials: aiplatform-root / <see ${SECRETS_DIR}/minio-root.pass>"
log "Internal endpoint: https://minio.minio.svc.cluster.local:9000"
