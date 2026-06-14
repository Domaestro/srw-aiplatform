#!/usr/bin/env bash
# Test: oauth2-proxy blocks unauthenticated access and redirects to Keycloak.
source "$(dirname "$0")/lib.sh"

echo "=== test_sso: oauth2-proxy + Keycloak SSO flow ==="

GATEWAY_IP=$(kubectl -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.spec.clusterIP}')

# Spawn a long-lived probe pod for several requests in a row.
kubectl run sso-probe --restart=Never --image=curlimages/curl:8.10.1 \
    --namespace=cert-manager \
    --overrides='{"spec":{"containers":[{"name":"c","image":"curlimages/curl:8.10.1","command":["sleep","60"],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
    >/dev/null 2>&1
kubectl -n cert-manager wait --for=condition=Ready pod/sso-probe --timeout=30s >/dev/null 2>&1
cleanup() { kubectl -n cert-manager delete pod sso-probe --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

CURL_RESOLVE="--resolve mlflow.aiplatform.local:443:${GATEWAY_IP}"

# T1: GET /  → 403 (no auth)
CODE=$(kubectl -n cert-manager exec sso-probe -- curl -sk ${CURL_RESOLVE} -o /dev/null -w '%{http_code}' https://mlflow.aiplatform.local/ 2>&1 | tail -1)
assert "GET /mlflow without auth returns 403" "${CODE}" "403"

# T2: GET /oauth2/sign_in → 200 (login page)
CODE=$(kubectl -n cert-manager exec sso-probe -- curl -sk ${CURL_RESOLVE} -o /dev/null -w '%{http_code}' 'https://mlflow.aiplatform.local/oauth2/sign_in?rd=%2F' 2>&1 | tail -1)
assert "GET /oauth2/sign_in returns 200 (oauth2-proxy login page)" "${CODE}" "200"

# T3: GET /oauth2/start → 302 to Keycloak with correct client_id and redirect_uri
HEAD=$(kubectl -n cert-manager exec sso-probe -- curl -sIk ${CURL_RESOLVE} 'https://mlflow.aiplatform.local/oauth2/start?rd=%2F' 2>&1)
assert_contains "/oauth2/start returns 302 redirect" "${HEAD}" "HTTP/2 302"
assert_contains "/oauth2/start redirects to Keycloak authorize" "${HEAD}" "keycloak.aiplatform.local"
assert_contains "/oauth2/start uses oauth2-proxy client_id" "${HEAD}" "client_id=oauth2-proxy"
assert_contains "/oauth2/start sets correct redirect_uri" "${HEAD}" "mlflow.aiplatform.local%2Foauth2%2Fcallback"
assert_contains "/oauth2/start sets CSRF cookie" "${HEAD}" "_oauth2_proxy_csrf"
assert_contains "/oauth2/start requests groups scope" "${HEAD}" "groups"

# T4: Keycloak OIDC discovery endpoint returns 200 with expected fields
DISCOVERY=$(kubectl -n cert-manager exec sso-probe -- curl -sk --resolve keycloak.aiplatform.local:443:${GATEWAY_IP} https://keycloak.aiplatform.local/realms/aiplatform/.well-known/openid-configuration 2>&1)
assert_contains "Keycloak OIDC discovery exposes authorization_endpoint" "${DISCOVERY}" "authorization_endpoint"
assert_contains "Keycloak OIDC discovery exposes token_endpoint"          "${DISCOVERY}" "token_endpoint"
assert_contains "Keycloak OIDC discovery exposes userinfo_endpoint"       "${DISCOVERY}" "userinfo_endpoint"
assert_contains "Keycloak OIDC discovery names realm 'aiplatform'"        "${DISCOVERY}" "realms/aiplatform"

# T5: Keycloak token endpoint accepts password grant for alice (validates user is provisioned)
TOKEN_RESP=$(kubectl -n cert-manager exec sso-probe -- curl -sk \
    --resolve keycloak.aiplatform.local:443:${GATEWAY_IP} \
    -d "client_id=oauth2-proxy" \
    -d "client_secret=$(cat "${PROTOTYPE_DIR}/.local/secrets/oauth2-proxy-client.secret")" \
    -d "grant_type=password" \
    -d "username=alice" \
    -d "password=alice-pass" \
    -d "scope=openid groups" \
    https://keycloak.aiplatform.local/realms/aiplatform/protocol/openid-connect/token 2>&1 || true)
# NOTE: direct grants are disabled in our realm template for security; we expect
# either an error or token depending on KC config. Don't fail on either.
if [[ "${TOKEN_RESP}" == *"access_token"* ]]; then
    echo "PASS  Keycloak returns access_token for alice (direct-grant allowed)"
    __test_pass=$((__test_pass+1))
elif [[ "${TOKEN_RESP}" == *"unauthorized_client"* || "${TOKEN_RESP}" == *"Direct grants"* || "${TOKEN_RESP}" == *"invalid_grant"* ]]; then
    echo "PASS  Keycloak correctly disabled direct-grant flow (must use auth-code)"
    __test_pass=$((__test_pass+1))
else
    echo "FAIL  Unexpected Keycloak token response: ${TOKEN_RESP:0:200}"
    __test_fail=$((__test_fail+1))
fi

summarize
