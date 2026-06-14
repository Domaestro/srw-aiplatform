#!/usr/bin/env bash
# Expose every platform UI on a plain localhost port via kubectl port-forward.
#
# Why this instead of https://*.aiplatform.local:9443 :
#   1. The ".local" TLD is reserved for mDNS (avahi). Browsers with DNS-over-HTTPS
#      enabled may ignore /etc/hosts and fail to resolve *.aiplatform.local.
#   2. The SSO flow embeds the default port 443 in its redirects, so it breaks when
#      accessed through a non-standard forwarded port (e.g. 9443).
#   3. localhost + plain http avoids both the mDNS issue and the self-signed-cert
#      trust prompt.
#
# Each service is forwarded in the background; the script prints the URLs and waits.
# Press Ctrl+C to stop all forwards.
source "$(dirname "$0")/lib.sh"

require_cmd kubectl

declare -a PIDS=()

# Each service is wrapped in a supervisor loop: kubectl port-forward exits whenever
# the target pod restarts (e.g. after `k3d cluster start`). The loop immediately
# re-establishes the forward, so the browser URL keeps working without re-running
# this script. The supervisor is what we track in PIDS (killing it stops the loop).
forward() {
    local ns="$1" svc="$2" local_port="$3" remote_port="$4"
    # setsid puts the supervisor loop in its OWN process group (pgid == its pid),
    # so cleanup can kill the loop AND its current kubectl child in one shot via
    # `kill -- -<pgid>`. Without this, killing the loop can orphan the kubectl child.
    setsid bash -c '
        while true; do
            kubectl -n "'"${ns}"'" port-forward "svc/'"${svc}"'" "'"${local_port}"':'"${remote_port}"'" \
                >/dev/null 2>&1
            sleep 2
        done
    ' &
    PIDS+=("$!")
}

cleanup() {
    trap - INT TERM EXIT
    echo
    log "Stopping all port-forwards"
    # Each supervisor is a process-group leader (started via setsid); killing the
    # negative pid (-pgid) terminates the loop and its kubectl child together.
    for pid in "${PIDS[@]}"; do
        kill -- "-${pid}" 2>/dev/null || kill "${pid}" 2>/dev/null || true
    done
    exit 0
}
trap cleanup INT TERM EXIT

log "Starting port-forwards for all platform UIs ..."
forward mlflow      mlflow                  5000 5000
forward keycloak    keycloak                8090 8080
forward monitoring  kps-grafana             3000 80
forward minio       minio-console           9001 9001
forward kubeflow    argo-workflows-server   2746 2746

sleep 4

GRAFANA_PASS=$(cat "${LOCAL_STATE_DIR}/secrets/grafana-admin.pass" 2>/dev/null || echo "<см. .local/secrets/grafana-admin.pass>")
MINIO_PASS=$(cat "${LOCAL_STATE_DIR}/secrets/minio-root.pass" 2>/dev/null || echo "<см. .local/secrets/minio-root.pass>")
KC_PASS=$(cat "${LOCAL_STATE_DIR}/secrets/keycloak-admin.pass" 2>/dev/null || echo "<см. .local/secrets/keycloak-admin.pass>")

cat <<EOF

============================================================================
  Веб-интерфейсы платформы доступны (открывай в браузере как есть):
============================================================================

  MLflow      http://localhost:5000/
              (без логина, прямой доступ — список экспериментов)

  Keycloak    http://localhost:8090/admin
              admin / ${KC_PASS}
              (realm aiplatform: Users → alice/bob/eve, Clients → oauth2-proxy)

  Grafana     http://localhost:3000/
              admin / ${GRAFANA_PASS}
              (Dashboards → Kubernetes / Compute Resources / Cluster)

  MinIO       https://localhost:9001/
              aiplatform-root / ${MINIO_PASS}
              (браузер ругнётся на cert — нажми «Принять риск», это норм)

  Argo UI     http://localhost:2746/
              (Workflows → namespace team-demo → demo-pipeline-*)

============================================================================
  ВАЖНО: вводи адреса ИМЕННО с http:// или https:// и словом localhost.
         НЕ используй *.aiplatform.local в браузере (см. PROGRESS.md разд.11).

  Этот терминал держи открытым. Ctrl+C — остановить все port-forward.
============================================================================
EOF

# Wait forever (until Ctrl+C).
wait
