#!/usr/bin/env bash
# Provision a least-privilege MinIO user 'mlflow-svc' with read/write access only to
# the 'mlflow-artifacts' bucket, then mirror the credentials into the mlflow namespace
# along with the platform CA certificate so MLflow can verify TLS against MinIO.
#
# Idempotent: running multiple times keeps the same access key, refreshes the secret
# key, and re-applies the policy attachment.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

MINIO_NS="minio"
MLFLOW_NS="mlflow"
MLFLOW_ACCESS_KEY="mlflow-svc"
SECRETS_DIR="${LOCAL_STATE_DIR}/secrets"

ensure_secret_file() {
    local f="$1"
    if [[ ! -s "${f}" ]]; then
        tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32 > "${f}"
        chmod 600 "${f}"
    fi
}

ensure_secret_file "${SECRETS_DIR}/minio-mlflow.pass"
MLFLOW_SECRET_KEY="$(cat "${SECRETS_DIR}/minio-mlflow.pass")"

ROOT_USER=$(kubectl -n "${MINIO_NS}" get secret minio-root-credentials -o jsonpath='{.data.rootUser}' | base64 -d)
ROOT_PASS=$(kubectl -n "${MINIO_NS}" get secret minio-root-credentials -o jsonpath='{.data.rootPassword}' | base64 -d)

log "Provisioning MinIO user '${MLFLOW_ACCESS_KEY}' with bucket-scoped policy mlflow-rw"
# The 'mc' commands are wrapped without 'set -e' so that idempotent operations
# (re-creating an existing user, re-creating an existing policy) can return
# non-zero without aborting the whole script.
kubectl -n "${MINIO_NS}" exec deploy/minio -- /bin/sh <<EOF
export MC_INSECURE=1
mc alias set local https://localhost:9000 '${ROOT_USER}' '${ROOT_PASS}' --insecure >/dev/null

# Drop the user if it exists so we can rotate the secret key cleanly.
mc admin user remove local '${MLFLOW_ACCESS_KEY}' --insecure >/dev/null 2>&1 || true
mc admin user add local '${MLFLOW_ACCESS_KEY}' '${MLFLOW_SECRET_KEY}' --insecure

cat > /tmp/mlflow-policy.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::mlflow-artifacts"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"
      ],
      "Resource": ["arn:aws:s3:::mlflow-artifacts/*"]
    }
  ]
}
POLICY

# 'mc admin policy create' fails if the policy exists; suppress and fall through.
mc admin policy create local mlflow-rw /tmp/mlflow-policy.json --insecure 2>/dev/null \
    || mc admin policy update local mlflow-rw /tmp/mlflow-policy.json --insecure
mc admin policy attach local mlflow-rw --user '${MLFLOW_ACCESS_KEY}' --insecure 2>/dev/null || true

echo "OK"
EOF

log "Mirroring credentials into namespace ${MLFLOW_NS} as Secret 'mlflow-s3-credentials'"
kubectl create secret generic mlflow-s3-credentials \
    --namespace "${MLFLOW_NS}" \
    --from-literal=AWS_ACCESS_KEY_ID="${MLFLOW_ACCESS_KEY}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${MLFLOW_SECRET_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Copying platform CA into namespace ${MLFLOW_NS} as Secret 'aiplatform-ca'"
CA_CRT=$(kubectl -n cert-manager get secret aiplatform-root-ca -o jsonpath='{.data.ca\.crt}')
kubectl create secret generic aiplatform-ca \
    --namespace "${MLFLOW_NS}" \
    --from-literal=ca.crt="$(echo "${CA_CRT}" | base64 -d)" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Done. User '${MLFLOW_ACCESS_KEY}' bound to policy 'mlflow-rw' on bucket 'mlflow-artifacts'."
