#!/bin/bash
# Cost Optimization and Tracking
# Tracks resource usage and estimates cloud costs for testing

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/cloud-detection.sh" ]]; then
    source "$SCRIPT_DIR/cloud-detection.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Default cost tracking directory
COST_TRACKING_DIR="${COST_TRACKING_DIR:-./test-framework/results}"
COST_TRACKING_FILE="${COST_TRACKING_DIR}/cost-tracking.csv"

# Ensure cost tracking directory exists
ensure_cost_tracking_dir() {
    mkdir -p "$COST_TRACKING_DIR"

    # Create CSV header if file doesn't exist
    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo "timestamp,provider,cni,test_name,duration_seconds,node_count,estimated_cost_usd,currency" > "$COST_TRACKING_FILE"
    fi
}

# Track test duration and metadata
track_test_duration() {
    local test_name="$1"
    local duration_seconds="$2"
    local provider="${3:-$(detect_cloud_provider)}"
    local cni="${4:-$(detect_cni_plugin)}"

    ensure_cost_tracking_dir

    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    local estimated_cost=$(estimate_cost "$provider" "$duration_seconds" "$node_count")
    local timestamp=$(date -Iseconds)

    # Append to cost tracking file
    echo "$timestamp,$provider,$cni,$test_name,$duration_seconds,$node_count,$estimated_cost,USD" >> "$COST_TRACKING_FILE"

    info "Cost tracking: $test_name on $provider ($cni) - ${duration_seconds}s - \$${estimated_cost}"
}

# Estimate cost based on provider, duration, and node count
estimate_cost() {
    local provider="$1"
    local duration_seconds="$2"
    local node_count="${3:-1}"

    # Convert duration to hours
    local duration_hours=$(echo "scale=6; $duration_seconds / 3600" | bc)

    # Cost per node per hour (approximate as of 2024)
    local cost_per_node_hour=0

    case "$provider" in
        gke)
            # GKE: ~$0.10/hour for standard nodes + cluster management fee
            cost_per_node_hour="0.10"
            local management_fee=$(echo "scale=6; $duration_hours * 0.10" | bc)
            local node_cost=$(echo "scale=6; $duration_hours * $node_count * $cost_per_node_hour" | bc)
            echo "scale=4; $node_cost + $management_fee" | bc
            ;;
        eks)
            # EKS: ~$0.10/hour for control plane + node costs
            cost_per_node_hour="0.10"
            local control_plane_fee=$(echo "scale=6; $duration_hours * 0.10" | bc)
            local node_cost=$(echo "scale=6; $duration_hours * $node_count * $cost_per_node_hour" | bc)
            echo "scale=4; $node_cost + $control_plane_fee" | bc
            ;;
        aks)
            # AKS: ~$0.096/hour for standard nodes (free control plane)
            cost_per_node_hour="0.096"
            echo "scale=4; $duration_hours * $node_count * $cost_per_node_hour" | bc
            ;;
        kind|minikube|k3s|microk8s)
            # Local clusters - only electricity costs, negligible
            echo "0.00"
            ;;
        *)
            # Unknown provider
            echo "0.00"
            ;;
    esac
}

# Calculate total costs from tracking file
calculate_total_costs() {
    local provider="${1:-}"
    local start_date="${2:-}"
    local end_date="${3:-}"

    ensure_cost_tracking_dir

    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo "0.00"
        return
    fi

    # Build awk filter conditions
    local filter=""
    if [[ -n "$provider" ]]; then
        filter="$filter && \$2 == \"$provider\""
    fi
    if [[ -n "$start_date" ]]; then
        filter="$filter && \$1 >= \"$start_date\""
    fi
    if [[ -n "$end_date" ]]; then
        filter="$filter && \$1 <= \"$end_date\""
    fi

    # Remove leading "&&" if present
    filter="${filter#&& }"
    if [[ -z "$filter" ]]; then
        filter="1"  # Match all
    fi

    # Sum estimated costs
    awk -F',' "NR > 1 && $filter {sum += \$7} END {printf \"%.4f\", sum}" "$COST_TRACKING_FILE"
}

# Get cost breakdown by provider
get_cost_breakdown() {
    local start_date="${1:-}"
    local end_date="${2:-}"

    ensure_cost_tracking_dir

    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo "{}"
        return
    fi

    # Build date filter
    local filter="NR > 1"
    if [[ -n "$start_date" ]]; then
        filter="$filter && \$1 >= \"$start_date\""
    fi
    if [[ -n "$end_date" ]]; then
        filter="$filter && \$1 <= \"$end_date\""
    fi

    # Group by provider and sum costs
    local breakdown=$(awk -F',' "$filter {costs[\$2] += \$7} END {
        printf \"{\"
        first=1
        for (provider in costs) {
            if (!first) printf \",\"
            printf \"\\\"%s\\\":%.4f\", provider, costs[provider]
            first=0
        }
        printf \"}\"
    }" "$COST_TRACKING_FILE")

    echo "$breakdown"
}

# Get detailed cost report
generate_cost_report() {
    local provider="${1:-}"
    local start_date="${2:-}"
    local end_date="${3:-}"

    local total_cost=$(calculate_total_costs "$provider" "$start_date" "$end_date")
    local cost_breakdown=$(get_cost_breakdown "$start_date" "$end_date")
    local test_count=$(get_test_count "$provider" "$start_date" "$end_date")
    local total_duration=$(get_total_duration "$provider" "$start_date" "$end_date")

    cat <<EOF
{
  "report_type": "cost_analysis",
  "filters": {
    "provider": "${provider:-all}",
    "start_date": "${start_date:-all}",
    "end_date": "${end_date:-all}"
  },
  "summary": {
    "total_cost_usd": $total_cost,
    "total_tests": $test_count,
    "total_duration_seconds": $total_duration,
    "average_cost_per_test": $(echo "scale=4; $total_cost / $test_count" | bc 2>/dev/null || echo "0")
  },
  "breakdown_by_provider": $cost_breakdown,
  "generated_at": "$(date -Iseconds)"
}
EOF
}

# Get test count
get_test_count() {
    local provider="${1:-}"
    local start_date="${2:-}"
    local end_date="${3:-}"

    ensure_cost_tracking_dir

    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo "0"
        return
    fi

    local filter="NR > 1"
    if [[ -n "$provider" ]]; then
        filter="$filter && \$2 == \"$provider\""
    fi
    if [[ -n "$start_date" ]]; then
        filter="$filter && \$1 >= \"$start_date\""
    fi
    if [[ -n "$end_date" ]]; then
        filter="$filter && \$1 <= \"$end_date\""
    fi

    awk -F',' "$filter {count++} END {print count+0}" "$COST_TRACKING_FILE"
}

# Get total duration
get_total_duration() {
    local provider="${1:-}"
    local start_date="${2:-}"
    local end_date="${3:-}"

    ensure_cost_tracking_dir

    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo "0"
        return
    fi

    local filter="NR > 1"
    if [[ -n "$provider" ]]; then
        filter="$filter && \$2 == \"$provider\""
    fi
    if [[ -n "$start_date" ]]; then
        filter="$filter && \$1 >= \"$start_date\""
    fi
    if [[ -n "$end_date" ]]; then
        filter="$filter && \$1 <= \"$end_date\""
    fi

    awk -F',' "$filter {sum += \$5} END {print sum+0}" "$COST_TRACKING_FILE"
}

# Suggest cost optimizations
suggest_optimizations() {
    local provider="${1:-$(detect_cloud_provider)}"

    cat <<EOF
Cost Optimization Suggestions for $provider:

EOF

    case "$provider" in
        gke)
            cat <<EOF
1. Use Preemptible/Spot nodes for non-critical testing (60-90% savings)
2. Implement cluster autoscaling to scale down during idle periods
3. Use regional clusters instead of zonal for better reliability/cost ratio
4. Enable GKE Autopilot for managed resource optimization
5. Clean up test resources immediately after test completion
6. Schedule long-running tests during off-peak hours
7. Use committed use discounts for predictable workloads
EOF
            ;;
        eks)
            cat <<EOF
1. Use Spot instances for worker nodes (up to 90% savings)
2. Implement cluster autoscaler with appropriate scaling policies
3. Use Fargate for workloads with predictable resource needs
4. Enable AWS Compute Optimizer recommendations
5. Clean up unused LoadBalancers and EBS volumes
6. Use AWS Savings Plans for committed usage
7. Consolidate multiple test clusters into one multi-tenant cluster
EOF
            ;;
        aks)
            cat <<EOF
1. Use Spot VMs for node pools (up to 90% savings)
2. Enable cluster autoscaler with appropriate min/max node counts
3. Use Azure Container Instances for burst workloads
4. Implement Azure Cost Management + Billing alerts
5. Clean up test resources with retention policies
6. Use Azure Reservations for committed workloads
7. Enable AKS cost analysis and recommendations
EOF
            ;;
        kind|minikube|k3s|microk8s)
            cat <<EOF
1. Local clusters have minimal costs (electricity only)
2. Ensure automated cleanup of old clusters and images
3. Consider resource limits to prevent host system impact
4. Use lightweight test images to reduce storage and bandwidth
5. Implement proper lifecycle management for test resources
EOF
            ;;
        *)
            echo "No specific optimizations available for provider: $provider"
            ;;
    esac
}

# Print cost summary
print_cost_summary() {
    local provider="${1:-}"

    ensure_cost_tracking_dir

    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        warn "No cost tracking data available"
        return
    fi

    local total_cost=$(calculate_total_costs "$provider")
    local test_count=$(get_test_count "$provider")
    local total_duration=$(get_total_duration "$provider")

    echo ""
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}Cost Tracking Summary${NC}"
    echo -e "${GREEN}===============================================${NC}"
    if [[ -n "$provider" ]]; then
        echo -e "Provider: ${CYAN}$provider${NC}"
    else
        echo -e "Provider: ${CYAN}All${NC}"
    fi
    echo ""
    echo -e "Total Tests:    ${CYAN}$test_count${NC}"
    echo -e "Total Duration: ${CYAN}${total_duration}s ($(echo "scale=2; $total_duration / 60" | bc)m)${NC}"
    echo -e "Total Cost:     ${CYAN}\$${total_cost} USD${NC}"

    if [[ $test_count -gt 0 ]]; then
        local avg_cost=$(echo "scale=4; $total_cost / $test_count" | bc)
        echo -e "Avg Cost/Test:  ${CYAN}\$${avg_cost} USD${NC}"
    fi
    echo -e "${GREEN}===============================================${NC}"
    echo ""
}

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --track)
            test_name="${2:-}"
            duration="${3:-}"
            if [[ -z "$test_name" || -z "$duration" ]]; then
                echo "Usage: $0 --track <test_name> <duration_seconds> [provider] [cni]"
                exit 1
            fi
            provider="${4:-$(detect_cloud_provider)}"
            cni="${5:-$(detect_cni_plugin)}"
            track_test_duration "$test_name" "$duration" "$provider" "$cni"
            ;;
        --estimate)
            provider="${2:-$(detect_cloud_provider)}"
            duration="${3:-3600}"
            nodes="${4:-3}"
            cost=$(estimate_cost "$provider" "$duration" "$nodes")
            echo "Estimated cost: \$${cost} USD"
            echo "Provider: $provider"
            echo "Duration: ${duration}s ($(echo "scale=2; $duration / 60" | bc)m)"
            echo "Nodes: $nodes"
            ;;
        --report)
            generate_cost_report "$2" "$3" "$4"
            ;;
        --summary)
            print_cost_summary "$2"
            ;;
        --total)
            total=$(calculate_total_costs "$2" "$3" "$4")
            echo "$total"
            ;;
        --optimize)
            suggest_optimizations "$2"
            ;;
        *)
            echo "Cost Optimization and Tracking Utility"
            echo ""
            echo "Usage:"
            echo "  $0 --track <test> <duration> [provider] [cni]  Track test execution cost"
            echo "  $0 --estimate [provider] [duration] [nodes]    Estimate cost for scenario"
            echo "  $0 --report [provider] [start] [end]           Generate cost report (JSON)"
            echo "  $0 --summary [provider]                        Print cost summary"
            echo "  $0 --total [provider] [start] [end]            Calculate total costs"
            echo "  $0 --optimize [provider]                       Show optimization suggestions"
            echo ""
            echo "Or source this script to use functions:"
            echo "  source $0"
            echo "  track_test_duration \"my-test\" 120"
            echo "  cost=\$(estimate_cost \"gke\" 3600 3)"
            ;;
    esac
fi
