#!/usr/bin/env bash
# Bring up the k3d cluster according to k3d/cluster.yaml.
# - Renders cluster.yaml with absolute paths.
# - Creates the cluster if it does not yet exist.
# - Labels worker nodes for system / ml-cpu workloads (matching the reference architecture).
source "$(dirname "$0")/lib.sh"

require_cmd k3d
require_cmd kubectl

RENDERED_CFG="${LOCAL_STATE_DIR}/cluster.rendered.yaml"
render_manifest "${PROTOTYPE_DIR}/k3d/cluster.yaml" "${RENDERED_CFG}"

# Ensure mount points exist on host before k3d starts mounting them.
mkdir -p "${LOCAL_STATE_DIR}/audit-log"

if k3d cluster list | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
    log "Cluster '${CLUSTER_NAME}' already exists. Skipping create."
else
    log "Creating k3d cluster '${CLUSTER_NAME}'"
    k3d cluster create --config "${RENDERED_CFG}"
fi

log "Switching kubectl context to k3d-${CLUSTER_NAME}"
kubectl config use-context "k3d-${CLUSTER_NAME}"

log "Waiting for the cluster to become ready"
kubectl wait --for=condition=Ready node --all --timeout=180s

# Label worker nodes by role. The cluster has agents named k3d-aiplatform-agent-{0,1}.
# Node 0 -> system (Istio, Keycloak, monitoring); Node 1 -> ml-cpu (notebooks, training)
log "Labelling worker nodes (system / ml-cpu)"
kubectl label node "k3d-${CLUSTER_NAME}-agent-0" node-role.aiplatform/system=true --overwrite
kubectl label node "k3d-${CLUSTER_NAME}-agent-1" node-role.aiplatform/ml-cpu=true --overwrite

log "Cluster nodes:"
kubectl get nodes -o wide --show-labels=false
log "Cluster is ready."
