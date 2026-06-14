#!/usr/bin/env bash
# Test: Pod Security Admission rejects privileged pods in tenant namespaces.
source "$(dirname "$0")/lib.sh"

echo "=== test_psa: PSA restricted blocks privileged pods in team-demo ==="

# T1: privileged pod is REJECTED in team-demo (enforce=restricted)
OUT=$(kubectl apply -n team-demo -f - 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: psa-test-privileged }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","5"]
      securityContext:
        privileged: true
EOF
)
assert_contains "PSA blocks privileged pod in team-demo" "${OUT}" "violates PodSecurity"
assert_contains "PSA cites 'restricted' policy" "${OUT}" 'restricted:'

# T2: pod with no securityContext is REJECTED in team-demo
OUT=$(kubectl apply -n team-demo -f - 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: psa-test-noctx }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","5"]
EOF
)
assert_contains "PSA blocks pod without explicit securityContext" "${OUT}" "violates PodSecurity"

# T3: hostPath volume is REJECTED in team-demo
OUT=$(kubectl apply -n team-demo -f - 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: psa-test-hostpath }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","5"]
      volumeMounts: [{ name: host, mountPath: /h }]
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
        capabilities: { drop: ["ALL"] }
        seccompProfile: { type: RuntimeDefault }
  volumes:
    - name: host
      hostPath: { path: /etc }
EOF
)
assert_contains "PSA blocks hostPath volume" "${OUT}" "violates PodSecurity"

# T4: PSA-compliant pod is ACCEPTED in team-demo
OUT=$(kubectl apply -n team-demo -f - 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: psa-test-compliant }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep","5"]
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
        capabilities: { drop: ["ALL"] }
        seccompProfile: { type: RuntimeDefault }
EOF
)
assert_contains "PSA accepts compliant pod" "${OUT}" "psa-test-compliant created"
kubectl -n team-demo delete pod psa-test-compliant --wait=false >/dev/null 2>&1 || true

summarize
