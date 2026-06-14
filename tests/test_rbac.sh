#!/usr/bin/env bash
# Test: RBAC ClusterRole templates grant only minimal expected permissions.
source "$(dirname "$0")/lib.sh"

echo "=== test_rbac: tenant ServiceAccounts have minimum-required permissions ==="

# viewer: read but no write
assert "viewer cannot create pods" \
    "$(kubectl auth can-i create pods --as=system:serviceaccount:team-demo:demo-viewer -n team-demo 2>/dev/null)" \
    "no"

assert "viewer cannot delete rolebindings" \
    "$(kubectl auth can-i delete rolebindings --as=system:serviceaccount:team-demo:demo-viewer -n team-demo 2>/dev/null)" \
    "no"

assert "viewer can list pods" \
    "$(kubectl auth can-i list pods --as=system:serviceaccount:team-demo:demo-viewer -n team-demo 2>/dev/null)" \
    "yes"

# ml-engineer: workload create, no RBAC escalation, secret READ ok
assert "ml-engineer can create pods" \
    "$(kubectl auth can-i create pods --as=system:serviceaccount:team-demo:demo-ml -n team-demo 2>/dev/null)" \
    "yes"

assert "ml-engineer can create jobs" \
    "$(kubectl auth can-i create jobs --as=system:serviceaccount:team-demo:demo-ml -n team-demo 2>/dev/null)" \
    "yes"

assert "ml-engineer cannot create rolebindings" \
    "$(kubectl auth can-i create rolebindings --as=system:serviceaccount:team-demo:demo-ml -n team-demo 2>/dev/null)" \
    "no"

assert "ml-engineer cannot create secrets (read-only access)" \
    "$(kubectl auth can-i create secrets --as=system:serviceaccount:team-demo:demo-ml -n team-demo 2>/dev/null)" \
    "no"

assert "ml-engineer can read secrets" \
    "$(kubectl auth can-i get secrets --as=system:serviceaccount:team-demo:demo-ml -n team-demo 2>/dev/null)" \
    "yes"

# project-admin: full namespace control
assert "project-admin can create rolebindings" \
    "$(kubectl auth can-i create rolebindings --as=system:serviceaccount:team-demo:demo-admin -n team-demo 2>/dev/null)" \
    "yes"

assert "project-admin can delete rolebindings" \
    "$(kubectl auth can-i delete rolebindings --as=system:serviceaccount:team-demo:demo-admin -n team-demo 2>/dev/null)" \
    "yes"

# Cross-namespace: none of demo accounts can touch other namespaces
assert "viewer cannot list pods in mlflow ns" \
    "$(kubectl auth can-i list pods --as=system:serviceaccount:team-demo:demo-viewer -n mlflow 2>/dev/null)" \
    "no"

assert "ml-engineer cannot create pods in mlflow ns" \
    "$(kubectl auth can-i create pods --as=system:serviceaccount:team-demo:demo-ml -n mlflow 2>/dev/null)" \
    "no"

assert "project-admin cannot delete namespaces (cluster-scope)" \
    "$(kubectl auth can-i delete namespaces --as=system:serviceaccount:team-demo:demo-admin 2>/dev/null)" \
    "no"

summarize
