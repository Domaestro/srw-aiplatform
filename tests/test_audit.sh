#!/usr/bin/env bash
# Test: audit-log captures sensitive operations.
source "$(dirname "$0")/lib.sh"

echo "=== test_audit: kube-apiserver audit log records security-sensitive ops ==="

AUDIT_PATH="/var/log/k3s/audit.log"

# T1: audit log file exists and grows
LINES_BEFORE=$(docker exec k3d-aiplatform-server-0 wc -l "${AUDIT_PATH}" 2>/dev/null | awk '{print $1}')
[[ -z "${LINES_BEFORE}" ]] && LINES_BEFORE=0
echo "  audit log has ${LINES_BEFORE} lines before test"

# Generate a sensitive operation: create + delete a Secret in team-demo
kubectl -n team-demo create secret generic audit-test-secret --from-literal=key=value >/dev/null 2>&1
kubectl -n team-demo delete secret audit-test-secret >/dev/null 2>&1

# Give audit log a moment to flush
sleep 2
LINES_AFTER=$(docker exec k3d-aiplatform-server-0 wc -l "${AUDIT_PATH}" 2>/dev/null | awk '{print $1}')
[[ -z "${LINES_AFTER}" ]] && LINES_AFTER=0
echo "  audit log has ${LINES_AFTER} lines after test"

if [[ ${LINES_AFTER} -gt ${LINES_BEFORE} ]]; then
    echo "PASS  audit log grew after secret create/delete (+$((LINES_AFTER - LINES_BEFORE)) lines)"
    __test_pass=$((__test_pass+1))
else
    echo "FAIL  audit log did not grow"
    __test_fail=$((__test_fail+1))
fi

# T2: audit log contains a RequestResponse-level entry for secret creation
RECENT=$(docker exec k3d-aiplatform-server-0 tail -200 "${AUDIT_PATH}" 2>/dev/null)
assert_contains "audit log contains secret create event" "${RECENT}" '"verb":"create"'
assert_contains "audit log records secret resource" "${RECENT}" '"resource":"secrets"'
assert_contains "audit log records team-demo namespace" "${RECENT}" '"namespace":"team-demo"'

# T3: audit log uses RequestResponse level for secrets (high sensitivity)
assert_contains "audit log captures RequestResponse level for secrets" "${RECENT}" '"level":"RequestResponse"'

# T4: routine probe paths (/healthz, /version, /metrics) are NOT in audit log
# (they should be excluded per policy)
HEALTHZ_COUNT=$(echo "${RECENT}" | grep -c '"requestURI":"/healthz' || true)
VERSION_COUNT=$(echo "${RECENT}" | grep -c '"requestURI":"/version' || true)
if [[ ${HEALTHZ_COUNT} -eq 0 && ${VERSION_COUNT} -eq 0 ]]; then
    echo "PASS  audit policy correctly excludes /healthz, /version (noise)"
    __test_pass=$((__test_pass+1))
else
    echo "FAIL  audit log contains noisy /healthz or /version events"
    __test_fail=$((__test_fail+1))
fi

summarize
