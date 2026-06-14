#!/usr/bin/env bash
# Test: NetworkPolicy default-deny blocks unauthorised traffic;
# explicit allow rules let MLflow reach Postgres and MinIO.
source "$(dirname "$0")/lib.sh"

echo "=== test_networkpolicy: default-deny + explicit allow rules ==="

# Helper: run a probe pod for ~30s in a given ns with a given label, exec curl in it.
spawn_probe() {
    local ns="$1" label="$2" pod_name="np-probe-${RANDOM}"
    kubectl run "${pod_name}" --restart=Never --image=curlimages/curl:8.10.1 \
        --namespace="${ns}" \
        --overrides='{"metadata":{"labels":'"${label}"'},"spec":{"containers":[{"name":"c","image":"curlimages/curl:8.10.1","command":["sleep","60"],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
        >/dev/null 2>&1
    kubectl -n "${ns}" wait --for=condition=Ready "pod/${pod_name}" --timeout=30s >/dev/null 2>&1 || true
    echo "${pod_name}"
}

cleanup_probe() {
    local ns="$1" pod="$2"
    kubectl -n "${ns}" delete pod "${pod}" --wait=false >/dev/null 2>&1 || true
}

# T1: pod in team-demo CANNOT reach Postgres on its own (no allow rule)
PROBE=$(spawn_probe team-demo '{"app":"netpol-test"}')
RESULT=$(kubectl -n team-demo exec "${PROBE}" -- sh -c "timeout 3 nc -zv postgres.mlflow.svc.cluster.local 5432 2>&1 || echo BLOCKED" 2>&1 | tail -1)
assert_contains "team-demo (no special label) cannot reach Postgres" "${RESULT}" "BLOCKED"
cleanup_probe team-demo "${PROBE}"

# T2: pod in cert-manager (which has no policy) CANNOT reach Postgres (mlflow ns has default-deny ingress)
PROBE=$(spawn_probe cert-manager '{"app":"netpol-test"}')
RESULT=$(kubectl -n cert-manager exec "${PROBE}" -- sh -c "timeout 3 nc -zv postgres.mlflow.svc.cluster.local 5432 2>&1 || echo BLOCKED" 2>&1 | tail -1)
assert_contains "cert-manager pod cannot reach Postgres (default-deny on mlflow ingress)" "${RESULT}" "BLOCKED"
cleanup_probe cert-manager "${PROBE}"

# T3: pod with app.kubernetes.io/name=mlflow in mlflow ns CAN reach Postgres
PROBE=$(spawn_probe mlflow '{"app.kubernetes.io/name":"mlflow"}')
RESULT=$(kubectl -n mlflow exec "${PROBE}" -- sh -c "timeout 3 nc -zv postgres 5432 2>&1 | head -1" 2>&1 | tail -1)
assert_contains "mlflow-labelled pod in mlflow ns can reach Postgres" "${RESULT}" "open"
cleanup_probe mlflow "${PROBE}"

# T4: every namespace can do DNS (the allow-dns-egress rule)
PROBE=$(spawn_probe team-demo '{"app":"netpol-dns-test"}')
RESULT=$(kubectl -n team-demo exec "${PROBE}" -- sh -c "nslookup keycloak.aiplatform.local 2>&1 | head -5" 2>&1)
assert_contains "team-demo can resolve *.aiplatform.local via CoreDNS" "${RESULT}" "Address"
cleanup_probe team-demo "${PROBE}"

# T5: team-demo can reach mlflow (allow-team-demo-egress-mlflow) but not directly to postgres
PROBE=$(spawn_probe team-demo '{"app":"netpol-egress-test"}')
RESULT=$(kubectl -n team-demo exec "${PROBE}" -- sh -c "timeout 3 nc -zv mlflow.mlflow.svc.cluster.local 5000 2>&1 | head -1" 2>&1 | tail -1)
assert_contains "team-demo can egress to MLflow:5000 (explicit allow)" "${RESULT}" "open"
cleanup_probe team-demo "${PROBE}"

summarize
