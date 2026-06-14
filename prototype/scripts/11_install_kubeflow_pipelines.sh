#!/usr/bin/env bash
# Install Kubeflow Pipelines (KFP) standalone in the 'kubeflow' namespace.
# Uses the upstream platform-agnostic-emissary overlay, which does not require
# any cloud-specific configuration and runs Argo workflows with the emissary
# executor (no privileged docker.sock access on nodes).
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

KFP_VERSION="${KFP_VERSION:-2.3.0}"

log "Ensuring kubeflow namespace with the right PSA labels"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/namespaces.yaml"

# KFP installs in two phases per upstream recommendation: CRDs first, then the rest.
log "Phase 1: KFP CRDs and cluster-scoped resources"
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${KFP_VERSION}"

log "Waiting for KFP CRDs to be established"
kubectl wait --for=condition=Established \
    crd/applications.app.k8s.io \
    crd/scheduledworkflows.kubeflow.org \
    crd/viewers.kubeflow.org \
    crd/workflows.argoproj.io \
    --timeout=120s

log "Phase 2: KFP namespaced resources (env/platform-agnostic-emissary)"
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=${KFP_VERSION}"

log "Waiting for KFP core deployments (up to 8 minutes)"
for d in mysql minio ml-pipeline ml-pipeline-ui ml-pipeline-persistenceagent \
         ml-pipeline-scheduledworkflow ml-pipeline-viewer-crd \
         ml-pipeline-visualizationserver workflow-controller \
         cache-server metadata-grpc-deployment metadata-writer; do
    log "  waiting for deployment/${d}"
    kubectl --namespace kubeflow rollout status "deployment/${d}" --timeout=480s \
        || warn "deployment ${d} did not become ready in time"
done

log "KFP status:"
kubectl --namespace kubeflow get deploy,statefulset,svc | head -40

log "Done. KFP UI service: ml-pipeline-ui.kubeflow.svc.cluster.local:80"
log "Verify via: kubectl -n kubeflow port-forward svc/ml-pipeline-ui 8081:80"
log "Then open: http://localhost:8081"
