#!/usr/bin/env bash
# Test: end-to-end Argo Workflow logs an experiment to MLflow with artifact in MinIO.
source "$(dirname "$0")/lib.sh"

echo "=== test_mlflow_e2e: Argo Workflow → MLflow → MinIO end-to-end ==="

# Clean up any stale runs from previous test executions.
kubectl -n team-demo delete workflow --all --wait=false >/dev/null 2>&1 || true
sleep 2

# Submit demo workflow and wait for completion.
kubectl create -f "${PROTOTYPE_DIR}/pipelines/demo_argo_workflow.yaml" >/dev/null 2>&1
sleep 3
WF=$(kubectl -n team-demo get workflow -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

PHASE=""
for i in {1..30}; do
    PHASE=$(kubectl -n team-demo get workflow "${WF}" -o jsonpath='{.status.phase}' 2>/dev/null)
    [[ "${PHASE}" == "Succeeded" || "${PHASE}" == "Failed" || "${PHASE}" == "Error" ]] && break
    sleep 10
done

assert "Argo Workflow completes successfully" "${PHASE}" "Succeeded"

# Probe MLflow for the resulting experiment.
kubectl run mlflow-probe --restart=Never --image=curlimages/curl:8.10.1 \
    --namespace=mlflow \
    --overrides='{"metadata":{"labels":{"app.kubernetes.io/name":"mlflow"}},"spec":{"containers":[{"name":"c","image":"curlimages/curl:8.10.1","command":["sleep","30"],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
    >/dev/null 2>&1
kubectl -n mlflow wait --for=condition=Ready pod/mlflow-probe --timeout=30s >/dev/null 2>&1

EXP_JSON=$(kubectl -n mlflow exec mlflow-probe -- curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"max_results":10}' \
    http://mlflow.mlflow.svc.cluster.local:5000/api/2.0/mlflow/experiments/search 2>&1)

assert_contains "MLflow has experiment 'argo-demo'" "${EXP_JSON}" 'argo-demo'

# Extract the experiment_id and search runs.
EXP_ID=$(echo "${EXP_JSON}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for e in d.get('experiments', []):
    if e['name'] == 'argo-demo':
        print(e['experiment_id'])
        break
" 2>/dev/null)

if [[ -n "${EXP_ID}" ]]; then
    RUNS_JSON=$(kubectl -n mlflow exec mlflow-probe -- curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"experiment_ids\":[\"${EXP_ID}\"], \"max_results\": 5}" \
        http://mlflow.mlflow.svc.cluster.local:5000/api/2.0/mlflow/runs/search 2>&1)
    assert_contains "MLflow has at least one Finished run in argo-demo" "${RUNS_JSON}" 'FINISHED'
    assert_contains "MLflow run has rmse metric"                          "${RUNS_JSON}" 'rmse'
    assert_contains "MLflow run has source=argo-workflow param"           "${RUNS_JSON}" 'argo-workflow'
else
    echo "FAIL  Could not extract argo-demo experiment_id from MLflow"
    __test_fail=$((__test_fail+1))
fi

kubectl -n mlflow delete pod mlflow-probe --wait=false >/dev/null 2>&1 || true

# Verify the artifact is actually in MinIO bucket.
ROOT_USER=$(kubectl -n minio get secret minio-root-credentials -o jsonpath='{.data.rootUser}' | base64 -d)
ROOT_PASS=$(kubectl -n minio get secret minio-root-credentials -o jsonpath='{.data.rootPassword}' | base64 -d)
BUCKET_LIST=$(kubectl -n minio exec deploy/minio -- /bin/sh -c "
export MC_INSECURE=1
mc alias set local https://localhost:9000 '${ROOT_USER}' '${ROOT_PASS}' --insecure >/dev/null 2>&1
mc ls --recursive local/mlflow-artifacts --insecure 2>&1 | head -20
" 2>&1)
assert_contains "MinIO bucket mlflow-artifacts contains experiment artifacts" "${BUCKET_LIST}" "artifacts"

summarize
