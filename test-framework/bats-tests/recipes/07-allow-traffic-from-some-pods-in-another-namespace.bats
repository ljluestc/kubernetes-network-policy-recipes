#!/usr/bin/env bats
# BATS tests for Recipe 07: Allow Traffic from Some Pods in Another Namespace
# Tests combined namespace and pod selector

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-07-$(date +%s)-$$"
    TEST_NS_OTHER="${TEST_NS}-other"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

teardown() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    echo "# Test duration: ${duration}s" >&3

    kubectl delete namespace "${TEST_NS}" --wait=true --timeout=30s 2>/dev/null || true
    kubectl delete namespace "${TEST_NS_OTHER}" --wait=true --timeout=30s 2>/dev/null || true

    rm -rf "${TEST_TEMP_DIR}"
}

@test "07: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/07-allow-traffic-from-some-pods-in-another-namespace.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "07: Policy should require BOTH namespace AND pod labels (AND logic)" {
    # Create web pod
    create_test_pod "web" "app=web"

    # Create external namespace with label
    create_labeled_namespace "${TEST_NS_OTHER}" "team=operations"

    # Create pods with different labels
    kubectl run allowed-pod --image=nginx:alpine --labels="type=monitoring" -n "${TEST_NS_OTHER}"
    kubectl run denied-pod --image=nginx:alpine --labels="type=frontend" -n "${TEST_NS_OTHER}"

    kubectl wait --for=condition=Ready pod/allowed-pod -n "${TEST_NS_OTHER}" --timeout=60s
    kubectl wait --for=condition=Ready pod/denied-pod -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply policy requiring BOTH team=operations namespace AND type=monitoring pod
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-operations-monitoring
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: operations
      podSelector:
        matchLabels:
          type: monitoring
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Pod with both namespace and pod labels should be allowed
    local result_allowed=0
    kubectl exec allowed-pod -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_allowed=$?
    assert_equal "${result_allowed}" "0" "Pod with matching labels should be allowed"

    # Pod with correct namespace but wrong pod label should be denied
    local result_denied=0
    kubectl exec denied-pod -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_denied=$?
    assert_not_equal "${result_denied}" "0" "Pod without matching pod label should be denied"
}

@test "07: Multiple from clauses create OR logic between rules" {
    create_test_pod "web" "app=web"

    # Create two namespaces
    local ns_ops="${TEST_NS}-ops"
    local ns_dev="${TEST_NS}-dev"

    create_labeled_namespace "${ns_ops}" "team=operations"
    create_labeled_namespace "${ns_dev}" "team=dev"

    # Create pods
    kubectl run ops-monitoring --image=nginx:alpine --labels="type=monitoring" -n "${ns_ops}"
    kubectl run dev-debug --image=nginx:alpine --labels="type=debug" -n "${ns_dev}"
    kubectl run ops-other --image=nginx:alpine --labels="type=other" -n "${ns_ops}"

    kubectl wait --for=condition=Ready pod/ops-monitoring -n "${ns_ops}" --timeout=60s
    kubectl wait --for=condition=Ready pod/dev-debug -n "${ns_dev}" --timeout=60s
    kubectl wait --for=condition=Ready pod/ops-other -n "${ns_ops}" --timeout=60s

    # Apply policy with OR logic: (ops+monitoring) OR (dev+debug)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-multiple
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: operations
      podSelector:
        matchLabels:
          type: monitoring
  - from:
    - namespaceSelector:
        matchLabels:
          team: dev
      podSelector:
        matchLabels:
          type: debug
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # ops-monitoring should be allowed (matches first rule)
    local result1=0
    kubectl exec ops-monitoring -n "${ns_ops}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result1=$?
    assert_equal "${result1}" "0"

    # dev-debug should be allowed (matches second rule)
    local result2=0
    kubectl exec dev-debug -n "${ns_dev}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result2=$?
    assert_equal "${result2}" "0"

    # ops-other should be denied (doesn't match either rule)
    local result3=0
    kubectl exec ops-other -n "${ns_ops}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result3=$?
    assert_not_equal "${result3}" "0"

    # Cleanup
    kubectl delete namespace "${ns_ops}" "${ns_dev}" --wait=false
}

@test "07: Pod selector alone does not match pods from other namespaces" {
    create_test_pod "web" "app=web"

    # Create unlabeled namespace
    kubectl create namespace "${TEST_NS_OTHER}"
    kubectl run client --image=nginx:alpine --labels="type=monitoring" -n "${TEST_NS_OTHER}"
    kubectl wait --for=condition=Ready pod/client -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply policy with podSelector but no namespaceSelector
    # This should only match pods in the SAME namespace
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-monitoring
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          type: monitoring
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Pod from other namespace should be blocked (even with matching pod label)
    local result=0
    kubectl exec client -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result=$?
    assert_not_equal "${result}" "0" "PodSelector alone should not match cross-namespace"
}

@test "07: Complex matchExpressions for both namespace and pod" {
    create_test_pod "web" "app=web"

    # Create namespace with multiple labels
    create_labeled_namespace "${TEST_NS_OTHER}" "env=prod,region=us-west"

    # Create pods with various labels
    kubectl run allowed --image=nginx:alpine --labels="app=api,version=v2" -n "${TEST_NS_OTHER}"
    kubectl run denied1 --image=nginx:alpine --labels="app=api,version=v1" -n "${TEST_NS_OTHER}"
    kubectl run denied2 --image=nginx:alpine --labels="app=web,version=v2" -n "${TEST_NS_OTHER}"

    kubectl wait --for=condition=Ready pod/allowed -n "${TEST_NS_OTHER}" --timeout=60s
    kubectl wait --for=condition=Ready pod/denied1 -n "${TEST_NS_OTHER}" --timeout=60s
    kubectl wait --for=condition=Ready pod/denied2 -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply policy with complex matchExpressions
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-prod-api-v2
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchExpressions:
        - key: env
          operator: In
          values:
          - prod
        - key: region
          operator: Exists
      podSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - api
        - key: version
          operator: In
          values:
          - v2
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # allowed (app=api,version=v2) should succeed
    local result_allowed=0
    kubectl exec allowed -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_allowed=$?
    assert_equal "${result_allowed}" "0"

    # denied1 (version=v1) should be blocked
    local result_denied1=0
    kubectl exec denied1 -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_denied1=$?
    assert_not_equal "${result_denied1}" "0"

    # denied2 (app=web) should be blocked
    local result_denied2=0
    kubectl exec denied2 -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_denied2=$?
    assert_not_equal "${result_denied2}" "0"
}

@test "07: Same rule can select multiple pods across namespaces" {
    create_test_pod "web" "app=web"

    # Create namespace
    create_labeled_namespace "${TEST_NS_OTHER}" "shared=true"

    # Create multiple pods with same label
    kubectl run pod1 --image=nginx:alpine --labels="role=client" -n "${TEST_NS_OTHER}"
    kubectl run pod2 --image=nginx:alpine --labels="role=client" -n "${TEST_NS_OTHER}"
    kubectl run pod3 --image=nginx:alpine --labels="role=client" -n "${TEST_NS_OTHER}"

    kubectl wait --for=condition=Ready pod/pod1 -n "${TEST_NS_OTHER}" --timeout=60s
    kubectl wait --for=condition=Ready pod/pod2 -n "${TEST_NS_OTHER}" --timeout=60s
    kubectl wait --for=condition=Ready pod/pod3 -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-shared-clients
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          shared: "true"
      podSelector:
        matchLabels:
          role: client
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # All pods with role=client should be allowed
    for pod in pod1 pod2 pod3; do
        local result=0
        kubectl exec "${pod}" -n "${TEST_NS_OTHER}" -- \
            wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result=$?
        assert_equal "${result}" "0" "Pod ${pod} should be allowed"
    done
}
