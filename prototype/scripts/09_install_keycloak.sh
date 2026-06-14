#!/usr/bin/env bash
# Install Keycloak 26 in the keycloak namespace.
# Steps:
#   1. Label the keycloak namespace for Istio sidecar injection.
#   2. Generate admin and DB credentials, place them as Secrets.
#   3. Create a 'keycloak' database in the shared in-cluster PostgreSQL.
#   4. Apply NetworkPolicies (must come before the pod so the post-start probes succeed).
#   5. Apply realm ConfigMap, Deployment, Service, VirtualService.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

KEYCLOAK_NS="keycloak"
MLFLOW_NS="mlflow"
SECRETS_DIR="${LOCAL_STATE_DIR}/secrets"
mkdir -p "${SECRETS_DIR}"; chmod 700 "${SECRETS_DIR}"

# ensure_secret_file is now provided by lib.sh (openssl-based, no SIGPIPE risk).

ensure_secret_file "${SECRETS_DIR}/keycloak-admin.pass"
ensure_secret_file "${SECRETS_DIR}/keycloak-db.pass"
ensure_secret_file "${SECRETS_DIR}/oauth2-proxy-client.secret"

log "Labelling namespace ${KEYCLOAK_NS} for Istio sidecar injection"
kubectl label namespace "${KEYCLOAK_NS}" istio-injection=enabled --overwrite

log "Creating admin and DB credential Secrets"
kubectl create secret generic keycloak-admin \
    --namespace "${KEYCLOAK_NS}" \
    --from-literal=username=admin \
    --from-literal=password="$(cat "${SECRETS_DIR}/keycloak-admin.pass")" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic keycloak-db-credentials \
    --namespace "${KEYCLOAK_NS}" \
    --from-literal=username=keycloak \
    --from-literal=password="$(cat "${SECRETS_DIR}/keycloak-db.pass")" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create the 'keycloak' database and role inside the shared PostgreSQL.
log "Bootstrapping 'keycloak' database in the shared PostgreSQL"
PG_PASS=$(kubectl -n "${MLFLOW_NS}" get secret mlflow-postgres-credentials -o jsonpath='{.data.password}' | base64 -d)
KC_DB_PASS=$(cat "${SECRETS_DIR}/keycloak-db.pass")

# psql works from within the postgres pod itself; the in-cluster admin role is 'mlflow'
# (created as the POSTGRES_USER by the postgresql Deployment).
# Two-step idempotent provisioning: try CREATE ROLE; if it fails (role exists), do ALTER ROLE.
if ! kubectl -n "${MLFLOW_NS}" exec deploy/postgres -- env PGPASSWORD="${PG_PASS}" \
        psql -U mlflow -d mlflow -c "CREATE ROLE keycloak LOGIN PASSWORD '${KC_DB_PASS}';" >/dev/null 2>&1; then
    kubectl -n "${MLFLOW_NS}" exec deploy/postgres -- env PGPASSWORD="${PG_PASS}" \
        psql -U mlflow -d mlflow -c "ALTER ROLE keycloak WITH LOGIN PASSWORD '${KC_DB_PASS}';"
fi

# CREATE DATABASE cannot run inside a transaction block and must be conditional.
DB_EXISTS=$(kubectl -n "${MLFLOW_NS}" exec deploy/postgres -- env PGPASSWORD="${PG_PASS}" \
    psql -U mlflow -d mlflow -tAc "SELECT 1 FROM pg_database WHERE datname='keycloak'" 2>/dev/null || true)
if [[ "${DB_EXISTS}" != "1" ]]; then
    kubectl -n "${MLFLOW_NS}" exec deploy/postgres -- env PGPASSWORD="${PG_PASS}" \
        psql -U mlflow -d mlflow -c "CREATE DATABASE keycloak OWNER keycloak;"
fi

log "Applying NetworkPolicies"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/security/keycloak-netpol.yaml"

log "Applying realm template, Deployment, Service, VirtualService"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/keycloak-realm.yaml"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/keycloak.yaml"
kubectl apply -f "${PROTOTYPE_DIR}/k8s/base/keycloak-virtualservice.yaml"

log "Waiting for Keycloak rollout"
kubectl --namespace "${KEYCLOAK_NS}" rollout status deployment/keycloak --timeout=300s

log "Replacing placeholder client secret on the imported realm"
ADMIN_USER=$(kubectl -n "${KEYCLOAK_NS}" get secret keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASS=$(kubectl -n "${KEYCLOAK_NS}" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
OAUTH2_SECRET=$(cat "${SECRETS_DIR}/oauth2-proxy-client.secret")

# Use kcadm.sh on the pod itself to rotate the oauth2-proxy client secret.
kubectl -n "${KEYCLOAK_NS}" exec deploy/keycloak -c keycloak -- /opt/keycloak/bin/kcadm.sh \
    config credentials --server http://localhost:8080 --realm master \
    --user "${ADMIN_USER}" --password "${ADMIN_PASS}"

CLIENT_ID_INTERNAL=$(kubectl -n "${KEYCLOAK_NS}" exec deploy/keycloak -c keycloak -- /opt/keycloak/bin/kcadm.sh \
    get clients -r aiplatform --query "clientId=oauth2-proxy" --fields id --format csv --noquotes 2>/dev/null | tail -n1)

kubectl -n "${KEYCLOAK_NS}" exec deploy/keycloak -c keycloak -- /opt/keycloak/bin/kcadm.sh \
    update clients/"${CLIENT_ID_INTERNAL}" -r aiplatform \
    -s "secret=${OAUTH2_SECRET}"

log "Done. Keycloak realm 'aiplatform' provisioned with 3 users and OAuth2 client."
log "Admin URL (via /etc/hosts entry):   https://keycloak.aiplatform.local"
log "Admin credentials:                  ${ADMIN_USER} / (see ${SECRETS_DIR}/keycloak-admin.pass)"
log "Test users (each gets the same password as the username):"
log "  alice / alice-pass  -> role project-admin"
log "  bob   / bob-pass    -> role ml-engineer"
log "  eve   / eve-pass    -> role viewer"
log "OAuth2-proxy client secret:         (see ${SECRETS_DIR}/oauth2-proxy-client.secret)"
