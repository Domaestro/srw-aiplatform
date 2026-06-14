#!/usr/bin/env bash
# Tear down the prototype cluster.
# Safe to run repeatedly; if the cluster does not exist, exits 0.
source "$(dirname "$0")/lib.sh"

require_cmd k3d

if k3d cluster list | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
    log "Deleting k3d cluster '${CLUSTER_NAME}'"
    k3d cluster delete "${CLUSTER_NAME}"
else
    log "Cluster '${CLUSTER_NAME}' does not exist. Nothing to do."
fi

log "Teardown complete."
