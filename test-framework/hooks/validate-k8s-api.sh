#!/usr/bin/env bash
# Validate Kubernetes API versions in YAML files
# This hook checks for deprecated API versions and validates YAML syntax

set -euo pipefail

EXIT_CODE=0

echo "Validating Kubernetes YAML files..."

for file in "$@"; do
    # Skip non-YAML files
    if [[ ! "$file" =~ \.(yaml|yml)$ ]]; then
        continue
    fi

    # Skip if file doesn't exist (deleted)
    if [[ ! -f "$file" ]]; then
        continue
    fi

    echo "  Checking $file..."

    # Check for deprecated API versions
    if grep -q "apiVersion: extensions/v1beta1" "$file" 2>/dev/null; then
        echo "ERROR: Deprecated API version in $file: extensions/v1beta1"
        echo "  Use: networking.k8s.io/v1 for NetworkPolicy"
        EXIT_CODE=1
    fi

    if grep -q "apiVersion: policy/v1beta1" "$file" 2>/dev/null; then
        if grep -q "kind: PodDisruptionBudget" "$file" 2>/dev/null; then
            echo "WARNING: API version policy/v1beta1 for PodDisruptionBudget is deprecated"
            echo "  Consider using: policy/v1"
        fi
    fi

    if grep -q "apiVersion: networking.k8s.io/v1beta1" "$file" 2>/dev/null; then
        echo "ERROR: Deprecated API version in $file: networking.k8s.io/v1beta1"
        echo "  Use: networking.k8s.io/v1"
        EXIT_CODE=1
    fi

    # Validate with kubectl --dry-run if kubectl is available
    if command -v kubectl &> /dev/null; then
        if ! kubectl apply --dry-run=client -f "$file" &> /dev/null; then
            echo "ERROR: Invalid Kubernetes YAML in $file"
            echo "  Run: kubectl apply --dry-run=client -f $file"
            echo "  to see detailed validation errors"
            EXIT_CODE=1
        else
            echo "    ✓ Valid Kubernetes YAML"
        fi
    else
        echo "    ⚠ kubectl not found - skipping validation (install kubectl for full validation)"
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo "All Kubernetes YAML files passed validation."
fi

exit $EXIT_CODE
