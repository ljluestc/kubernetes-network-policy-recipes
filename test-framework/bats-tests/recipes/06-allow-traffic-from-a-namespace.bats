#!/usr/bin/env bats
# BATS tests for Recipe 06: Allow Traffic from a Namespace
# Tests namespace label selector for ingress

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-06-$(date +%s)-$$"
    TEST_NS_ALLOWED="${TEST_NS}-allowed"
    TEST_NS_DENIED="${TEST_NS}-denied"
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
    kubectl delete namespace "${TEST_NS_ALLOWED}" --wait=true --timeout=30s 2>/dev/null || true
    kubectl delete namespace "${TEST_NS_DENIED}" --wait=true --timeout=30s 2>/dev/null || true

    rm -rf "${TEST_TEMP_DIR}"
}

@test "06: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/06-allow-traffic-from-a-namespace.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "06: Policy should allow traffic from namespace with specific label" {
    # Create web pod
    create_test_pod "web" "app=web"

    # Create allowed namespace with label
    create_labeled_namespace "${TEST_NS_ALLOWED}" "team=operations"
    kubectl run allowed-client --image=nginx:alpine -n "${TEST_NS_ALLOWED}"
    kubectl wait --for=condition=Ready pod/allowed-client -n "${TEST_NS_ALLOWED}" --timeout=60s

    # Create denied namespace without label
    kubectl create namespace "${TEST_NS_DENIED}"
    kubectl run denied-client --image=nginx:alpine -n "${TEST_NS_DENIED}"
    kubectl wait --for=condition=Ready pod/denied-client -n "${TEST_NS_DENIED}" --timeout=60s

    # Apply policy allowing from namespace with team=operations
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-from-namespace
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
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Client from allowed namespace should succeed
    local result_allowed=0
    kubectl exec allowed-client -n "${TEST_NS_ALLOWED}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_allowed=$?
    assert_equal "${result_allowed}" "0" "Traffic from labeled namespace should be allowed"

    # Client from denied namespace should be blocked
    local result_denied=0
    kubectl exec denied-client -n "${TEST_NS_DENIED}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_denied=$?
    assert_not_equal "${result_denied}" "0" "Traffic from unlabeled namespace should be denied"
}

@test "06: Policy allows traffic from any pod in allowed namespace" {
    create_test_pod "web" "app=web"

    # Create namespace with label
    create_labeled_namespace "${TEST_NS_ALLOWED}" "env=production"

    # Create multiple pods in allowed namespace with different labels
    kubectl run pod1 --image=nginx:alpine --labels="app=client1" -n "${TEST_NS_ALLOWED}"
    kubectl run pod2 --image=nginx:alpine --labels="app=client2" -n "${TEST_NS_ALLOWED}"
    kubectl run pod3 --image=nginx:alpine --labels="role=monitoring" -n "${TEST_NS_ALLOWED}"

    kubectl wait --for=condition=Ready pod/pod1 -n "${TEST_NS_ALLOWED}" --timeout=60s
    kubectl wait --for=condition=Ready pod/pod2 -n "${TEST_NS_ALLOWED}" --timeout=60s
    kubectl wait --for=condition=Ready pod/pod3 -n "${TEST_NS_ALLOWED}" --timeout=60s

    # Apply policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-production
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
          env: production
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # All pods from allowed namespace should be allowed
    for pod in pod1 pod2 pod3; do
        local result=0
        kubectl exec "${pod}" -n "${TEST_NS_ALLOWED}" -- \
            wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result=$?
        assert_equal "${result}" "0" "Pod ${pod} should be allowed"
    done
}

@test "06: Multiple namespace labels with matchExpressions" {
    create_test_pod "web" "app=web"

    # Create namespaces with different labels
    create_labeled_namespace "${TEST_NS_ALLOWED}" "env=dev,tier=backend"
    kubectl run allowed-client --image=nginx:alpine -n "${TEST_NS_ALLOWED}"
    kubectl wait --for=condition=Ready pod/allowed-client -n "${TEST_NS_ALLOWED}" --timeout=60s

    create_labeled_namespace "${TEST_NS_DENIED}" "env=prod,tier=frontend"
    kubectl run denied-client --image=nginx:alpine -n "${TEST_NS_DENIED}"
    kubectl wait --for=condition=Ready pod/denied-client -n "${TEST_NS_DENIED}" --timeout=60s

    # Apply policy with matchExpressions
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-dev-backend
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
          - dev
        - key: tier
          operator: In
          values:
          - backend
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # dev+backend namespace should be allowed
    local result_allowed=0
    kubectl exec allowed-client -n "${TEST_NS_ALLOWED}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_allowed=$?
    assert_equal "${result_allowed}" "0"

    # prod+frontend namespace should be denied
    local result_denied=0
    kubectl exec denied-client -n "${TEST_NS_DENIED}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_denied=$?
    assert_not_equal "${result_denied}" "0"
}

@test "06: Policy can allow from multiple specific namespaces (OR logic)" {
    create_test_pod "web" "app=web"

    # Create multiple allowed namespaces
    local ns_dev="${TEST_NS}-dev"
    local ns_staging="${TEST_NS}-staging"
    local ns_prod="${TEST_NS}-prod"

    create_labeled_namespace "${ns_dev}" "env=dev"
    create_labeled_namespace "${ns_staging}" "env=staging"
    create_labeled_namespace "${ns_prod}" "env=prod"

    kubectl run client-dev --image=nginx:alpine -n "${ns_dev}"
    kubectl run client-staging --image=nginx:alpine -n "${ns_staging}"
    kubectl run client-prod --image=nginx:alpine -n "${ns_prod}"

    kubectl wait --for=condition=Ready pod/client-dev -n "${ns_dev}" --timeout=60s
    kubectl wait --for=condition=Ready pod/client-staging -n "${ns_staging}" --timeout=60s
    kubectl wait --for=condition=Ready pod/client-prod -n "${ns_prod}" --timeout=60s

    # Apply policy allowing dev OR staging (but not prod)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-dev-staging
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
          env: dev
  - from:
    - namespaceSelector:
        matchLabels:
          env: staging
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Dev should be allowed
    local result_dev=0
    kubectl exec client-dev -n "${ns_dev}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_dev=$?
    assert_equal "${result_dev}" "0"

    # Staging should be allowed
    local result_staging=0
    kubectl exec client-staging -n "${ns_staging}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_staging=$?
    assert_equal "${result_staging}" "0"

    # Prod should be denied
    local result_prod=0
    kubectl exec client-prod -n "${ns_prod}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_prod=$?
    assert_not_equal "${result_prod}" "0"

    # Cleanup
    kubectl delete namespace "${ns_dev}" "${ns_staging}" "${ns_prod}" --wait=false
}

@test "06: Namespace labels can be added/removed dynamically" {
    create_test_pod "web" "app=web"

    # Create namespace without label initially
    kubectl create namespace "${TEST_NS_ALLOWED}"
    kubectl run client --image=nginx:alpine -n "${TEST_NS_ALLOWED}"
    kubectl wait --for=condition=Ready pod/client -n "${TEST_NS_ALLOWED}" --timeout=60s

    # Apply policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-trusted
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
          trusted: "true"
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Traffic should be blocked initially
    local result_before=0
    kubectl exec client -n "${TEST_NS_ALLOWED}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_before=$?
    assert_not_equal "${result_before}" "0" "Should be blocked without label"

    # Add the trusted label to namespace
    kubectl label namespace "${TEST_NS_ALLOWED}" trusted="true"

    wait_for_policy_enforcement

    # Traffic should now be allowed
    local result_after=0
    kubectl exec client -n "${TEST_NS_ALLOWED}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_after=$?
    assert_equal "${result_after}" "0" "Should be allowed after adding label"
}
