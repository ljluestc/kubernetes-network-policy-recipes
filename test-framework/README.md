# Parallel Test Framework

Comprehensive automated testing framework for Kubernetes Network Policy recipes with parallel execution and detailed reporting.

## Features

### Core Testing
- **Parallel Execution**: Run up to N tests concurrently (default: 4 workers)
- **Resource Isolation**: Each test runs in its own isolated namespace
- **Comprehensive Coverage**: Tests all 15 network policy recipes (NP-01 through NP-14, plus NP-02a)
- **JSON Output**: Machine-readable test results for CI/CD integration
- **Timeout Handling**: Configurable test timeouts (default: 60s)
- **Automatic Cleanup**: Proper namespace cleanup after each test
- **Detailed Reporting**: Pass/fail status, duration, and error messages

### Performance & Benchmarking
- **Performance Benchmarking**: Measure NetworkPolicy enforcement latency, throughput impact, and resource utilization
- **Baseline Management**: Create and compare against performance baselines
- **Regression Detection**: Automatic detection of performance regressions with configurable thresholds
- **CNI Comparison**: Compare performance across different CNI plugins (Calico, Cilium, Weave, etc.)
- **Automated Cleanup**: Comprehensive environment cleanup with orphaned resource detection
- **Performance Analysis**: Generate detailed trend analysis and optimization recommendations
- **Multi-Format Reports**: JSON, HTML, and Markdown report generation

## Prerequisites

- `kubectl` - Kubernetes CLI tool
- `jq` - JSON processor
- `gnu-parallel` - GNU Parallel for job distribution
- Access to a Kubernetes cluster with NetworkPolicy support

### Installing Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install parallel jq

# macOS
brew install parallel jq

# Verify installation
parallel --version
jq --version
kubectl version --client
```

## Usage

### Basic Usage

Run all tests with default settings (4 parallel workers):

```bash
./parallel-test-runner.sh
```

### Advanced Options

```bash
# Run with 8 parallel workers
./parallel-test-runner.sh --workers 8

# Run specific tests only
./parallel-test-runner.sh --filter "01,02,09"

# Custom timeout (90 seconds)
./parallel-test-runner.sh --timeout 90

# Output JSON results only
./parallel-test-runner.sh --json > results.json

# Verbose mode
./parallel-test-runner.sh --verbose

# Custom results directory
./parallel-test-runner.sh --results-dir /tmp/test-results
```

## Architecture

### Components

1. **parallel-test-runner.sh**: Main test orchestrator
   - Discovers test recipes automatically
   - Manages worker pool using GNU Parallel
   - Aggregates results into JSON
   - Handles cleanup and error reporting

2. **lib/test-functions.sh**: Test implementation library
   - Individual test functions for each recipe (test_recipe_01 through test_recipe_14, plus test_recipe_02a)
   - Helper functions for pod management and connectivity testing
   - Resource creation and validation

### Execution Flow

```
1. Recipe Discovery
   ↓
2. Namespace Creation (isolated per test)
   ↓
3. Parallel Execution (GNU Parallel job queue)
   ↓
4. Test Execution (with timeout)
   ↓
5. Result Collection (JSON per test)
   ↓
6. Namespace Cleanup
   ↓
7. Result Aggregation
   ↓
8. Summary Report
```

### Resource Isolation

Each test runs in a unique namespace with the format:
```
np-test-{recipe_id}-{timestamp}-{pid}
```

Example: `np-test-01-20250115-031234-12345`

Namespaces are labeled with:
- `test-runner=parallel`
- `recipe-id={recipe_id}`
- `test-run={timestamp}`

## Output Format

### Console Output

```
[12:34:56] Found 15 recipes to test: 01 02 02a 03 04 05 06 07 08 09 10 11 12 13 14
[12:34:56] Running tests with 4 parallel workers...
[SUCCESS] Recipe 01: PASSED (5s)
[SUCCESS] Recipe 02: PASSED (7s)
[ERROR] Recipe 03: FAIL (3s)
...
===== Test Summary =====
Total: 15
Passed: 13
Failed: 2
Timeout: 0
Pass Rate: 86.67%
Total Duration: 45s
```

### JSON Output

```json
{
  "test_run": {
    "timestamp": "2025-01-15T03:12:34-08:00",
    "workers": 4,
    "timeout": 60
  },
  "results": [
    {
      "recipe_id": "01",
      "status": "PASS",
      "duration_seconds": 5,
      "namespace": "np-test-01-20250115-031234-12345",
      "timestamp": "2025-01-15T03:12:39-08:00",
      "timeout_seconds": 60,
      "error_message": "",
      "output": "Testing NP-01: Deny all traffic to an application\nPASS: Traffic correctly blocked\n"
    }
  ],
  "summary": {
    "total": 15,
    "passed": 13,
    "failed": 2,
    "timeout": 0,
    "total_duration_seconds": 45,
    "pass_rate": 86.67
  }
}
```

## Recipe Coverage

| Recipe | Description | Status |
|--------|-------------|--------|
| NP-01  | Deny all traffic to an application | ✅ Implemented |
| NP-02  | Limit traffic to an application | ✅ Implemented |
| NP-02a | Allow all traffic to an application | ✅ Implemented |
| NP-03  | Deny all non-whitelisted traffic in namespace | ✅ Implemented |
| NP-04  | Deny traffic from other namespaces | ✅ Implemented |
| NP-05  | Allow traffic from all namespaces | ✅ Implemented |
| NP-06  | Allow traffic from a specific namespace | ✅ Implemented |
| NP-07  | Allow traffic from specific pods in another namespace | ✅ Implemented |
| NP-08  | Allow external traffic | ✅ Implemented |
| NP-09  | Allow traffic only to a specific port | ✅ Implemented |
| NP-10  | Allow traffic with multiple selectors | ✅ Implemented |
| NP-11  | Deny egress traffic from an application | ✅ Implemented |
| NP-12  | Deny all non-whitelisted egress traffic from namespace | ✅ Implemented |
| NP-13  | Allow egress traffic to specific pods | ✅ Implemented |
| NP-14  | Deny external egress traffic | ✅ Implemented |

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Network Policy Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y parallel jq

      - name: Setup kind cluster
        uses: helm/kind-action@v1
        with:
          cluster_name: test-cluster
          config: .github/kind-config.yaml

      - name: Run parallel tests
        run: |
          cd test-framework
          ./parallel-test-runner.sh --json > results.json

      - name: Upload test results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-results
          path: test-framework/results/
```

### GitLab CI Example

```yaml
test:
  stage: test
  image: gcr.io/google.com/cloudsdktool/cloud-sdk:latest
  before_script:
    - apt-get update && apt-get install -y parallel jq
    - gcloud container clusters get-credentials test-cluster
  script:
    - cd test-framework
    - ./parallel-test-runner.sh --json > results.json
  artifacts:
    paths:
      - test-framework/results/
    when: always
```

## Performance Benchmarks

Approximate execution times (4 workers on GKE cluster):

| Workers | Total Time | Time per Test (avg) |
|---------|-----------|---------------------|
| 1       | 180s      | 12s                 |
| 2       | 95s       | 12s                 |
| 4       | 50s       | 12s                 |
| 8       | 30s       | 12s                 |

## Troubleshooting

### Tests Timing Out

Increase the timeout value:
```bash
./parallel-test-runner.sh --timeout 120
```

### Namespace Conflicts

The framework uses unique timestamps and PIDs to avoid conflicts. If you encounter issues, manually clean up:
```bash
kubectl delete namespace -l test-runner=parallel
```

### GNU Parallel Not Found

Install GNU Parallel:
```bash
# Ubuntu/Debian
sudo apt-get install parallel

# macOS
brew install parallel
```

### jq Command Not Found

Install jq:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

## Performance Testing and Benchmarking

The test framework includes comprehensive performance benchmarking and analysis tools. See **[PERFORMANCE.md](PERFORMANCE.md)** for detailed documentation.

### Quick Start

```bash
# Run performance benchmark on a recipe
./performance-benchmark.sh --recipe 01-deny-all-traffic-to-an-application.md

# Create baseline for future comparisons
./performance-benchmark.sh --recipe 01-deny-all-traffic-to-an-application.md --baseline

# Compare against baseline and alert on regressions
./performance-benchmark.sh \
  --recipe 01-deny-all-traffic-to-an-application.md \
  --compare ./benchmark-results/baseline.json \
  --threshold 10 \
  --alert

# Cleanup test environments
./cleanup-environment.sh --all-test-ns --age 1h --verify

# Generate performance analysis report
./analyze-performance.sh --format html --recommendations
```

### Available Tools

1. **`performance-benchmark.sh`** - Benchmark NetworkPolicy performance
   - Measures enforcement latency, throughput impact, connection latency
   - Tracks resource utilization (CPU, memory)
   - Supports baseline creation and comparison
   - Automatic regression detection and alerting

2. **`cleanup-environment.sh`** - Automated environment cleanup
   - Cleanup test namespaces and resources
   - Orphaned resource detection
   - Age-based cleanup with dry-run support
   - Scheduled cleanup via cron
   - Health verification

3. **`analyze-performance.sh`** - Performance analysis and reporting
   - Trend analysis across multiple benchmarks
   - CNI plugin comparison
   - Multi-format reports (JSON, HTML, Markdown)
   - Optimization recommendations

For complete documentation, see **[PERFORMANCE.md](PERFORMANCE.md)**.

## Additional Documentation

- **[PERFORMANCE.md](PERFORMANCE.md)** - Performance benchmarking and cleanup guide
- **[CICD.md](CICD.md)** - CI/CD pipeline integration examples
- **[MULTICLOUD.md](MULTICLOUD.md)** - Multi-cloud environment support
- **[REPORTING.md](REPORTING.md)** - Test reporting and visualization

## Development

### Adding New Tests

1. Add recipe file to project root: `XX-recipe-name.md`
2. Add test function to `lib/test-functions.sh`:
   ```bash
   test_recipe_XX() {
       echo "Testing NP-XX: Description"
       # Test implementation
       return 0  # or 1 for failure
   }
   ```
3. Tests are automatically discovered by the runner

### Modifying Test Logic

Edit individual test functions in `lib/test-functions.sh`. Each function:
- Receives `$TEST_NAMESPACE` as the isolated namespace
- Receives `$RECIPE_ID` as the recipe identifier
- Returns 0 for pass, non-zero for fail
- Outputs test details to stdout

## License

Same as parent project.

## Contributing

See parent project CONTRIBUTING.md for guidelines.
