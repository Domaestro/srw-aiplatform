#!/usr/bin/env bash
# Install Argo Workflows in the kubeflow namespace.
# This is the orchestration engine that underpins Kubeflow Pipelines; here we use
# it directly as our pipeline runner.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl
require_cmd helm

KFW_NS="kubeflow"
CHART_VERSION="${ARGO_WORKFLOWS_CHART_VERSION:-1.0.14}"

log "Ensuring kubeflow namespace exists with correct labels"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/namespaces.yaml"

log "Adding/updating argo helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null 2>&1 || true

log "Installing/upgrading argo-workflows chart ${CHART_VERSION}"
helm upgrade --install argo-workflows argo/argo-workflows \
    --namespace "${KFW_NS}" \
    --version "${CHART_VERSION}" \
    --values "${PROTOTYPE_DIR}/charts/argo-workflows-values.yaml" \
    --wait --timeout 5m

log "Status:"
kubectl --namespace "${KFW_NS}" get pods -l app.kubernetes.io/name=argo-workflows-server,app.kubernetes.io/name=argo-workflows-workflow-controller
kubectl --namespace "${KFW_NS}" get deploy

log "Done. Argo Workflows server: argo-workflows-server.kubeflow.svc.cluster.local:2746"
log "UI port-forward: kubectl -n kubeflow port-forward svc/argo-workflows-server 2746:2746"
