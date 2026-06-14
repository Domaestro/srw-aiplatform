#!/usr/bin/env bash
# Install Kubeflow Training Operator (v1, PyTorchJob/TFJob/MPIJob/XGBoostJob CRDs).
# Manifests come from the kubeflow/manifests repo cloned in Iter 5a; images are
# pinned to ghcr.io/kubeflow/training-v1/* (publicly available).
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

KF_MANIFESTS_DIR="${LOCAL_STATE_DIR}/kubeflow-manifests"
KFW_NS="kubeflow"

if [[ ! -d "${KF_MANIFESTS_DIR}" ]]; then
    err "kubeflow/manifests not cloned. Expected at ${KF_MANIFESTS_DIR}"
    exit 1
fi

log "Applying training-operator kustomize overlay"
kubectl kustomize "${KF_MANIFESTS_DIR}/applications/training-operator/upstream/overlays/kubeflow" \
    | kubectl apply --server-side --force-conflicts -f -

log "Waiting for training-operator deployment to become ready"
kubectl --namespace "${KFW_NS}" rollout status deployment/training-operator --timeout=180s

log "Training Operator status:"
kubectl --namespace "${KFW_NS}" get pods,deploy -l control-plane=kubeflow-training-operator
echo
log "Installed CRDs:"
kubectl get crd | grep -E "(pytorchjob|tfjob|mxjob|xgboostjob|mpijob)\.kubeflow\.org" || warn "No training CRDs found"
