#!/usr/bin/env bash
# Test: every web-facing service is served over TLS with a cert signed by aiplatform-ca.
source "$(dirname "$0")/lib.sh"

echo "=== test_tls: TLS termination on Istio Gateway via aiplatform-ca chain ==="

GATEWAY_IP=$(kubectl -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.spec.clusterIP}')

run_in_probe() {
    local cmd="$1"
    kubectl run tls-probe --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --namespace=cert-manager \
        --overrides='{"spec":{"containers":[{"name":"c","image":"curlimages/curl:8.10.1","command":["sh","-c","'"${cmd}"'"],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
        2>&1
}

# Extract platform CA for verification
CA_CRT=$(kubectl -n cert-manager get secret aiplatform-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d)

# T1: Gateway returns Istio-Envoy and a valid wildcard cert
HTTP_CODE=$(run_in_probe "curl -sk --resolve mlflow.aiplatform.local:443:${GATEWAY_IP} -o /dev/null -w '%{http_code}' https://mlflow.aiplatform.local/" 2>&1 | tail -1)
assert_contains "mlflow.aiplatform.local returns a valid HTTP response over TLS" "${HTTP_CODE}" "403"

# T2: Cert's CN is *.aiplatform.local AND issuer is aiplatform-root-ca
SUBJECT_INFO=$(run_in_probe "curl -sIk --resolve keycloak.aiplatform.local:443:${GATEWAY_IP} https://keycloak.aiplatform.local/ -v 2>&1 | grep -E 'CN|issuer' | head -5" 2>&1 | tail -5)
assert_contains "TLS cert for keycloak.aiplatform.local is signed by aiplatform-root-ca" "${SUBJECT_INFO}" "aiplatform-root-ca"

# T3: server header is istio-envoy (request was actually terminated at the gateway)
HEADERS=$(run_in_probe "curl -sIk --resolve grafana.aiplatform.local:443:${GATEWAY_IP} https://grafana.aiplatform.local/" 2>&1 | tail -10)
assert_contains "grafana.aiplatform.local served via istio-envoy" "${HEADERS}" "server: istio-envoy"

# T4: cert-manager actually issued certificates we expect
CERTS=$(kubectl get certificate -A 2>&1)
assert_contains "Certificate 'minio-tls' issued" "${CERTS}" "minio-tls"
assert_contains "Certificate 'wildcard-aiplatform-tls' issued" "${CERTS}" "wildcard-aiplatform-tls"
assert_contains "Certificate 'aiplatform-root-ca' issued" "${CERTS}" "aiplatform-root-ca"

# T5: all certs are ready (not expired or pending)
READY_COUNT=$(kubectl get certificate -A --no-headers 2>&1 | awk '{print $3}' | grep -c '^True$')
TOTAL_COUNT=$(kubectl get certificate -A --no-headers 2>&1 | wc -l)
if [[ ${READY_COUNT} -eq ${TOTAL_COUNT} && ${TOTAL_COUNT} -gt 0 ]]; then
    echo "PASS  All ${TOTAL_COUNT} certificates are Ready=True"
    __test_pass=$((__test_pass+1))
else
    echo "FAIL  Some certificates not ready (Ready: ${READY_COUNT}/${TOTAL_COUNT})"
    kubectl get certificate -A
    __test_fail=$((__test_fail+1))
fi

summarize
