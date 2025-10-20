# Test Coverage Tracking and Reporting

This document describes the comprehensive test coverage tracking system for the Kubernetes Network Policy Recipes project.

## Overview

The coverage system tracks three types of test coverage:

1. **BATS Unit Test Coverage** - Percentage of recipes with BATS unit tests
2. **Integration Test Coverage** - Percentage of recipes with integration tests
3. **Recipe Coverage** - Overall percentage of recipes with any kind of test

The system generates badges, HTML reports, and enforces coverage thresholds in CI/CD pipelines.

## Components

### Coverage Tracker (`lib/coverage-tracker.sh`)

Main script for calculating and reporting test coverage.

**Commands:**

```bash
# Generate JSON coverage report
test-framework/lib/coverage-tracker.sh report [output_file]

# Generate HTML coverage report
test-framework/lib/coverage-tracker.sh html [output_file]

# Get specific coverage metrics
test-framework/lib/coverage-tracker.sh bats           # BATS coverage %
test-framework/lib/coverage-tracker.sh integration   # Integration coverage %
test-framework/lib/coverage-tracker.sh recipe        # Recipe coverage %
```

**Output:**

JSON report structure:
```json
{
  "timestamp": "2025-10-17T12:00:00-07:00",
  "coverage": {
    "bats_unit_tests": 100.00,
    "integration_tests": 0,
    "recipe_coverage": 100.00,
    "overall": 50.00
  },
  "details": {
    "total_recipes": 15,
    "bats_test_files": 16,
    "integration_test_files": 0,
    "total_test_cases": 115
  },
  "thresholds": {
    "minimum": 95,
    "target": 100,
    "status": "PASS"
  }
}
```

### Badge Generator (`lib/badge-generator.sh`)

Generates shields.io compatible badges for displaying in README.

**Commands:**

```bash
# Generate all badges from coverage report
test-framework/lib/badge-generator.sh all [coverage_report] [output_dir]

# Generate specific badges
test-framework/lib/badge-generator.sh coverage <percentage> [output_file]
test-framework/lib/badge-generator.sh bats <percentage> [output_file]
test-framework/lib/badge-generator.sh integration <percentage> [output_file]
test-framework/lib/badge-generator.sh recipe <percentage> [output_file]
test-framework/lib/badge-generator.sh tests <count> [output_file]
test-framework/lib/badge-generator.sh ci <status> [output_file]

# Generate README badge markdown
test-framework/lib/badge-generator.sh readme [repo_url] [output_file]
```

**Badge Colors:**

- **brightgreen** - Coverage >= 95%
- **green** - Coverage >= 90%
- **yellow** - Coverage >= 75%
- **orange** - Coverage >= 50%
- **red** - Coverage < 50%

### Coverage Enforcer (`lib/coverage-enforcer.sh`)

Enforces coverage thresholds and detects regressions in CI.

**Commands:**

```bash
# Enforce minimum coverage threshold
test-framework/lib/coverage-enforcer.sh threshold <coverage> [threshold]

# Check for coverage regression
test-framework/lib/coverage-enforcer.sh regression <current> [baseline_file] [max_regression]

# Check component-specific thresholds
test-framework/lib/coverage-enforcer.sh components [report] [bats_threshold] [int_threshold]

# Check recipe completeness
test-framework/lib/coverage-enforcer.sh recipes [report]

# Generate coverage diff for PRs
test-framework/lib/coverage-enforcer.sh diff [current] [baseline] [output]

# Format diff for PR comment
test-framework/lib/coverage-enforcer.sh pr-comment [diff_file]

# Run all checks
test-framework/lib/coverage-enforcer.sh all [report]
```

## Coverage Thresholds

The project enforces the following coverage thresholds:

| Metric | Minimum | Target |
|--------|---------|--------|
| Overall Coverage | 95% | 100% |
| BATS Unit Tests | 95% | 100% |
| Integration Tests | 90% | 100% |
| Recipe Coverage | 100% | 100% |

**Threshold Enforcement:**

- **CI Builds:** Fail if overall coverage < 95%
- **Pull Requests:** Warn if coverage decreases by > 1%
- **Component Tests:** Each component must meet its threshold

## CI/CD Integration

### GitHub Actions

The coverage system is integrated into the `.github/workflows/test.yml` workflow:

**Coverage Report Job:**

```yaml
coverage-report:
  needs: [bats-tests, test-kind]
  runs-on: ubuntu-latest
  steps:
    - Generate coverage report
    - Generate all badges
    - Upload coverage report
    - Upload badges
    - Enforce coverage threshold
    - Check coverage regression
```

**Pull Request Comments:**

Coverage information is automatically added to PR comments:

```markdown
### 📊 Test Coverage

| Metric | Coverage | Status |
|--------|----------|--------|
| Overall Coverage | 100.00% | ✅ |
| BATS Unit Tests | 100.00% | |
| Integration Tests | 95.00% | |
| Recipe Coverage | 100.00% | |
| **Total Test Cases** | **115** | |

Coverage threshold: 95% (PASS)
```

### GitLab CI

Add to `.gitlab-ci.yml`:

```yaml
coverage-report:
  stage: test
  script:
    - source test-framework/lib/coverage-tracker.sh
    - generate_coverage_report
    - source test-framework/lib/badge-generator.sh
    - generate_all_badges
    - source test-framework/lib/coverage-enforcer.sh
    - enforce_coverage_threshold 95
  artifacts:
    paths:
      - test-framework/results/coverage-report.json
      - test-framework/results/coverage-report.html
      - badges/*.json
```

### Jenkins

Add to `Jenkinsfile`:

```groovy
stage('Coverage Report') {
    steps {
        sh '''
            source test-framework/lib/coverage-tracker.sh
            generate_coverage_report test-framework/results/coverage-report.json
            generate_html_coverage_report
        '''
        sh '''
            source test-framework/lib/badge-generator.sh
            generate_all_badges
        '''
        sh '''
            source test-framework/lib/coverage-enforcer.sh
            enforce_coverage_threshold $(jq -r '.coverage.overall' test-framework/results/coverage-report.json) 95
        '''
    }
    post {
        always {
            publishHTML([
                reportDir: 'test-framework/results',
                reportFiles: 'coverage-report.html',
                reportName: 'Coverage Report'
            ])
        }
    }
}
```

## Local Usage

### Generate Coverage Report

```bash
# Generate JSON report
cd test-framework
./lib/coverage-tracker.sh report

# Generate HTML report
./lib/coverage-tracker.sh html

# View HTML report
open results/coverage-report.html  # macOS
xdg-open results/coverage-report.html  # Linux
```

### Generate Badges

```bash
# Generate all badges
cd test-framework
./lib/badge-generator.sh all

# View generated badges
ls -l ../badges/
```

### Check Coverage Threshold

```bash
# Extract overall coverage and check threshold
COVERAGE=$(jq -r '.coverage.overall' test-framework/results/coverage-report.json)
test-framework/lib/coverage-enforcer.sh threshold "$COVERAGE" 95
```

## Adding New Tests

When adding new test files, coverage is automatically recalculated:

### Adding BATS Tests

1. Create new BATS test file in `test-framework/bats-tests/recipes/`
2. Follow naming convention: `XX-recipe-name.bats` (e.g., `00-create-cluster.bats`)
3. Coverage tracker automatically detects the new file
4. Run coverage report to verify

### Adding Integration Tests

Integration tests are located in `test-framework/integration-tests/scenarios/`:

1. Create new scenario file or add to existing one
2. Follow the test function naming convention: `test_category_scenario()`
3. Add test to the runner in `run-integration-tests.sh`:
   ```bash
   run_test test_your_new_scenario
   ```
4. Run tests locally to verify:
   ```bash
   cd test-framework
   ./run-integration-tests.sh
   ```

**Integration Test Structure:**
```bash
test_your_scenario() {
    local ns="integration-test-$$"  # Unique namespace
    echo "  [TEST] Your scenario description"

    # Setup
    kubectl create namespace "$ns"
    kubectl run app -n "$ns" --image=nginx --labels="app=web"

    # Apply policies
    kubectl apply -n "$ns" -f - <<EOF
    <policy YAML>
EOF

    # Test connectivity
    if <test passes>; then
        echo "    PASS: Description"
        kubectl delete namespace "$ns" --wait=false
        return 0
    else
        echo "    FAIL: Description"
        kubectl delete namespace "$ns" --wait=false
        return 1
    fi
}
```

## Coverage Metrics Explained

### BATS Unit Test Coverage

Percentage of recipes (00-14) that have corresponding BATS test files.

**Calculation:**
```
BATS Coverage = (Recipes with BATS tests / Total Recipes) × 100
```

**Example:**
- Total recipes: 15
- Recipes with BATS tests: 15
- BATS Coverage: 100%

### Integration Test Coverage

Percentage of network policy scenarios covered by comprehensive end-to-end integration tests.

**Calculation:**
```
Integration Coverage = (Integration test scenarios / Total scenarios) × 100
```

**Example:**
- Total integration scenarios: 25
- Multi-policy combinations: 3 tests
- Three-tier applications: 3 tests
- Cross-namespace: 3 tests
- Microservices patterns: 3 tests
- Policy conflicts: 4 tests
- Performance: 4 tests
- Failure recovery: 5 tests
- Integration Coverage: 100%

**Test Scenarios:**
1. **Multi-policy combinations** - Deny-all + selective allow, multiple ingress rules, policy precedence
2. **Three-tier applications** - Frontend-backend-database, monitoring sidecars, port restrictions
3. **Cross-namespace** - Namespace selectors, isolation, selective access
4. **Microservices** - Service mesh patterns, sidecar proxies, canary deployments
5. **Policy conflicts** - Overlapping selectors, ingress/egress conflicts, order independence
6. **Performance** - 50+ policies, complex selectors, update latency, scale testing
7. **Failure recovery** - Pod restarts, policy deletion, namespace cleanup, concurrent updates

### Recipe Coverage

Percentage of recipes with ANY kind of test (BATS or integration).

**Calculation:**
```
Recipe Coverage = (Recipes with any test / Total Recipes) × 100
```

### Overall Coverage

Average of BATS and integration coverage.

**Calculation:**
```
Overall Coverage = (BATS Coverage + Integration Coverage) / 2
```

## HTML Report

The HTML coverage report provides a visual representation of test coverage with:

- **Coverage cards** showing each metric
- **Progress bars** for visual representation
- **Color-coded status** indicators
- **Detailed statistics** table
- **Responsive design** for mobile viewing

Access the HTML report at: `test-framework/results/coverage-report.html`

## Badges

Badges are generated in shields.io endpoint format and stored in the `badges/` directory:

- `coverage.json` - Overall coverage badge
- `bats-coverage.json` - BATS unit test coverage
- `integration-coverage.json` - Integration test coverage
- `recipe-coverage.json` - Recipe coverage
- `tests.json` - Total test count
- `ci-status.json` - CI build status

### Using Badges in README

Update your README with:

```markdown
![Test Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/badges/coverage.json)
![BATS Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/badges/bats-coverage.json)
![Tests](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/badges/tests.json)
```

## Troubleshooting

### Coverage Not Calculating

```bash
# Verify test files exist
find test-framework/bats-tests/recipes -name "*.bats"

# Check script permissions
ls -la test-framework/lib/coverage-*.sh

# Run with debug output
bash -x test-framework/lib/coverage-tracker.sh report
```

### Threshold Enforcement Failing

```bash
# Check current coverage
jq -r '.coverage.overall' test-framework/results/coverage-report.json

# Verify threshold value
jq -r '.thresholds.minimum' test-framework/results/coverage-report.json

# Run enforcer manually
test-framework/lib/coverage-enforcer.sh all
```

### Badges Not Generating

```bash
# Check coverage report exists
cat test-framework/results/coverage-report.json

# Generate badges manually
test-framework/lib/badge-generator.sh all

# Verify badge files
ls -la badges/
cat badges/coverage.json
```

## Best Practices

1. **Run coverage reports locally** before committing
2. **Maintain 95%+ overall coverage** for production readiness
3. **Review coverage in PR reviews** to ensure new features are tested
4. **Update baselines** when coverage legitimately increases
5. **Document untested scenarios** when coverage can't reach 100%
6. **Use HTML reports** for detailed analysis
7. **Monitor coverage trends** over time

## Future Enhancements

Planned improvements to the coverage system:

- [ ] Per-recipe coverage details
- [ ] Historical coverage tracking
- [ ] Coverage trend graphs
- [ ] Code coverage integration (beyond test count)
- [ ] Automatic PR suggestions for low coverage
- [ ] Coverage heat maps
- [ ] Multi-platform badge hosting

## Support

For issues with the coverage system:

1. Check this documentation
2. Review the script source code
3. Check CI/CD logs for error messages
4. Open an issue on GitHub

---

**Last Updated:** 2025-10-17
**Coverage System Version:** 1.0.0
