#!/usr/bin/env bash

#############################################################################
# Automated Cleanup and Environment Reset for Network Policy Testing
#
# This script provides comprehensive cleanup capabilities:
# - Test namespace cleanup
# - NetworkPolicy removal
# - Pod and deployment cleanup
# - Resource garbage collection
# - Cluster state reset
# - Orphaned resource detection
# - Health verification
# - Scheduled cleanup automation
#
# Usage:
#   ./cleanup-environment.sh [options]
#
# Options:
#   --namespace <ns>        Cleanup specific namespace
#   --all-test-ns          Cleanup all test namespaces
#   --policies             Remove all NetworkPolicies
#   --force                Force cleanup without confirmation
#   --verify               Verify cleanup completed successfully
#   --health-check         Run cluster health check after cleanup
#   --dry-run              Show what would be cleaned up
#   --age <duration>       Clean resources older than duration (e.g., 1h, 30m)
#   --schedule             Enable scheduled cleanup
#   --verbose              Enable verbose output
#   --help                 Show this help message
#
#############################################################################

set -euo pipefail

# Default configuration
NAMESPACE=""
ALL_TEST_NS=false
CLEANUP_POLICIES=false
FORCE=false
VERIFY=false
HEALTH_CHECK=false
DRY_RUN=false
AGE_THRESHOLD=""
SCHEDULE=false
VERBOSE=false

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Cleanup counters
NAMESPACES_CLEANED=0
POLICIES_CLEANED=0
PODS_CLEANED=0
SERVICES_CLEANED=0
ERRORS=0

#############################################################################
# Helper Functions
#############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
    ((ERRORS++))
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

confirm_action() {
    local message="$1"

    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo -n "$message (y/N): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

#############################################################################
# Resource Discovery
#############################################################################

find_test_namespaces() {
    log "Discovering test namespaces..."

    local namespaces=()

    # Find namespaces matching test patterns
    while IFS= read -r ns; do
        if [[ "$ns" =~ ^(test-|perf-benchmark-|netpol-test-|recipe-test-) ]]; then
            namespaces+=("$ns")
        fi
    done < <(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

    if [[ ${#namespaces[@]} -gt 0 ]]; then
        log_info "Found ${#namespaces[@]} test namespace(s)"
        for ns in "${namespaces[@]}"; do
            log_info "  - $ns"
        done
    else
        log_info "No test namespaces found"
    fi

    printf '%s\n' "${namespaces[@]}"
}

find_old_resources() {
    local age_threshold="$1"

    log "Finding resources older than $age_threshold..."

    # Convert age threshold to seconds
    local age_seconds=$(convert_duration_to_seconds "$age_threshold")
    local current_time=$(date +%s)

    local old_namespaces=()

    while IFS= read -r line; do
        local ns=$(echo "$line" | awk '{print $1}')
        local age=$(echo "$line" | awk '{print $2}')

        local creation_time=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.creationTimestamp}')
        local creation_seconds=$(date -d "$creation_time" +%s 2>/dev/null || echo "0")

        if [[ $creation_seconds -gt 0 ]]; then
            local resource_age=$((current_time - creation_seconds))
            if [[ $resource_age -gt $age_seconds ]]; then
                old_namespaces+=("$ns")
                log_info "  - $ns (age: ${age})"
            fi
        fi
    done < <(kubectl get namespaces --no-headers 2>/dev/null | grep -E '^(test-|perf-benchmark-|netpol-test-|recipe-test-)')

    printf '%s\n' "${old_namespaces[@]}"
}

convert_duration_to_seconds() {
    local duration="$1"

    if [[ "$duration" =~ ([0-9]+)h ]]; then
        echo $((${BASH_REMATCH[1]} * 3600))
    elif [[ "$duration" =~ ([0-9]+)m ]]; then
        echo $((${BASH_REMATCH[1]} * 60))
    elif [[ "$duration" =~ ([0-9]+)s ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "3600"  # Default: 1 hour
    fi
}

find_orphaned_resources() {
    log "Checking for orphaned resources..."

    local orphaned=()

    # Find pods without parent controllers
    while IFS= read -r pod; do
        local owner=$(kubectl get pod "$pod" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null)
        if [[ -z "$owner" ]]; then
            orphaned+=("pod/$pod")
            log_info "  - Orphaned pod: $pod"
        fi
    done < <(kubectl get pods --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    # Find services without endpoints
    while IFS= read -r line; do
        local ns=$(echo "$line" | awk '{print $1}')
        local svc=$(echo "$line" | awk '{print $2}')

        local endpoints=$(kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[*].addresses}' 2>/dev/null)
        if [[ -z "$endpoints" ]]; then
            orphaned+=("service/$svc in namespace $ns")
            log_info "  - Service without endpoints: $svc (namespace: $ns)"
        fi
    done < <(kubectl get services --all-namespaces --no-headers 2>/dev/null | grep -v kubernetes)

    if [[ ${#orphaned[@]} -eq 0 ]]; then
        log_info "No orphaned resources found"
    fi

    printf '%s\n' "${orphaned[@]}"
}

#############################################################################
# Cleanup Operations
#############################################################################

cleanup_namespace() {
    local ns="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would cleanup namespace: $ns"
        return 0
    fi

    log "Cleaning up namespace: $ns"

    # Delete all NetworkPolicies first
    local policies=$(kubectl get networkpolicies -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$policies" ]]; then
        log_info "Removing NetworkPolicies in $ns"
        kubectl delete networkpolicies --all -n "$ns" --timeout=30s &>/dev/null || log_warn "Failed to delete some policies in $ns"
        POLICIES_CLEANED=$((POLICIES_CLEANED + $(echo "$policies" | wc -l)))
    fi

    # Delete all pods
    local pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$pods" ]]; then
        log_info "Removing pods in $ns"
        kubectl delete pods --all -n "$ns" --grace-period=0 --force --timeout=30s &>/dev/null || log_warn "Failed to delete some pods in $ns"
        PODS_CLEANED=$((PODS_CLEANED + $(echo "$pods" | wc -l)))
    fi

    # Delete all services
    local services=$(kubectl get services -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$services" ]]; then
        log_info "Removing services in $ns"
        kubectl delete services --all -n "$ns" --timeout=30s &>/dev/null || log_warn "Failed to delete some services in $ns"
        SERVICES_CLEANED=$((SERVICES_CLEANED + $(echo "$services" | wc -l)))
    fi

    # Delete the namespace
    log_info "Deleting namespace $ns"
    kubectl delete namespace "$ns" --timeout=60s --wait=false &>/dev/null || {
        log_error "Failed to delete namespace $ns"
        return 1
    }

    NAMESPACES_CLEANED=$((NAMESPACES_CLEANED + 1))
    return 0
}

cleanup_all_policies() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would cleanup all NetworkPolicies"
        return 0
    fi

    log "Cleaning up all NetworkPolicies across all namespaces..."

    local count=0
    while IFS= read -r line; do
        local ns=$(echo "$line" | awk '{print $1}')
        local policy=$(echo "$line" | awk '{print $2}')

        log_info "Deleting policy $policy in namespace $ns"
        kubectl delete networkpolicy "$policy" -n "$ns" --timeout=30s &>/dev/null || {
            log_warn "Failed to delete policy $policy in $ns"
        }
        ((count++))
    done < <(kubectl get networkpolicies --all-namespaces --no-headers 2>/dev/null)

    POLICIES_CLEANED=$count
    log "Removed $count NetworkPolicies"
}

cleanup_orphaned_resources() {
    local orphaned_resources=("$@")

    if [[ ${#orphaned_resources[@]} -eq 0 ]]; then
        return 0
    fi

    log "Cleaning up orphaned resources..."

    for resource in "${orphaned_resources[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "Would cleanup: $resource"
            continue
        fi

        log_info "Deleting $resource"
        kubectl delete $resource --timeout=30s &>/dev/null || {
            log_warn "Failed to delete $resource"
        }
    done
}

#############################################################################
# Verification
#############################################################################

verify_cleanup() {
    local ns="$1"

    log "Verifying cleanup for namespace: $ns"

    # Check if namespace still exists
    if kubectl get namespace "$ns" &>/dev/null; then
        log_warn "Namespace $ns still exists (may be in Terminating state)"

        # Check for remaining resources
        local remaining_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        local remaining_policies=$(kubectl get networkpolicies -n "$ns" --no-headers 2>/dev/null | wc -l)

        if [[ $remaining_pods -gt 0 ]]; then
            log_warn "  - $remaining_pods pods still exist"
        fi

        if [[ $remaining_policies -gt 0 ]]; then
            log_warn "  - $remaining_policies policies still exist"
        fi

        return 1
    else
        log "  ✓ Namespace successfully deleted"
        return 0
    fi
}

verify_all_cleanup() {
    log "Running comprehensive cleanup verification..."

    local issues=0

    # Check for stuck namespaces in Terminating state
    local terminating=$(kubectl get namespaces --no-headers 2>/dev/null | grep Terminating || echo "")
    if [[ -n "$terminating" ]]; then
        log_warn "Namespaces stuck in Terminating state:"
        echo "$terminating" | while read -r line; do
            log_warn "  - $(echo "$line" | awk '{print $1}')"
        done
        ((issues++))
    fi

    # Check for finalizers blocking deletion
    while IFS= read -r ns; do
        local finalizers=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)
        if [[ -n "$finalizers" ]] && [[ "$finalizers" != "[]" ]]; then
            log_warn "Namespace $ns has finalizers: $finalizers"
            ((issues++))
        fi
    done < <(kubectl get namespaces -o jsonpath='{.items[?(@.status.phase=="Terminating")].metadata.name}' 2>/dev/null)

    if [[ $issues -eq 0 ]]; then
        log "  ✓ All cleanup operations verified successfully"
        return 0
    else
        log_warn "Cleanup verification found $issues issue(s)"
        return 1
    fi
}

#############################################################################
# Health Checks
#############################################################################

run_health_check() {
    log "Running cluster health check..."

    local health_status="healthy"

    # Check node status
    log_info "Checking node status..."
    local not_ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l)
    if [[ $not_ready_nodes -gt 0 ]]; then
        log_warn "Found $not_ready_nodes node(s) not in Ready state"
        health_status="degraded"
    else
        log_info "  ✓ All nodes are Ready"
    fi

    # Check system pods
    log_info "Checking system pods..."
    local failing_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
    if [[ $failing_pods -gt 0 ]]; then
        log_warn "Found $failing_pods system pod(s) not running"
        health_status="degraded"
    else
        log_info "  ✓ All system pods are running"
    fi

    # Check for resource pressure
    log_info "Checking resource pressure..."
    local pressure=$(kubectl describe nodes 2>/dev/null | grep -E "MemoryPressure|DiskPressure|PIDPressure" | grep "True" || echo "")
    if [[ -n "$pressure" ]]; then
        log_warn "Resource pressure detected:"
        echo "$pressure" | while read -r line; do
            log_warn "  - $line"
        done
        health_status="degraded"
    else
        log_info "  ✓ No resource pressure detected"
    fi

    # Check CNI health
    log_info "Checking CNI plugin health..."
    local cni_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -E "calico|cilium|weave|flannel|aws-node" | grep -v "Running" | wc -l)
    if [[ $cni_pods -gt 0 ]]; then
        log_warn "Found $cni_pods CNI pod(s) not running"
        health_status="degraded"
    else
        log_info "  ✓ CNI plugins are healthy"
    fi

    if [[ "$health_status" == "healthy" ]]; then
        log "✓ Cluster is healthy"
        return 0
    else
        log_warn "Cluster health: $health_status"
        return 1
    fi
}

#############################################################################
# Scheduled Cleanup
#############################################################################

setup_scheduled_cleanup() {
    log "Setting up scheduled cleanup..."

    local schedule_config="/tmp/netpol-cleanup-schedule"

    cat > "$schedule_config" <<'EOF'
# Network Policy Test Cleanup Schedule
# Runs cleanup every day at 2 AM for resources older than 24 hours

# Cron format: minute hour day month weekday command
0 2 * * * /home/calelin/dev/kubernetes-network-policy-recipes/test-framework/cleanup-environment.sh --all-test-ns --age 24h --force --verify --health-check
EOF

    log "Schedule configuration created: $schedule_config"
    log "To enable, add to crontab: crontab -e"
    log "Then append the contents of: $schedule_config"
}

#############################################################################
# Reporting
#############################################################################

generate_cleanup_report() {
    log "Cleanup Summary:"
    log "  Namespaces cleaned: $NAMESPACES_CLEANED"
    log "  Policies removed: $POLICIES_CLEANED"
    log "  Pods removed: $PODS_CLEANED"
    log "  Services removed: $SERVICES_CLEANED"
    log "  Errors encountered: $ERRORS"

    # Save to file
    local report_file="${OUTPUT_DIR:-./cleanup-results}/cleanup-report-$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "$(dirname "$report_file")"

    jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg namespaces "$NAMESPACES_CLEANED" \
        --arg policies "$POLICIES_CLEANED" \
        --arg pods "$PODS_CLEANED" \
        --arg services "$SERVICES_CLEANED" \
        --arg errors "$ERRORS" \
        '{
            timestamp: $timestamp,
            summary: {
                namespaces_cleaned: $namespaces,
                policies_removed: $policies,
                pods_removed: $pods,
                services_removed: $services,
                errors: $errors
            }
        }' > "$report_file"

    log_info "Report saved to: $report_file"
}

#############################################################################
# Main Execution
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --all-test-ns)
                ALL_TEST_NS=true
                shift
                ;;
            --policies)
                CLEANUP_POLICIES=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verify)
                VERIFY=true
                shift
                ;;
            --health-check)
                HEALTH_CHECK=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --age)
                AGE_THRESHOLD="$2"
                shift 2
                ;;
            --schedule)
                SCHEDULE=true
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

    log "Starting cleanup operations..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi

    # Handle scheduled cleanup setup
    if [[ "$SCHEDULE" == "true" ]]; then
        setup_scheduled_cleanup
        exit 0
    fi

    # Cleanup specific namespace
    if [[ -n "$NAMESPACE" ]]; then
        if ! confirm_action "Cleanup namespace $NAMESPACE?"; then
            log "Cleanup cancelled"
            exit 0
        fi
        cleanup_namespace "$NAMESPACE"
        if [[ "$VERIFY" == "true" ]]; then
            verify_cleanup "$NAMESPACE"
        fi
    fi

    # Cleanup all test namespaces
    if [[ "$ALL_TEST_NS" == "true" ]]; then
        local test_namespaces=()

        if [[ -n "$AGE_THRESHOLD" ]]; then
            mapfile -t test_namespaces < <(find_old_resources "$AGE_THRESHOLD")
        else
            mapfile -t test_namespaces < <(find_test_namespaces)
        fi

        if [[ ${#test_namespaces[@]} -eq 0 ]]; then
            log "No test namespaces found to cleanup"
        else
            if ! confirm_action "Cleanup ${#test_namespaces[@]} test namespace(s)?"; then
                log "Cleanup cancelled"
                exit 0
            fi

            for ns in "${test_namespaces[@]}"; do
                cleanup_namespace "$ns"
            done

            if [[ "$VERIFY" == "true" ]]; then
                verify_all_cleanup
            fi
        fi
    fi

    # Cleanup all NetworkPolicies
    if [[ "$CLEANUP_POLICIES" == "true" ]]; then
        if ! confirm_action "Remove all NetworkPolicies?"; then
            log "Cleanup cancelled"
            exit 0
        fi
        cleanup_all_policies
    fi

    # Find and cleanup orphaned resources
    local orphaned=()
    mapfile -t orphaned < <(find_orphaned_resources)
    if [[ ${#orphaned[@]} -gt 0 ]]; then
        if confirm_action "Cleanup ${#orphaned[@]} orphaned resource(s)?"; then
            cleanup_orphaned_resources "${orphaned[@]}"
        fi
    fi

    # Generate cleanup report
    generate_cleanup_report

    # Run health check if requested
    if [[ "$HEALTH_CHECK" == "true" ]]; then
        run_health_check
    fi

    if [[ $ERRORS -eq 0 ]]; then
        log "✓ Cleanup completed successfully"
        exit 0
    else
        log_warn "Cleanup completed with $ERRORS error(s)"
        exit 1
    fi
}

# Run main function
main "$@"
