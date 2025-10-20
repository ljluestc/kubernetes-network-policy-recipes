#!/bin/bash
# Feature Matrix for Cloud Providers and CNI Plugins
# Maps NetworkPolicy features to provider/CNI support levels

set -euo pipefail

# Source cloud detection if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/cloud-detection.sh" ]]; then
    source "$SCRIPT_DIR/cloud-detection.sh"
fi

# Feature support levels
FEATURE_FULL="full"          # Fully supported
FEATURE_PARTIAL="partial"     # Partially supported
FEATURE_NONE="none"          # Not supported
FEATURE_UNKNOWN="unknown"    # Unknown support

# Get feature support for a given CNI and feature
# Args: $1=cni, $2=feature
get_cni_feature_support() {
    local cni="$1"
    local feature="$2"

    case "$cni" in
        calico)
            case "$feature" in
                ingress_rules) echo "$FEATURE_FULL" ;;
                egress_rules) echo "$FEATURE_FULL" ;;
                namespace_selectors) echo "$FEATURE_FULL" ;;
                pod_selectors) echo "$FEATURE_FULL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_FULL" ;;
                named_ports) echo "$FEATURE_FULL" ;;
                sctp_protocol) echo "$FEATURE_FULL" ;;
                deny_all) echo "$FEATURE_FULL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        cilium)
            case "$feature" in
                ingress_rules) echo "$FEATURE_FULL" ;;
                egress_rules) echo "$FEATURE_FULL" ;;
                namespace_selectors) echo "$FEATURE_FULL" ;;
                pod_selectors) echo "$FEATURE_FULL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_FULL" ;;
                named_ports) echo "$FEATURE_FULL" ;;
                sctp_protocol) echo "$FEATURE_FULL" ;;
                deny_all) echo "$FEATURE_FULL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        weave)
            case "$feature" in
                ingress_rules) echo "$FEATURE_FULL" ;;
                egress_rules) echo "$FEATURE_FULL" ;;
                namespace_selectors) echo "$FEATURE_FULL" ;;
                pod_selectors) echo "$FEATURE_FULL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_FULL" ;;
                named_ports) echo "$FEATURE_FULL" ;;
                sctp_protocol) echo "$FEATURE_PARTIAL" ;;
                deny_all) echo "$FEATURE_FULL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        flannel)
            case "$feature" in
                ingress_rules) echo "$FEATURE_NONE" ;;
                egress_rules) echo "$FEATURE_NONE" ;;
                namespace_selectors) echo "$FEATURE_NONE" ;;
                pod_selectors) echo "$FEATURE_NONE" ;;
                ip_blocks) echo "$FEATURE_NONE" ;;
                port_ranges) echo "$FEATURE_NONE" ;;
                named_ports) echo "$FEATURE_NONE" ;;
                sctp_protocol) echo "$FEATURE_NONE" ;;
                deny_all) echo "$FEATURE_NONE" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        vpc-cni)
            case "$feature" in
                ingress_rules) echo "$FEATURE_PARTIAL" ;;
                egress_rules) echo "$FEATURE_PARTIAL" ;;
                namespace_selectors) echo "$FEATURE_PARTIAL" ;;
                pod_selectors) echo "$FEATURE_PARTIAL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_PARTIAL" ;;
                named_ports) echo "$FEATURE_PARTIAL" ;;
                sctp_protocol) echo "$FEATURE_NONE" ;;
                deny_all) echo "$FEATURE_PARTIAL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        azure-cni)
            case "$feature" in
                ingress_rules) echo "$FEATURE_FULL" ;;
                egress_rules) echo "$FEATURE_FULL" ;;
                namespace_selectors) echo "$FEATURE_FULL" ;;
                pod_selectors) echo "$FEATURE_FULL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_FULL" ;;
                named_ports) echo "$FEATURE_FULL" ;;
                sctp_protocol) echo "$FEATURE_PARTIAL" ;;
                deny_all) echo "$FEATURE_FULL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        gcp-cni)
            case "$feature" in
                ingress_rules) echo "$FEATURE_FULL" ;;
                egress_rules) echo "$FEATURE_FULL" ;;
                namespace_selectors) echo "$FEATURE_FULL" ;;
                pod_selectors) echo "$FEATURE_FULL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_FULL" ;;
                named_ports) echo "$FEATURE_FULL" ;;
                sctp_protocol) echo "$FEATURE_PARTIAL" ;;
                deny_all) echo "$FEATURE_FULL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        kube-router)
            case "$feature" in
                ingress_rules) echo "$FEATURE_FULL" ;;
                egress_rules) echo "$FEATURE_FULL" ;;
                namespace_selectors) echo "$FEATURE_FULL" ;;
                pod_selectors) echo "$FEATURE_FULL" ;;
                ip_blocks) echo "$FEATURE_FULL" ;;
                port_ranges) echo "$FEATURE_FULL" ;;
                named_ports) echo "$FEATURE_FULL" ;;
                sctp_protocol) echo "$FEATURE_PARTIAL" ;;
                deny_all) echo "$FEATURE_FULL" ;;
                *) echo "$FEATURE_UNKNOWN" ;;
            esac
            ;;
        *)
            echo "$FEATURE_UNKNOWN"
            ;;
    esac
}

# Get detailed feature information with known limitations
get_feature_details() {
    local cni="$1"
    local feature="$2"

    case "$cni-$feature" in
        vpc-cni-ingress_rules)
            echo "Partial: Requires security group configuration for full support"
            ;;
        vpc-cni-egress_rules)
            echo "Partial: Limited by VPC routing and security groups"
            ;;
        vpc-cni-ip_blocks)
            echo "Full: Works well with VPC CIDR blocks"
            ;;
        weave-sctp_protocol)
            echo "Partial: SCTP support may require kernel module"
            ;;
        flannel-*)
            echo "None: Flannel requires additional CNI plugin for NetworkPolicy support"
            ;;
        *)
            local support=$(get_cni_feature_support "$cni" "$feature")
            echo "$support"
            ;;
    esac
}

# Check if a specific Kubernetes version supports a feature
check_k8s_version_support() {
    local feature="$1"
    local k8s_version="${2:-$(get_k8s_version)}"

    # Extract major.minor version
    local version_num=$(echo "$k8s_version" | grep -oP '\d+\.\d+' | head -n 1)

    case "$feature" in
        sctp_protocol)
            # SCTP support added in K8s 1.20 (beta), GA in 1.24
            [[ "$(echo -e "$version_num\n1.20" | sort -V | head -n 1)" == "1.20" ]] && echo "true" || echo "false"
            ;;
        endPort)
            # EndPort field added in K8s 1.22
            [[ "$(echo -e "$version_num\n1.22" | sort -V | head -n 1)" == "1.22" ]] && echo "true" || echo "false"
            ;;
        *)
            echo "true"  # Most features are GA
            ;;
    esac
}

# Get recommended timeout for provider
get_provider_timeout() {
    local provider="$1"

    case "$provider" in
        gke) echo "90" ;;
        eks) echo "90" ;;
        aks) echo "90" ;;
        kind) echo "60" ;;
        minikube) echo "60" ;;
        k3s) echo "60" ;;
        microk8s) echo "60" ;;
        *) echo "60" ;;
    esac
}

# Get recommended parallel workers for provider
get_provider_workers() {
    local provider="$1"

    case "$provider" in
        gke) echo "8" ;;
        eks) echo "8" ;;
        aks) echo "8" ;;
        kind) echo "4" ;;
        minikube) echo "2" ;;
        k3s) echo "4" ;;
        microk8s) echo "4" ;;
        *) echo "4" ;;
    esac
}

# Check if a recipe is supported
is_recipe_supported() {
    local recipe_id="$1"
    local cni="$2"

    case "$recipe_id" in
        01|02|02a)
            # Deny-all and allow-all policies
            local support=$(get_cni_feature_support "$cni" "deny_all")
            [[ "$support" == "$FEATURE_FULL" ]] && return 0 || return 1
            ;;
        03|04|05|06)
            # Namespace-based policies
            local support=$(get_cni_feature_support "$cni" "namespace_selectors")
            [[ "$support" == "$FEATURE_FULL" ]] && return 0 || return 1
            ;;
        07)
            # Pod selector policies
            local support=$(get_cni_feature_support "$cni" "pod_selectors")
            [[ "$support" == "$FEATURE_FULL" ]] && return 0 || return 1
            ;;
        08)
            # External traffic (ipBlock)
            local support=$(get_cni_feature_support "$cni" "ip_blocks")
            [[ "$support" == "$FEATURE_FULL" ]] && return 0 || return 1
            ;;
        09|10)
            # Port-based policies
            local support=$(get_cni_feature_support "$cni" "port_ranges")
            [[ "$support" != "$FEATURE_NONE" ]] && return 0 || return 1
            ;;
        11|12|14)
            # Egress policies
            local support=$(get_cni_feature_support "$cni" "egress_rules")
            [[ "$support" != "$FEATURE_NONE" ]] && return 0 || return 1
            ;;
        13)
            # Egress to specific pods (requires pod selectors)
            local support=$(get_cni_feature_support "$cni" "pod_selectors")
            [[ "$support" == "$FEATURE_FULL" ]] && return 0 || return 1
            ;;
        *)
            # Unknown recipe, assume supported
            return 0
            ;;
    esac
}

# Get list of supported recipes for current environment
get_supported_recipes() {
    local cni="${1:-$(detect_cni_plugin)}"
    local supported=()

    # All recipe IDs
    local recipes=("01" "02" "02a" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12" "13" "14")

    for recipe in "${recipes[@]}"; do
        if is_recipe_supported "$recipe" "$cni"; then
            supported+=("$recipe")
        fi
    done

    echo "${supported[@]}"
}

# Get list of unsupported recipes for current environment
get_unsupported_recipes() {
    local cni="${1:-$(detect_cni_plugin)}"
    local unsupported=()

    # All recipe IDs
    local recipes=("01" "02" "02a" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12" "13" "14")

    for recipe in "${recipes[@]}"; do
        if ! is_recipe_supported "$recipe" "$cni"; then
            unsupported+=("$recipe")
        fi
    done

    echo "${unsupported[@]}"
}

# Generate feature compatibility report
generate_compatibility_report() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"

    local k8s_version=$(get_k8s_version)
    local cni_version=$(get_cni_version "$cni")
    local timeout=$(get_provider_timeout "$provider")
    local workers=$(get_provider_workers "$provider")

    local supported=($(get_supported_recipes "$cni"))
    local unsupported=($(get_unsupported_recipes "$cni"))

    local features=("ingress_rules" "egress_rules" "namespace_selectors" "pod_selectors"
                   "ip_blocks" "port_ranges" "named_ports" "sctp_protocol" "deny_all")

    # Build features JSON with details
    local features_json="{"
    local first=true
    for feature in "${features[@]}"; do
        local support=$(get_cni_feature_support "$cni" "$feature")
        local k8s_support=$(check_k8s_version_support "$feature" "$k8s_version")
        local details=$(get_feature_details "$cni" "$feature")

        [[ "$first" != "true" ]] && features_json+=","
        first=false
        features_json+="\"$feature\":{"
        features_json+="\"support\":\"$support\","
        features_json+="\"k8s_compatible\":$k8s_support,"
        features_json+="\"details\":\"$details\""
        features_json+="}"
    done
    features_json+="}"

    # Build supported recipes JSON array
    local supported_json="["
    first=true
    for recipe in "${supported[@]}"; do
        [[ "$first" != "true" ]] && supported_json+=","
        first=false
        supported_json+="\"$recipe\""
    done
    supported_json+="]"

    # Build unsupported recipes JSON array
    local unsupported_json="["
    first=true
    for recipe in "${unsupported[@]}"; do
        [[ "$first" != "true" ]] && unsupported_json+=","
        first=false
        unsupported_json+="\"$recipe\""
    done
    unsupported_json+="]"

    # Calculate compatibility score
    local total_features=${#features[@]}
    local full_supported=0
    for feature in "${features[@]}"; do
        local support=$(get_cni_feature_support "$cni" "$feature")
        [[ "$support" == "$FEATURE_FULL" ]] && ((full_supported++))
    done
    local compatibility_percentage=$((full_supported * 100 / total_features))

    cat <<EOF
{
  "environment": {
    "provider": "$provider",
    "cni": "$cni",
    "cni_version": "$cni_version",
    "kubernetes_version": "$k8s_version",
    "compatibility_score": "$compatibility_percentage%"
  },
  "recommendations": {
    "timeout_seconds": $timeout,
    "parallel_workers": $workers
  },
  "features": $features_json,
  "recipes": {
    "supported": $supported_json,
    "unsupported": $unsupported_json,
    "total_supported": ${#supported[@]},
    "total_unsupported": ${#unsupported[@]}
  },
  "report_timestamp": "$(date -Iseconds)"
}
EOF
}

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --report)
            generate_compatibility_report
            ;;
        --supported)
            cni="${2:-$(detect_cni_plugin)}"
            get_supported_recipes "$cni"
            ;;
        --unsupported)
            cni="${2:-$(detect_cni_plugin)}"
            get_unsupported_recipes "$cni"
            ;;
        --check)
            recipe_id="${2:-}"
            cni="${3:-$(detect_cni_plugin)}"
            if [[ -z "$recipe_id" ]]; then
                echo "Usage: $0 --check <recipe_id> [cni]"
                exit 1
            fi
            if is_recipe_supported "$recipe_id" "$cni"; then
                echo "Recipe $recipe_id is supported on $cni"
                exit 0
            else
                echo "Recipe $recipe_id is NOT supported on $cni"
                exit 1
            fi
            ;;
        *)
            echo "Feature Matrix Utility"
            echo ""
            echo "Usage:"
            echo "  $0 --report              Generate full compatibility report (JSON)"
            echo "  $0 --supported [cni]     List supported recipes"
            echo "  $0 --unsupported [cni]   List unsupported recipes"
            echo "  $0 --check <recipe> [cni] Check if recipe is supported"
            echo ""
            echo "Or source this script to use functions:"
            echo "  source $0"
            echo "  supported=\$(get_supported_recipes calico)"
            echo "  report=\$(generate_compatibility_report)"
            ;;
    esac
fi
