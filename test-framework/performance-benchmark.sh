#!/usr/bin/env bash

#############################################################################
# Performance Benchmarking for Kubernetes Network Policies
#
# This script provides comprehensive performance measurement capabilities:
# - NetworkPolicy enforcement latency measurement
# - Network throughput impact analysis
# - Resource utilization tracking (CPU, memory, network)
# - Performance regression detection
# - Historical benchmark comparison
# - Automated performance alerting
#
# Usage:
#   ./performance-benchmark.sh [options]
#
# Options:
#   --recipe <file>         Recipe file to benchmark (required)
#   --duration <seconds>    Test duration (default: 60)
#   --baseline              Create baseline benchmark
#   --compare <baseline>    Compare against baseline
#   --output <dir>          Output directory (default: ./benchmark-results)
#   --format <json|html>    Output format (default: json)
#   --threshold <percent>   Regression threshold % (default: 10)
#   --alert                 Enable alerting for regressions
#   --verbose               Enable verbose output
#   --help                  Show this help message
#
#############################################################################

set -euo pipefail

# Default configuration
RECIPE_FILE=""
TEST_DURATION=60
BASELINE_MODE=false
COMPARE_BASELINE=""
OUTPUT_DIR="./benchmark-results"
OUTPUT_FORMAT="json"
REGRESSION_THRESHOLD=10
ALERT_ENABLED=false
VERBOSE=false

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Benchmark timestamp
BENCHMARK_TS=$(date +%Y%m%d_%H%M%S)
BENCHMARK_ID="${BENCHMARK_TS}_$(uuidgen | cut -d'-' -f1)"

#############################################################################
# Helper Functions
#############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
    fi
}

show_usage() {
    grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# *//'
    exit 0
}

check_dependencies() {
    local deps=("kubectl" "jq" "bc" "curl" "iperf3")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: apt-get install ${missing[*]} or brew install ${missing[*]}"
        exit 1
    fi
}

#############################################################################
# Kubernetes Cluster Info
#############################################################################

get_cluster_info() {
    log "Gathering cluster information..."

    local cluster_info={}
    cluster_info=$(jq -n \
        --arg version "$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion')" \
        --arg nodes "$(kubectl get nodes --no-headers | wc -l)" \
        --arg cni "$(detect_cni)" \
        --arg provider "$(detect_cloud_provider)" \
        '{
            version: $version,
            nodes: $nodes,
            cni: $cni,
            provider: $provider
        }')

    echo "$cluster_info"
}

detect_cni() {
    if kubectl get ds -n kube-system calico-node &>/dev/null; then
        echo "calico"
    elif kubectl get ds -n kube-system aws-node &>/dev/null; then
        echo "aws-vpc-cni"
    elif kubectl get ds -n kube-system cilium &>/dev/null; then
        echo "cilium"
    elif kubectl get ds -n kube-system weave-net &>/dev/null; then
        echo "weave"
    else
        echo "unknown"
    fi
}

detect_cloud_provider() {
    local context=$(kubectl config current-context)

    if [[ "$context" == *"gke"* ]]; then
        echo "gke"
    elif [[ "$context" == *"eks"* ]] || [[ "$context" == *"aws"* ]]; then
        echo "eks"
    elif [[ "$context" == *"aks"* ]] || [[ "$context" == *"azure"* ]]; then
        echo "aks"
    elif [[ "$context" == *"kind"* ]]; then
        echo "kind"
    elif [[ "$context" == *"minikube"* ]]; then
        echo "minikube"
    else
        echo "unknown"
    fi
}

#############################################################################
# Test Environment Setup
#############################################################################

setup_test_namespace() {
    local ns="perf-benchmark-${BENCHMARK_ID}"
    log "Creating test namespace: $ns"

    kubectl create namespace "$ns" || {
        log_error "Failed to create namespace"
        return 1
    }

    echo "$ns"
}

deploy_test_workloads() {
    local ns="$1"
    log "Deploying test workloads in namespace: $ns"

    # Deploy client pod
    kubectl run client-pod -n "$ns" \
        --image=nicolaka/netshoot \
        --restart=Never \
        --command -- sleep 3600

    # Deploy server pod with iperf3
    kubectl run server-pod -n "$ns" \
        --image=networkstatic/iperf3 \
        --restart=Never \
        --port=5201 \
        -- iperf3 -s

    # Create service for server
    kubectl expose pod server-pod -n "$ns" \
        --port=5201 \
        --name=server-service

    # Wait for pods to be ready
    log "Waiting for pods to be ready..."
    kubectl wait --for=condition=Ready pod/client-pod -n "$ns" --timeout=120s
    kubectl wait --for=condition=Ready pod/server-pod -n "$ns" --timeout=120s

    log "Test workloads deployed successfully"
}

#############################################################################
# Performance Measurements
#############################################################################

measure_policy_enforcement_latency() {
    local ns="$1"
    local policy_file="$2"

    log "Measuring NetworkPolicy enforcement latency..."

    local start_time=$(date +%s.%N)

    # Apply the policy
    kubectl apply -f "$policy_file" -n "$ns" &>/dev/null

    # Wait for policy to be enforced (check connectivity changes)
    local enforced=false
    local max_wait=30
    local wait_count=0

    while [[ "$enforced" == "false" ]] && [[ $wait_count -lt $max_wait ]]; do
        # Test connectivity to verify policy is enforced
        if ! kubectl exec client-pod -n "$ns" -- timeout 2 nc -zv server-service 5201 &>/dev/null; then
            enforced=true
        fi
        sleep 0.5
        ((wait_count++))
    done

    local end_time=$(date +%s.%N)
    local latency=$(echo "$end_time - $start_time" | bc)

    log_info "Policy enforcement latency: ${latency}s"
    echo "$latency"
}

measure_baseline_throughput() {
    local ns="$1"

    log "Measuring baseline network throughput (no policy)..."

    # Run iperf3 test from client to server
    local throughput=$(kubectl exec client-pod -n "$ns" -- \
        iperf3 -c server-service -t 10 -J 2>/dev/null | \
        jq -r '.end.sum_received.bits_per_second // 0')

    # Convert to Mbps
    local throughput_mbps=$(echo "scale=2; $throughput / 1000000" | bc)

    log_info "Baseline throughput: ${throughput_mbps} Mbps"
    echo "$throughput_mbps"
}

measure_policy_throughput() {
    local ns="$1"

    log "Measuring network throughput with policy applied..."

    # Run iperf3 test from client to server
    local throughput=$(kubectl exec client-pod -n "$ns" -- \
        iperf3 -c server-service -t 10 -J 2>/dev/null | \
        jq -r '.end.sum_received.bits_per_second // 0')

    # Convert to Mbps
    local throughput_mbps=$(echo "scale=2; $throughput / 1000000" | bc)

    log_info "Policy throughput: ${throughput_mbps} Mbps"
    echo "$throughput_mbps"
}

measure_resource_utilization() {
    local ns="$1"
    local duration="$2"

    log "Measuring resource utilization for ${duration}s..."

    local cpu_total=0
    local mem_total=0
    local samples=0

    for ((i=0; i<duration; i+=5)); do
        # Get pod metrics
        local metrics=$(kubectl top pod -n "$ns" --no-headers 2>/dev/null || echo "")

        if [[ -n "$metrics" ]]; then
            while IFS= read -r line; do
                local cpu=$(echo "$line" | awk '{print $2}' | sed 's/m//')
                local mem=$(echo "$line" | awk '{print $3}' | sed 's/Mi//')

                cpu_total=$(echo "$cpu_total + $cpu" | bc)
                mem_total=$(echo "$mem_total + $mem" | bc)
                ((samples++))
            done <<< "$metrics"
        fi

        sleep 5
    done

    if [[ $samples -gt 0 ]]; then
        local cpu_avg=$(echo "scale=2; $cpu_total / $samples" | bc)
        local mem_avg=$(echo "scale=2; $mem_total / $samples" | bc)

        log_info "Average CPU: ${cpu_avg}m, Average Memory: ${mem_avg}Mi"
        echo "${cpu_avg}:${mem_avg}"
    else
        log_warn "No resource metrics available"
        echo "0:0"
    fi
}

measure_connection_latency() {
    local ns="$1"

    log "Measuring connection latency..."

    # Use ping to measure latency
    local latency=$(kubectl exec client-pod -n "$ns" -- \
        ping -c 10 server-service 2>/dev/null | \
        tail -1 | awk -F'/' '{print $5}')

    log_info "Connection latency: ${latency}ms"
    echo "$latency"
}

#############################################################################
# Benchmark Execution
#############################################################################

run_benchmark() {
    local recipe_file="$1"

    log "Starting performance benchmark..."
    log "Recipe: $recipe_file"
    log "Duration: ${TEST_DURATION}s"
    log "Benchmark ID: $BENCHMARK_ID"

    # Create test namespace
    local test_ns=$(setup_test_namespace)

    # Deploy test workloads
    deploy_test_workloads "$test_ns"

    # Measure baseline (no policy)
    log "Phase 1: Baseline measurements (no policy)"
    local baseline_throughput=$(measure_baseline_throughput "$test_ns")
    local baseline_latency=$(measure_connection_latency "$test_ns")
    local baseline_resources=$(measure_resource_utilization "$test_ns" 30)

    # Apply policy and measure enforcement latency
    log "Phase 2: Policy enforcement"
    local enforcement_latency=$(measure_policy_enforcement_latency "$test_ns" "$recipe_file")

    # Measure with policy applied
    log "Phase 3: Performance with policy"
    sleep 5  # Let policy stabilize
    local policy_throughput=$(measure_policy_throughput "$test_ns")
    local policy_latency=$(measure_connection_latency "$test_ns")
    local policy_resources=$(measure_resource_utilization "$test_ns" 30)

    # Calculate impact
    local throughput_impact=0
    if [[ $(echo "$baseline_throughput > 0" | bc) -eq 1 ]]; then
        throughput_impact=$(echo "scale=2; (($baseline_throughput - $policy_throughput) / $baseline_throughput) * 100" | bc)
    fi

    local latency_impact=0
    if [[ -n "$baseline_latency" ]] && [[ -n "$policy_latency" ]]; then
        latency_impact=$(echo "scale=2; (($policy_latency - $baseline_latency) / $baseline_latency) * 100" | bc)
    fi

    # Extract resource metrics
    local baseline_cpu=$(echo "$baseline_resources" | cut -d':' -f1)
    local baseline_mem=$(echo "$baseline_resources" | cut -d':' -f2)
    local policy_cpu=$(echo "$policy_resources" | cut -d':' -f1)
    local policy_mem=$(echo "$policy_resources" | cut -d':' -f2)

    # Get cluster info
    local cluster_info=$(get_cluster_info)

    # Build results JSON
    local results=$(jq -n \
        --arg id "$BENCHMARK_ID" \
        --arg timestamp "$BENCHMARK_TS" \
        --arg recipe "$recipe_file" \
        --arg duration "$TEST_DURATION" \
        --argjson cluster "$cluster_info" \
        --arg enforcement_latency "$enforcement_latency" \
        --arg baseline_throughput "$baseline_throughput" \
        --arg policy_throughput "$policy_throughput" \
        --arg throughput_impact "$throughput_impact" \
        --arg baseline_latency "$baseline_latency" \
        --arg policy_latency "$policy_latency" \
        --arg latency_impact "$latency_impact" \
        --arg baseline_cpu "$baseline_cpu" \
        --arg baseline_mem "$baseline_mem" \
        --arg policy_cpu "$policy_cpu" \
        --arg policy_mem "$policy_mem" \
        '{
            benchmark_id: $id,
            timestamp: $timestamp,
            recipe: $recipe,
            duration: $duration,
            cluster: $cluster,
            enforcement: {
                latency_seconds: $enforcement_latency
            },
            throughput: {
                baseline_mbps: $baseline_throughput,
                policy_mbps: $policy_throughput,
                impact_percent: $throughput_impact
            },
            latency: {
                baseline_ms: $baseline_latency,
                policy_ms: $policy_latency,
                impact_percent: $latency_impact
            },
            resources: {
                baseline: {
                    cpu_millicores: $baseline_cpu,
                    memory_mb: $baseline_mem
                },
                policy: {
                    cpu_millicores: $policy_cpu,
                    memory_mb: $policy_mem
                }
            }
        }')

    # Cleanup test namespace
    log "Cleaning up test namespace..."
    kubectl delete namespace "$test_ns" --wait=false &>/dev/null || true

    echo "$results"
}

#############################################################################
# Results Storage and Comparison
#############################################################################

save_results() {
    local results="$1"
    local output_file="${OUTPUT_DIR}/${BENCHMARK_ID}.json"

    mkdir -p "$OUTPUT_DIR"
    echo "$results" | jq '.' > "$output_file"

    log "Results saved to: $output_file"

    # Save as baseline if requested
    if [[ "$BASELINE_MODE" == "true" ]]; then
        local baseline_file="${OUTPUT_DIR}/baseline.json"
        echo "$results" | jq '.' > "$baseline_file"
        log "Baseline saved to: $baseline_file"
    fi
}

compare_with_baseline() {
    local results="$1"
    local baseline_file="$2"

    if [[ ! -f "$baseline_file" ]]; then
        log_error "Baseline file not found: $baseline_file"
        return 1
    fi

    log "Comparing with baseline: $baseline_file"

    local baseline=$(cat "$baseline_file")

    # Extract metrics
    local current_enforcement=$(echo "$results" | jq -r '.enforcement.latency_seconds')
    local baseline_enforcement=$(echo "$baseline" | jq -r '.enforcement.latency_seconds')

    local current_throughput=$(echo "$results" | jq -r '.throughput.policy_mbps')
    local baseline_throughput=$(echo "$baseline" | jq -r '.throughput.policy_mbps')

    # Calculate regressions
    local enforcement_regression=0
    if [[ $(echo "$baseline_enforcement > 0" | bc) -eq 1 ]]; then
        enforcement_regression=$(echo "scale=2; (($current_enforcement - $baseline_enforcement) / $baseline_enforcement) * 100" | bc)
    fi

    local throughput_regression=0
    if [[ $(echo "$baseline_throughput > 0" | bc) -eq 1 ]]; then
        throughput_regression=$(echo "scale=2; (($baseline_throughput - $current_throughput) / $baseline_throughput) * 100" | bc)
    fi

    # Build comparison report
    local comparison=$(jq -n \
        --arg current_id "$(echo "$results" | jq -r '.benchmark_id')" \
        --arg baseline_id "$(echo "$baseline" | jq -r '.benchmark_id')" \
        --arg enforcement_regression "$enforcement_regression" \
        --arg throughput_regression "$throughput_regression" \
        --argjson threshold "$REGRESSION_THRESHOLD" \
        '{
            current_benchmark: $current_id,
            baseline_benchmark: $baseline_id,
            regressions: {
                enforcement_latency_percent: $enforcement_regression,
                throughput_percent: $throughput_regression
            },
            threshold_percent: $threshold,
            regression_detected: (($enforcement_regression | tonumber) > $threshold or ($throughput_regression | tonumber) > $threshold)
        }')

    echo "$comparison"

    # Check for regressions
    if [[ $(echo "$comparison" | jq -r '.regression_detected') == "true" ]]; then
        log_warn "Performance regression detected!"
        log_warn "Enforcement latency regression: ${enforcement_regression}%"
        log_warn "Throughput regression: ${throughput_regression}%"

        if [[ "$ALERT_ENABLED" == "true" ]]; then
            send_alert "$comparison"
        fi

        return 1
    else
        log "No significant regression detected"
        return 0
    fi
}

send_alert() {
    local comparison="$1"

    log "Sending performance alert..."

    # Webhook URL from environment
    local webhook_url="${PERFORMANCE_ALERT_WEBHOOK:-}"

    if [[ -z "$webhook_url" ]]; then
        log_warn "No webhook URL configured (set PERFORMANCE_ALERT_WEBHOOK)"
        return 0
    fi

    local message="Performance Regression Detected\n"
    message+="Benchmark: $(echo "$comparison" | jq -r '.current_benchmark')\n"
    message+="Enforcement Latency: $(echo "$comparison" | jq -r '.regressions.enforcement_latency_percent')%\n"
    message+="Throughput: $(echo "$comparison" | jq -r '.regressions.throughput_percent')%"

    curl -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$message\"}" \
        &>/dev/null || log_warn "Failed to send alert"
}

#############################################################################
# HTML Report Generation
#############################################################################

generate_html_report() {
    local results="$1"
    local output_file="${OUTPUT_DIR}/${BENCHMARK_ID}.html"

    local recipe=$(echo "$results" | jq -r '.recipe')
    local enforcement_latency=$(echo "$results" | jq -r '.enforcement.latency_seconds')
    local throughput_impact=$(echo "$results" | jq -r '.throughput.impact_percent')
    local latency_impact=$(echo "$results" | jq -r '.latency.impact_percent')

    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Network Policy Performance Benchmark - $BENCHMARK_ID</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; padding: 15px; background: #f9f9f9; border-left: 4px solid #4CAF50; }
        .metric-label { font-size: 0.9em; color: #666; }
        .metric-value { font-size: 1.5em; font-weight: bold; color: #333; }
        .warning { border-left-color: #ff9800; }
        .error { border-left-color: #f44336; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #4CAF50; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Network Policy Performance Benchmark</h1>
        <p><strong>Benchmark ID:</strong> $BENCHMARK_ID</p>
        <p><strong>Recipe:</strong> $recipe</p>
        <p><strong>Timestamp:</strong> $(date)</p>

        <h2>Key Metrics</h2>
        <div class="metric">
            <div class="metric-label">Enforcement Latency</div>
            <div class="metric-value">${enforcement_latency}s</div>
        </div>
        <div class="metric $([ $(echo "$throughput_impact > 5" | bc) -eq 1 ] && echo "warning")">
            <div class="metric-label">Throughput Impact</div>
            <div class="metric-value">${throughput_impact}%</div>
        </div>
        <div class="metric $([ $(echo "$latency_impact > 5" | bc) -eq 1 ] && echo "warning")">
            <div class="metric-label">Latency Impact</div>
            <div class="metric-value">${latency_impact}%</div>
        </div>

        <h2>Detailed Results</h2>
        <pre>$(echo "$results" | jq '.')</pre>

        <div class="footer">
            Generated by kubernetes-network-policy-recipes performance benchmark suite
        </div>
    </div>
</body>
</html>
EOF

    log "HTML report saved to: $output_file"
}

#############################################################################
# Main Execution
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --recipe)
                RECIPE_FILE="$2"
                shift 2
                ;;
            --duration)
                TEST_DURATION="$2"
                shift 2
                ;;
            --baseline)
                BASELINE_MODE=true
                shift
                ;;
            --compare)
                COMPARE_BASELINE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --threshold)
                REGRESSION_THRESHOLD="$2"
                shift 2
                ;;
            --alert)
                ALERT_ENABLED=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    # Validate required arguments
    if [[ -z "$RECIPE_FILE" ]]; then
        log_error "Recipe file is required (--recipe)"
        show_usage
    fi

    if [[ ! -f "$RECIPE_FILE" ]]; then
        log_error "Recipe file not found: $RECIPE_FILE"
        exit 1
    fi

    # Check dependencies
    check_dependencies

    # Run benchmark
    local results=$(run_benchmark "$RECIPE_FILE")

    # Save results
    save_results "$results"

    # Compare with baseline if requested
    if [[ -n "$COMPARE_BASELINE" ]]; then
        compare_with_baseline "$results" "$COMPARE_BASELINE"
    fi

    # Generate HTML report if requested
    if [[ "$OUTPUT_FORMAT" == "html" ]]; then
        generate_html_report "$results"
    fi

    # Display summary
    log "Benchmark completed successfully!"
    echo "$results" | jq '.'
}

# Run main function
main "$@"
