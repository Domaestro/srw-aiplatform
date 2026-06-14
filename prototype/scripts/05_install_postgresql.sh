#!/usr/bin/env bash
# Deploy PostgreSQL 16 in the mlflow namespace as MLflow's backend store.
# - Random password generated on first run, persisted under .local/secrets/.
# - PSA restricted-compatible securityContext (non-root, no priv escalation,
#   capabilities dropped, RuntimeDefault seccomp).
# - NetworkPolicy: only pods labelled app=mlflow may reach :5432.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

MLFLOW_NS="mlflow"
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

ensure_secret_file "${SECRETS_DIR}/mlflow-postgres.pass"

log "Creating/updating PostgreSQL credentials Secret"
kubectl create secret generic mlflow-postgres-credentials \
    --namespace "${MLFLOW_NS}" \
    --from-literal=username=mlflow \
    --from-literal=password="$(cat "${SECRETS_DIR}/mlflow-postgres.pass")" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Applying NetworkPolicy (mlflow -> postgres)"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/postgres-netpol.yaml"

log "Applying PostgreSQL manifests"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/postgresql.yaml"

log "Waiting for PostgreSQL pod to become Ready"
kubectl --namespace "${MLFLOW_NS}" rollout status deployment/postgres --timeout=180s

log "PostgreSQL status:"
kubectl --namespace "${MLFLOW_NS}" get deployment,pod,svc,pvc -l app=postgres
log "PostgreSQL DSN: postgresql://mlflow:<see ${SECRETS_DIR}/mlflow-postgres.pass>@postgres.mlflow.svc.cluster.local:5432/mlflow"
