#!/usr/bin/env bash
# Validate GitLab CI/CD Pipeline Configuration
# This script checks the pipeline configuration and prerequisites

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_summary() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Validation Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
    echo -e "  ${GREEN}Passed:${NC}   $PASSED"
    echo -e "  ${RED}Failed:${NC}   $FAILED"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All critical checks passed!${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}  Note: Some optional features may not be configured${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ Some critical checks failed${NC}"
        echo -e "${RED}  Please fix the issues above before using the pipeline${NC}"
        return 1
    fi
}

# Start validation
print_header "GitLab CI/CD Pipeline Validation"

# Check 1: GitLab CI file exists
print_header "1. Pipeline Configuration Files"
if [[ -f .gitlab-ci.yml ]]; then
    check_pass "GitLab CI configuration file exists (.gitlab-ci.yml)"

    # Check YAML syntax
    if command -v yamllint &> /dev/null; then
        if yamllint .gitlab-ci.yml &> /dev/null; then
            check_pass "YAML syntax is valid"
        else
            check_fail "YAML syntax errors detected"
            echo "  Run: yamllint .gitlab-ci.yml"
        fi
    else
        check_warn "yamllint not installed (optional validation skipped)"
    fi
else
    check_fail "GitLab CI configuration file not found (.gitlab-ci.yml)"
fi

# Check 2: Test framework files
print_header "2. Test Framework"
if [[ -d test-framework ]]; then
    check_pass "Test framework directory exists"

    # Check critical scripts
    scripts=(
        "run-all-bats-tests.sh"
        "parallel-test-runner.sh"
        "run-integration-tests.sh"
        "lib/ci-helpers.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "test-framework/${script}" ]]; then
            check_pass "Script exists: ${script}"
            if [[ -x "test-framework/${script}" ]]; then
                check_pass "Script is executable: ${script}"
            else
                check_warn "Script not executable: ${script} (will be fixed in pipeline)"
            fi
        else
            check_fail "Missing script: ${script}"
        fi
    done
else
    check_fail "Test framework directory not found"
fi

# Check 3: BATS installation
print_header "3. BATS Testing Framework"
if [[ -d test-framework/bats-libs/bats-core ]]; then
    check_pass "BATS core library installed"
    if [[ -x test-framework/bats-libs/bats-core/bin/bats ]]; then
        check_pass "BATS binary is executable"
    else
        check_warn "BATS binary not executable (will be fixed in pipeline)"
    fi
else
    check_fail "BATS not installed (run: git submodule update --init --recursive)"
fi

# Check 4: Required tools (for local validation)
print_header "4. Local Development Tools (Optional)"
tools=(
    "docker:Docker"
    "kubectl:kubectl"
    "kind:kind (Kubernetes in Docker)"
    "git:Git"
    "jq:jq (JSON processor)"
)

for tool in "${tools[@]}"; do
    cmd="${tool%%:*}"
    name="${tool##*:}"
    if command -v "$cmd" &> /dev/null; then
        check_pass "$name installed ($(command -v $cmd))"
    else
        check_warn "$name not installed (optional for local testing)"
    fi
done

# Check 5: Documentation
print_header "5. Documentation Files"
docs=(
    "docs/gitlab-ci-configuration.md:Full configuration guide"
    "docs/gitlab-ci-quick-start.md:Quick start guide"
    "README.md:Project README"
)

for doc in "${docs[@]}"; do
    file="${doc%%:*}"
    desc="${doc##*:}"
    if [[ -f "$file" ]]; then
        check_pass "$desc exists ($file)"
    else
        check_warn "$desc not found ($file)"
    fi
done

# Check 6: GitLab CI structure
print_header "6. Pipeline Structure"
if [[ -f .gitlab-ci.yml ]]; then
    # Check for key stages
    stages=(
        "build"
        "lint"
        "scan"
        "bats-tests"
        "test-kind"
        "test-cloud"
        "report"
        "deploy"
    )

    for stage in "${stages[@]}"; do
        if grep -q "- ${stage}" .gitlab-ci.yml; then
            check_pass "Stage defined: ${stage}"
        else
            check_warn "Stage not found: ${stage}"
        fi
    done

    # Check for key jobs
    jobs=(
        "build:test-runner-image"
        "pre-commit"
        "container-scanning"
        "bats-tests"
        "test:kind:calico"
        "test:gke:calico"
        "test:eks:default"
        "test:aks:azure-cni"
        "pages"
    )

    for job in "${jobs[@]}"; do
        if grep -q "^${job}:" .gitlab-ci.yml; then
            check_pass "Job defined: ${job}"
        else
            check_warn "Job not found: ${job}"
        fi
    done
fi

# Check 7: Container registry readiness
print_header "7. Container Registry"
if grep -q "CI_REGISTRY_IMAGE" .gitlab-ci.yml; then
    check_pass "Container registry variables configured"
else
    check_fail "Container registry variables not configured"
fi

# Check 8: Caching configuration
print_header "8. Caching Strategy"
if grep -q "cache:" .gitlab-ci.yml; then
    check_pass "Cache configuration found"
    if grep -q "docker_cache" .gitlab-ci.yml; then
        check_pass "Docker layer caching configured"
    else
        check_warn "Docker layer caching not configured"
    fi
else
    check_warn "No caching configured (pipeline may be slower)"
fi

# Check 9: Security scanning
print_header "9. Security Scanning"
if grep -q "container-scanning:" .gitlab-ci.yml; then
    check_pass "Container scanning job configured"
else
    check_warn "Container scanning not configured"
fi

if grep -q "dependency-scanning:" .gitlab-ci.yml; then
    check_pass "Dependency scanning job configured"
else
    check_warn "Dependency scanning not configured"
fi

if grep -q "secrets-scanning:" .gitlab-ci.yml; then
    check_pass "Secrets scanning job configured"
else
    check_warn "Secrets scanning not configured"
fi

# Check 10: GitLab Pages
print_header "10. GitLab Pages"
if grep -q "^pages:" .gitlab-ci.yml; then
    check_pass "GitLab Pages job configured"
    if grep -q "public/" .gitlab-ci.yml; then
        check_pass "Pages output directory configured (public/)"
    else
        check_fail "Pages output directory not configured"
    fi
else
    check_warn "GitLab Pages not configured"
fi

# Check 11: Notifications
print_header "11. Notifications"
if grep -q "SLACK_WEBHOOK_URL" .gitlab-ci.yml; then
    check_pass "Slack notification configured"
else
    check_warn "Slack notifications not configured (optional)"
fi

# Check 12: Cloud provider configurations
print_header "12. Cloud Provider Support"
providers=(
    "GKE:test:gke"
    "EKS:test:eks"
    "AKS:test:aks"
)

for provider in "${providers[@]}"; do
    name="${provider%%:*}"
    pattern="${provider##*:}"
    if grep -q "^${pattern}:" .gitlab-ci.yml; then
        check_pass "$name tests configured"
    else
        check_warn "$name tests not found"
    fi
done

# Check 13: Environment variables documentation
print_header "13. Configuration Variables"
vars=(
    "PARALLEL_JOBS:Parallel execution"
    "TEST_TIMEOUT:Test timeout"
    "ENV_TYPE:Environment type"
    "ENABLE_SECURITY_SCAN:Security scanning toggle"
)

for var in "${vars[@]}"; do
    name="${var%%:*}"
    desc="${var##*:}"
    if grep -q "$name" .gitlab-ci.yml; then
        check_pass "$desc configured ($name)"
    else
        check_warn "$desc not configured ($name)"
    fi
done

# Check 14: Cleanup jobs
print_header "14. Cleanup Jobs"
if grep -q "cleanup:namespaces:" .gitlab-ci.yml; then
    check_pass "Namespace cleanup job configured"
else
    check_warn "Namespace cleanup not configured"
fi

if grep -q "cleanup:docker:" .gitlab-ci.yml; then
    check_pass "Docker cleanup job configured"
else
    check_warn "Docker cleanup not configured"
fi

# Check 15: Repository structure
print_header "15. Repository Structure"
dirs=(
    "test-framework:Test framework directory"
    "test-framework/bats-tests:BATS tests directory"
    "test-framework/lib:Library scripts"
    "docs:Documentation directory"
)

for dir in "${dirs[@]}"; do
    path="${dir%%:*}"
    desc="${dir##*:}"
    if [[ -d "$path" ]]; then
        check_pass "$desc exists ($path)"
    else
        check_warn "$desc not found ($path)"
    fi
done

# Final summary
print_summary
exit_code=$?

# Additional recommendations
if [[ $exit_code -eq 0 ]]; then
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Next Steps${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
    echo "1. Review the configuration guide:"
    echo "   ${BLUE}docs/gitlab-ci-configuration.md${NC}"
    echo ""
    echo "2. Set up GitLab CI/CD variables (if using cloud providers):"
    echo "   - Go to Settings > CI/CD > Variables"
    echo "   - Add cloud provider credentials (GCP, AWS, Azure)"
    echo "   - Add SLACK_WEBHOOK_URL for notifications (optional)"
    echo ""
    echo "3. Enable GitLab Pages:"
    echo "   - Go to Settings > Pages"
    echo "   - Ensure Pages are enabled"
    echo ""
    echo "4. Configure pipeline schedules:"
    echo "   - Go to CI/CD > Schedules"
    echo "   - Add nightly and weekly test runs"
    echo ""
    echo "5. Push to trigger your first pipeline:"
    echo "   ${BLUE}git add . && git commit -m 'Enable enhanced GitLab CI' && git push${NC}"
    echo ""
fi

exit $exit_code
