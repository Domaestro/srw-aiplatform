#!/usr/bin/env bash
# Recovery helper to run AFTER `k3d cluster start aiplatform`.
#
# Problem it solves: when the cluster is resumed, pods come up in an arbitrary
# order. oauth2-proxy performs a fail-fast OIDC discovery against Keycloak (via the
# Istio ingress gateway) at startup; if the gateway has not yet programmed its :443
# listener, oauth2-proxy exits and enters CrashLoopBackOff with growing back-off.
#
# This script waits for the gateway to be reachable, then restarts the order-
# sensitive deployments so they re-resolve their dependencies cleanly.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

log "Waiting for core control-plane pods to be Ready"
kubectl -n istio-system   rollout status deployment/istiod                 --timeout=180s || true
kubectl -n istio-ingress  rollout status deployment/istio-ingressgateway   --timeout=180s || true
kubectl -n keycloak       rollout status deployment/keycloak               --timeout=300s || true

log "Waiting until the Istio gateway accepts TLS on :443 (via in-cluster probe)"
GATEWAY_IP=$(kubectl -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.spec.clusterIP}')
for i in $(seq 1 30); do
    ready=$(kubectl run gw-wait-${RANDOM} --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --namespace=cert-manager \
        --overrides='{"spec":{"containers":[{"name":"c","image":"curlimages/curl:8.10.1","command":["sh","-c","timeout 3 nc -z '"${GATEWAY_IP}"' 443 && echo READY || echo WAIT"],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
        2>/dev/null | tr -d '[:space:]')
    if [[ "${ready}" == *READY* ]]; then
        log "Gateway :443 is accepting connections"
        break
    fi
    log "  attempt ${i}/30: gateway not ready yet, retrying in 5s"
    sleep 5
done

log "Restarting dependency-sensitive deployments"
kubectl -n mlflow rollout restart deployment/oauth2-proxy
kubectl -n mlflow rollout status  deployment/oauth2-proxy --timeout=120s || \
    warn "oauth2-proxy still not Ready; check 'kubectl -n mlflow logs deploy/oauth2-proxy'"

log "Post-start recovery complete. Current pod status:"
kubectl get pods -A --field-selector=status.phase!=Succeeded 2>/dev/null | grep -vE 'Completed' | tail -30

log "Reminder: the k3d serverlb already binds host port 8443->443, so DO NOT run"
log "          'kubectl port-forward ... 8443:443'. Use a different local port, e.g.:"
log "          kubectl -n istio-ingress port-forward svc/istio-ingressgateway 9443:443"
log "          then open https://<svc>.aiplatform.local:9443"
