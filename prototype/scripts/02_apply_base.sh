#!/usr/bin/env bash
# Apply baseline platform manifests:
# - namespaces with PSA labels
# - per-tenant ResourceQuota and LimitRange
# - default-deny NetworkPolicy + DNS egress allowance
# - cluster-wide RBAC role templates and demo bindings
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

log "Applying base namespaces"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/namespaces.yaml"

log "Applying tenant ResourceQuota / LimitRange"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/tenant-resources.yaml"

log "Applying NetworkPolicy default-deny"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/networkpolicies.yaml"

log "Applying RBAC role templates and demo bindings"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/rbac-roles.yaml"

log "Verifying applied resources:"
kubectl get ns -l aiplatform.local/role
kubectl --namespace team-demo get resourcequota,limitrange,networkpolicy,rolebinding
kubectl get clusterrole -l 'aiplatform.local/role-template'

log "Baseline manifests applied."
