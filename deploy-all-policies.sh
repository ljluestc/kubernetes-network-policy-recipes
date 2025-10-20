#!/bin/bash
# Master Deployment Script for Kubernetes Network Policy Recipes
# Deploys all network policies in sequence with validation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }

# Configuration
NAMESPACE="default"
WAIT_TIME=5
DRY_RUN=false

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy all Kubernetes Network Policy recipes in sequence

OPTIONS:
    -n, --namespace NAMESPACE   Target namespace (default: default)
    -w, --wait SECONDS         Wait time between deployments (default: 5)
    -d, --dry-run              Perform dry-run only
    -h, --help                 Show this help message

EXAMPLES:
    $0                         # Deploy all policies to default namespace
    $0 -n production          # Deploy to production namespace
    $0 --dry-run              # Validate without applying

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -w|--wait) WAIT_TIME="$2"; shift 2 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

# Network Policy Recipes in deployment order
declare -a RECIPES=(
    "NP-00:00-create-cluster.md:Create Kubernetes Cluster"
    "NP-01:01-deny-all-traffic-to-an-application.md:Deny All Traffic"
    "NP-02:02-limit-traffic-to-an-application.md:Limit Traffic to Application"
    "NP-02A:02a-allow-all-traffic-to-an-application.md:Allow All Traffic"
    "NP-03:03-deny-all-non-whitelisted-traffic-in-the-namespace.md:Deny Non-Whitelisted Traffic"
    "NP-04:04-deny-traffic-from-other-namespaces.md:Deny Traffic from Other Namespaces"
    "NP-05:05-allow-traffic-from-all-namespaces.md:Allow Traffic from All Namespaces"
    "NP-06:06-allow-traffic-from-a-namespace.md:Allow Traffic from Namespace"
    "NP-07:07-allow-traffic-from-some-pods-in-another-namespace.md:Allow Traffic from Specific Pods"
    "NP-08:08-allow-external-traffic.md:Allow External Traffic"
    "NP-09:09-allow-traffic-only-to-a-port.md:Allow Traffic to Port"
    "NP-10:10-allowing-traffic-with-multiple-selectors.md:Multiple Selectors"
    "NP-11:11-deny-egress-traffic-from-an-application.md:Deny Egress Traffic"
    "NP-12:12-deny-all-non-whitelisted-traffic-from-the-namespace.md:Deny Non-Whitelisted Egress"
    "NP-14:14-deny-external-egress-traffic.md:Deny External Egress"
)

log "===== Kubernetes Network Policy Deployment ====="
log "Target namespace: $NAMESPACE"
log "Dry run: $DRY_RUN"
log "Total recipes: ${#RECIPES[@]}"
echo ""

# Verify kubectl connectivity
if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster"
    error "Run: gcloud container clusters create np --enable-network-policy --zone us-central1-b"
    exit 1
fi

success "Connected to Kubernetes cluster"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log "Creating namespace: $NAMESPACE"
    if [[ "$DRY_RUN" == false ]]; then
        kubectl create namespace "$NAMESPACE"
    fi
fi

# Deploy each recipe
DEPLOYED=0
SKIPPED=0
FAILED=0

for recipe in "${RECIPES[@]}"; do
    IFS=':' read -r id file description <<< "$recipe"

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Recipe: $id - $description"
    log "File: $file"

    # Check if file exists
    if [[ ! -f "$file" ]]; then
        warning "File not found: $file (skipping)"
        ((SKIPPED++))
        continue
    fi

    # Extract YAML from markdown (between ```yaml and ```)
    if ! grep -q '```yaml' "$file"; then
        warning "No YAML found in $file (skipping)"
        ((SKIPPED++))
        continue
    fi

    # Extract and apply YAML
    log "Extracting network policy YAML..."

    # Create temporary file with extracted YAML
    TEMP_YAML=$(mktemp)
    sed -n '/```yaml/,/```/p' "$file" | sed '1d;$d' > "$TEMP_YAML"

    # Validate YAML
    if [[ ! -s "$TEMP_YAML" ]]; then
        warning "Empty YAML extracted from $file (skipping)"
        rm -f "$TEMP_YAML"
        ((SKIPPED++))
        continue
    fi

    # Show YAML content
    if [[ "$DRY_RUN" == true ]]; then
        log "YAML content:"
        cat "$TEMP_YAML" | head -20
        success "Dry-run: Would apply this policy"
        ((DEPLOYED++))
    else
        # Apply the network policy
        if kubectl apply -f "$TEMP_YAML" -n "$NAMESPACE"; then
            success "Applied: $id - $description"
            ((DEPLOYED++))

            # Wait before next deployment
            if [[ $WAIT_TIME -gt 0 ]]; then
                log "Waiting ${WAIT_TIME}s before next deployment..."
                sleep "$WAIT_TIME"
            fi
        else
            error "Failed to apply: $id - $description"
            ((FAILED++))
        fi
    fi

    rm -f "$TEMP_YAML"
done

# Summary
echo ""
log "===== Deployment Summary ====="
success "Deployed: $DEPLOYED"
warning "Skipped: $SKIPPED"
error "Failed: $FAILED"
echo ""

# Verify deployed policies
if [[ "$DRY_RUN" == false ]] && [[ $DEPLOYED -gt 0 ]]; then
    log "Verifying deployed network policies..."
    kubectl get networkpolicies -n "$NAMESPACE"
fi

# Exit code
if [[ $FAILED -gt 0 ]]; then
    exit 1
else
    success "All deployments completed successfully!"
    exit 0
fi
