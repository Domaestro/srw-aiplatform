#!/usr/bin/env bash
# Install MLflow Tracking Server connected to PostgreSQL (backend) and MinIO (artifacts).
# Prerequisites:
#   - PostgreSQL deployed in ns 'mlflow' (Iter 2.3)
#   - MinIO running and bucket 'mlflow-artifacts' exists (Iter 2.2)
#   - Secrets in ns 'mlflow': mlflow-postgres-credentials, mlflow-s3-credentials,
#     aiplatform-ca (set up by 05/06 scripts)
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

MLFLOW_NS="mlflow"
MLFLOW_CHART_VERSION="${MLFLOW_CHART_VERSION:-1.8.1}"

log "Applying NetworkPolicies for MLflow"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/mlflow-netpol.yaml"

log "Adding/updating community-charts helm repo"
helm repo add community-charts https://community-charts.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update community-charts >/dev/null 2>&1 || true

# Pull DB credentials from the in-cluster Secret so the version-controlled values.yaml
# stays free of secrets. They will end up in the helm release Secret (Opaque) only.
PG_USER=$(kubectl -n "${MLFLOW_NS}" get secret mlflow-postgres-credentials -o jsonpath='{.data.username}' | base64 -d)
PG_PASS=$(kubectl -n "${MLFLOW_NS}" get secret mlflow-postgres-credentials -o jsonpath='{.data.password}' | base64 -d)

log "Installing/upgrading MLflow chart ${MLFLOW_CHART_VERSION}"
helm upgrade --install mlflow community-charts/mlflow \
    --namespace "${MLFLOW_NS}" \
    --version "${MLFLOW_CHART_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/mlflow-values.yaml" \
    --set-string "backendStore.postgres.user=${PG_USER}" \
    --set-string "backendStore.postgres.password=${PG_PASS}" \
    --wait --timeout 5m

log "MLflow status:"
kubectl --namespace "${MLFLOW_NS}" get deploy,pod,svc -l app.kubernetes.io/name=mlflow

log "Cluster-internal endpoint: http://mlflow.mlflow.svc.cluster.local:5000"
log "To reach MLflow UI from the host: kubectl -n mlflow port-forward svc/mlflow 5000:5000"
