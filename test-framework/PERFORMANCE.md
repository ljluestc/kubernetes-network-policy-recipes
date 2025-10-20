# Performance Benchmarking and Environment Cleanup

This guide covers the comprehensive performance benchmarking and automated cleanup capabilities for testing Kubernetes NetworkPolicies.

## Table of Contents

- [Overview](#overview)
- [Performance Benchmarking](#performance-benchmarking)
- [Environment Cleanup](#environment-cleanup)
- [Performance Analysis](#performance-analysis)
- [Best Practices](#best-practices)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)

## Overview

The performance testing suite provides three main capabilities:

1. **Performance Benchmarking** (`performance-benchmark.sh`) - Measure NetworkPolicy performance impact
2. **Environment Cleanup** (`cleanup-environment.sh`) - Automated cleanup and resource management
3. **Performance Analysis** (`analyze-performance.sh`) - Analyze trends and generate reports

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Performance Testing Suite                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────┐ │
│  │   Benchmark      │  │    Cleanup       │  │ Analysis │ │
│  │   Script         │  │    Script        │  │  Script  │ │
│  └────────┬─────────┘  └────────┬─────────┘  └────┬─────┘ │
│           │                     │                  │       │
│           ▼                     ▼                  ▼       │
│  ┌─────────────────────────────────────────────────────┐  │
│  │            Benchmark Results Storage                │  │
│  │         (JSON files in ./benchmark-results)         │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Performance Benchmarking

### Quick Start

```bash
# Run a simple benchmark
./test-framework/performance-benchmark.sh \
  --recipe 01-deny-all-traffic-to-an-application.md

# Create a baseline for future comparisons
./test-framework/performance-benchmark.sh \
  --recipe 01-deny-all-traffic-to-an-application.md \
  --baseline

# Compare against baseline
./test-framework/performance-benchmark.sh \
  --recipe 01-deny-all-traffic-to-an-application.md \
  --compare ./benchmark-results/baseline.json \
  --threshold 10 \
  --alert
```

### Measured Metrics

The benchmark tool measures:

#### 1. Enforcement Latency
- **What**: Time from policy application to enforcement
- **How**: Monitors connectivity changes after policy apply
- **Typical Range**: 0.5s - 5s depending on CNI

#### 2. Network Throughput Impact
- **What**: Percentage change in network throughput
- **How**: iperf3 tests before and after policy
- **Typical Range**: 0% - 15% impact

#### 3. Connection Latency Impact
- **What**: Percentage change in connection latency
- **How**: ping tests before and after policy
- **Typical Range**: 0% - 10% impact

#### 4. Resource Utilization
- **What**: CPU and memory usage during tests
- **How**: kubectl top pod metrics
- **Typical Range**: Varies by workload

### Command-Line Options

```bash
./performance-benchmark.sh [options]

Options:
  --recipe <file>         Recipe file to benchmark (required)
  --duration <seconds>    Test duration (default: 60)
  --baseline              Create baseline benchmark
  --compare <baseline>    Compare against baseline
  --output <dir>          Output directory (default: ./benchmark-results)
  --format <json|html>    Output format (default: json)
  --threshold <percent>   Regression threshold % (default: 10)
  --alert                 Enable alerting for regressions
  --verbose               Enable verbose output
  --help                  Show help message
```

### Benchmark Results Format

Results are stored as JSON files with the following structure:

```json
{
  "benchmark_id": "20251016_123456_a1b2c3d4",
  "timestamp": "20251016_123456",
  "recipe": "01-deny-all-traffic-to-an-application.md",
  "duration": "60",
  "cluster": {
    "version": "v1.28.0",
    "nodes": "3",
    "cni": "calico",
    "provider": "gke"
  },
  "enforcement": {
    "latency_seconds": "1.234"
  },
  "throughput": {
    "baseline_mbps": "1000.0",
    "policy_mbps": "950.0",
    "impact_percent": "5.0"
  },
  "latency": {
    "baseline_ms": "10.5",
    "policy_ms": "11.2",
    "impact_percent": "6.67"
  },
  "resources": {
    "baseline": {
      "cpu_millicores": "50",
      "memory_mb": "128"
    },
    "policy": {
      "cpu_millicores": "55",
      "memory_mb": "132"
    }
  }
}
```

### Baseline Management

Baselines help track performance regressions over time:

```bash
# Create baseline for a specific recipe
./performance-benchmark.sh \
  --recipe 02-limit-traffic-to-an-application.md \
  --baseline

# Compare current performance against baseline
./performance-benchmark.sh \
  --recipe 02-limit-traffic-to-an-application.md \
  --compare ./benchmark-results/baseline.json

# Baseline will be saved as: ./benchmark-results/baseline.json
```

### Performance Alerting

Enable alerts for performance regressions:

```bash
# Set webhook URL for alerts
export PERFORMANCE_ALERT_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Run benchmark with alerting
./performance-benchmark.sh \
  --recipe 03-deny-all-non-whitelisted-traffic-in-the-namespace.md \
  --compare ./benchmark-results/baseline.json \
  --threshold 10 \
  --alert
```

Alert format (Slack/Teams compatible):
```
Performance Regression Detected
Benchmark: 20251016_123456_a1b2c3d4
Enforcement Latency: 15.5%
Throughput: 12.3%
```

## Environment Cleanup

### Quick Start

```bash
# Cleanup a specific namespace
./test-framework/cleanup-environment.sh --namespace test-namespace

# Cleanup all test namespaces
./test-framework/cleanup-environment.sh --all-test-ns --force

# Dry run to see what would be cleaned
./test-framework/cleanup-environment.sh --all-test-ns --dry-run

# Cleanup resources older than 1 hour
./test-framework/cleanup-environment.sh --all-test-ns --age 1h --force
```

### Command-Line Options

```bash
./cleanup-environment.sh [options]

Options:
  --namespace <ns>        Cleanup specific namespace
  --all-test-ns          Cleanup all test namespaces
  --policies             Remove all NetworkPolicies
  --force                Force cleanup without confirmation
  --verify               Verify cleanup completed successfully
  --health-check         Run cluster health check after cleanup
  --dry-run              Show what would be cleaned up
  --age <duration>       Clean resources older than duration (e.g., 1h, 30m)
  --schedule             Enable scheduled cleanup
  --verbose              Enable verbose output
  --help                 Show help message
```

### Test Namespace Patterns

The cleanup tool automatically detects namespaces matching these patterns:

- `test-*`
- `perf-benchmark-*`
- `netpol-test-*`
- `recipe-test-*`

### Cleanup Operations

The tool performs the following cleanup operations in order:

1. **NetworkPolicy Removal** - Delete all policies in the namespace
2. **Pod Cleanup** - Force delete all pods
3. **Service Cleanup** - Remove all services
4. **Namespace Deletion** - Delete the namespace itself

### Orphaned Resource Detection

Automatically finds and reports:

- Pods without parent controllers
- Services without endpoints
- Namespaces stuck in Terminating state

```bash
# Find and cleanup orphaned resources
./cleanup-environment.sh --all-test-ns --verify --verbose
```

### Cleanup Verification

Verify that cleanup operations completed successfully:

```bash
./cleanup-environment.sh \
  --namespace test-ns \
  --verify \
  --health-check
```

Verification checks:
- Namespace deletion status
- Remaining resources count
- Stuck finalizers
- Resource pressure

### Scheduled Cleanup

Set up automated cleanup via cron:

```bash
# Generate cron configuration
./cleanup-environment.sh --schedule

# This creates: /tmp/netpol-cleanup-schedule
# Add to crontab: crontab -e

# Example schedule (daily at 2 AM, cleanup resources >24h old)
0 2 * * * /path/to/cleanup-environment.sh --all-test-ns --age 24h --force --verify --health-check
```

### Cleanup Report

Cleanup operations generate a summary report:

```json
{
  "timestamp": "2025-10-16T12:34:56+00:00",
  "summary": {
    "namespaces_cleaned": "5",
    "policies_removed": "23",
    "pods_removed": "45",
    "services_removed": "12",
    "errors": "0"
  }
}
```

Saved to: `./cleanup-results/cleanup-report-<timestamp>.json`

## Performance Analysis

### Quick Start

```bash
# Generate HTML analysis report
./test-framework/analyze-performance.sh \
  --results-dir ./benchmark-results \
  --format html \
  --output analysis-report.html

# Generate all format reports
./test-framework/analyze-performance.sh \
  --results-dir ./benchmark-results \
  --format all \
  --recommendations

# CNI comparison
./test-framework/analyze-performance.sh \
  --cni-comparison \
  --trend 30
```

### Command-Line Options

```bash
./analyze-performance.sh [options]

Options:
  --results-dir <dir>      Directory with benchmark results (default: ./benchmark-results)
  --output <file>          Output report file
  --format <type>          Report format: json, html, markdown, all (default: html)
  --compare <ids>          Compare specific benchmark IDs (comma-separated)
  --trend <days>           Analyze trends over N days (default: 30)
  --threshold <percent>    Highlight changes above threshold (default: 5)
  --cni-comparison         Generate CNI comparison report
  --recommendations        Include optimization recommendations
  --verbose                Enable verbose output
  --help                   Show help message
```

### Report Formats

#### JSON Report
Machine-readable format for CI/CD integration:
```json
{
  "report_type": "performance_analysis",
  "generated_at": "2025-10-16T12:34:56+00:00",
  "trends": { ... },
  "cni_comparison": { ... },
  "recommendations": [ ... ]
}
```

#### Markdown Report
Great for documentation and GitHub:
- Executive summary
- Performance trends table
- CNI comparison table
- Recommendations list

#### HTML Report
Interactive, visual report with:
- Color-coded metrics cards
- Sortable comparison tables
- Performance badges
- Trend visualizations

### Trend Analysis

The analysis tool calculates statistics across multiple benchmarks:

```
Enforcement Latency:
  Min:    0.5s
  Max:    2.1s
  Avg:    1.2s
  StdDev: 0.3s

Throughput Impact:
  Min:    2.0%
  Max:    8.5%
  Avg:    5.1%
  StdDev: 1.8%
```

### CNI Comparison

Compare performance across different CNI plugins:

```bash
./analyze-performance.sh \
  --results-dir ./benchmark-results \
  --cni-comparison \
  --format html
```

Example output:
```
| CNI Plugin | Avg Enforcement Latency | Avg Throughput Impact |
|------------|-------------------------|----------------------|
| Calico     | 1.2s                   | 5.0%                 |
| Cilium     | 0.8s                   | 3.5%                 |
| Weave      | 1.5s                   | 7.2%                 |
```

### Recommendations Engine

Automatically generates optimization recommendations based on metrics:

```bash
./analyze-performance.sh \
  --recommendations \
  --threshold 5
```

Example recommendations:
- "High policy enforcement latency detected (2.5s). Consider optimizing policy complexity."
- "Significant throughput impact (15%). Review policy rules for optimization opportunities."
- "High variability in enforcement latency. Investigate cluster load and resource constraints."

## Best Practices

### Benchmarking Best Practices

1. **Establish Baselines Early**
   ```bash
   ./performance-benchmark.sh --recipe <recipe> --baseline
   ```

2. **Run Multiple Iterations**
   ```bash
   for i in {1..5}; do
     ./performance-benchmark.sh --recipe <recipe>
   done
   ./analyze-performance.sh --trend 1
   ```

3. **Test on Representative Clusters**
   - Use production-like cluster sizes
   - Test on target CNI plugins
   - Include realistic workloads

4. **Monitor Long-Term Trends**
   ```bash
   # Weekly analysis
   ./analyze-performance.sh --trend 7 --format all
   ```

### Cleanup Best Practices

1. **Always Verify Cleanup**
   ```bash
   ./cleanup-environment.sh --verify --health-check
   ```

2. **Use Age-Based Cleanup**
   ```bash
   # Keep recent tests, cleanup old ones
   ./cleanup-environment.sh --all-test-ns --age 24h
   ```

3. **Dry Run First**
   ```bash
   ./cleanup-environment.sh --all-test-ns --dry-run
   ```

4. **Schedule Regular Cleanup**
   ```bash
   # Daily at 2 AM
   0 2 * * * /path/to/cleanup-environment.sh --all-test-ns --age 24h --force
   ```

### Analysis Best Practices

1. **Regular Reporting**
   ```bash
   # Weekly performance report
   ./analyze-performance.sh --trend 7 --format html --recommendations
   ```

2. **CNI Comparison Before Migration**
   ```bash
   ./analyze-performance.sh --cni-comparison --format all
   ```

3. **Track Regressions**
   ```bash
   ./analyze-performance.sh --threshold 5 --verbose
   ```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Performance Testing

on:
  pull_request:
    paths:
      - '*.md'
      - 'test-framework/**'

jobs:
  performance-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Setup Kubernetes
        uses: engineerd/setup-kind@v0.5.0

      - name: Run Performance Benchmark
        run: |
          ./test-framework/performance-benchmark.sh \
            --recipe ${{ matrix.recipe }} \
            --compare ./benchmark-results/baseline.json \
            --threshold 10 \
            --format html

      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: benchmark-results
          path: benchmark-results/

      - name: Cleanup
        if: always()
        run: |
          ./test-framework/cleanup-environment.sh \
            --all-test-ns --force --verify

    strategy:
      matrix:
        recipe:
          - 01-deny-all-traffic-to-an-application.md
          - 02-limit-traffic-to-an-application.md
```

### GitLab CI Example

```yaml
performance-test:
  stage: test
  script:
    - ./test-framework/performance-benchmark.sh --recipe $RECIPE --baseline
    - ./test-framework/analyze-performance.sh --format all
  artifacts:
    paths:
      - benchmark-results/
    expire_in: 30 days
  after_script:
    - ./test-framework/cleanup-environment.sh --all-test-ns --force
  parallel:
    matrix:
      - RECIPE:
        - 01-deny-all-traffic-to-an-application.md
        - 02-limit-traffic-to-an-application.md
```

### Scheduled Performance Monitoring

```bash
#!/bin/bash
# scheduled-performance-test.sh

# Run nightly performance tests
for recipe in *.md; do
  ./test-framework/performance-benchmark.sh \
    --recipe "$recipe" \
    --compare ./benchmark-results/baseline.json \
    --threshold 10 \
    --alert
done

# Generate weekly analysis
./test-framework/analyze-performance.sh \
  --trend 7 \
  --format all \
  --recommendations

# Cleanup old test resources
./test-framework/cleanup-environment.sh \
  --all-test-ns \
  --age 24h \
  --force \
  --verify
```

## Troubleshooting

### Benchmark Issues

**Problem**: "iperf3 connection timeout"
```bash
# Solution: Check pod readiness
kubectl wait --for=condition=Ready pod/server-pod -n <namespace> --timeout=120s

# Verify connectivity
kubectl exec client-pod -n <namespace> -- ping -c 3 server-service
```

**Problem**: "No metrics available"
```bash
# Solution: Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify metrics-server is running
kubectl get pods -n kube-system | grep metrics-server
```

**Problem**: "Benchmark results show 0 throughput"
```bash
# Solution: Check iperf3 pod logs
kubectl logs server-pod -n <namespace>

# Ensure network connectivity
kubectl exec client-pod -n <namespace> -- nc -zv server-service 5201
```

### Cleanup Issues

**Problem**: "Namespace stuck in Terminating"
```bash
# Solution: Check for finalizers
kubectl get namespace <namespace> -o json | jq '.spec.finalizers'

# Remove finalizers if safe
kubectl patch namespace <namespace> -p '{"spec":{"finalizers":null}}' --type merge
```

**Problem**: "Pods won't delete"
```bash
# Solution: Force delete
kubectl delete pod <pod> -n <namespace> --grace-period=0 --force

# If still stuck, check for PVC or PV issues
kubectl get pvc -n <namespace>
```

**Problem**: "Cleanup verification fails"
```bash
# Solution: Run detailed verification
./cleanup-environment.sh --namespace <namespace> --verify --verbose

# Check for orphaned resources
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>
```

### Analysis Issues

**Problem**: "No results found in time range"
```bash
# Solution: Check results directory
ls -la ./benchmark-results/

# Expand time range
./analyze-performance.sh --trend 60
```

**Problem**: "CNI comparison shows no data"
```bash
# Solution: Ensure benchmarks were run on different CNIs
./analyze-performance.sh --verbose

# Check benchmark metadata
jq '.cluster.cni' ./benchmark-results/*.json
```

## Advanced Usage

### Custom Benchmark Scenarios

Create custom benchmark scripts:

```bash
#!/bin/bash
# custom-benchmark.sh

# Test multiple recipes in sequence
RECIPES=(
  "01-deny-all-traffic-to-an-application.md"
  "02-limit-traffic-to-an-application.md"
  "03-deny-all-non-whitelisted-traffic-in-the-namespace.md"
)

for recipe in "${RECIPES[@]}"; do
  echo "Benchmarking: $recipe"
  ./test-framework/performance-benchmark.sh \
    --recipe "$recipe" \
    --duration 120 \
    --format html
done

# Generate comparison report
./test-framework/analyze-performance.sh \
  --format all \
  --recommendations
```

### Performance Regression Testing

```bash
#!/bin/bash
# regression-test.sh

# Run benchmark and compare with baseline
./performance-benchmark.sh \
  --recipe "$1" \
  --compare ./benchmark-results/baseline.json \
  --threshold 5 \
  --format json \
  --output /tmp/current-benchmark.json

# Check for regressions
if jq -e '.regression_detected == true' /tmp/current-benchmark.json; then
  echo "Performance regression detected!"
  exit 1
else
  echo "No regression detected"
  exit 0
fi
```

## References

- [Test Framework README](README.md)
- [CI/CD Integration Guide](CICD.md)
- [Multi-Cloud Support](MULTICLOUD.md)
- [Reporting Documentation](REPORTING.md)

---

**Need Help?**
- Report issues: [GitHub Issues](https://github.com/ahmetb/kubernetes-network-policy-recipes/issues)
- Contribute: [CONTRIBUTING.md](../CONTRIBUTING.md)
