#!/usr/bin/env bash
# Install kube-prometheus-stack (Prometheus + Grafana + node-exporter + kube-state-metrics)
# in the 'monitoring' namespace.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

MON_NS="monitoring"
CHART_VERSION="${KPS_CHART_VERSION:-85.2.1}"
SECRETS_DIR="${LOCAL_STATE_DIR}/secrets"
mkdir -p "${SECRETS_DIR}"; chmod 700 "${SECRETS_DIR}"

ensure_secret_file "${SECRETS_DIR}/grafana-admin.pass"

log "Ensuring namespace ${MON_NS}"
kubectl get ns "${MON_NS}" >/dev/null 2>&1 || kubectl create namespace "${MON_NS}"
# Keep this namespace under 'baseline' PSA: kube-prometheus-stack ships a few
# components (node-exporter DaemonSet) that need host network / host PID access.
kubectl label namespace "${MON_NS}" \
    aiplatform.local/role=system \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite

log "Creating Grafana admin Secret"
kubectl create secret generic grafana-admin \
    --namespace "${MON_NS}" \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(cat "${SECRETS_DIR}/grafana-admin.pass")" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Adding/updating prometheus-community helm repo"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null 2>&1 || true

log "Installing/upgrading kube-prometheus-stack ${CHART_VERSION} (this can take ~5 minutes)"
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
    --namespace "${MON_NS}" \
    --version "${CHART_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/kube-prometheus-stack-values.yaml" \
    --wait --timeout 10m

log "Status:"
kubectl --namespace "${MON_NS}" get pods,deploy,statefulset,daemonset
echo
log "Grafana admin password persisted at: ${SECRETS_DIR}/grafana-admin.pass"
log "Port-forward to UIs:"
log "  Prometheus: kubectl -n ${MON_NS} port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090"
log "  Grafana:    kubectl -n ${MON_NS} port-forward svc/kps-grafana 3000:80"
