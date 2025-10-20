# CI/CD Integration Guide

Comprehensive guide for integrating Network Policy tests into your CI/CD pipelines.

## Overview

This project includes ready-to-use CI/CD configurations for:

- **GitHub Actions** - `.github/workflows/test.yml`
- **GitLab CI** - `.gitlab-ci.yml`
- **Jenkins** - `Jenkinsfile`
- **CircleCI** - `.circleci/config.yml`
- **Azure DevOps** - `azure-pipelines.yml`

All pipelines support:
- ✅ **BATS unit tests** - 115+ test cases across all recipes
- ✅ **Integration tests** - 25 complex scenarios
- ✅ **Pre-commit hooks** - Automated quality checks
- ✅ **Coverage tracking** - 95% threshold enforcement
- ✅ Parallel test execution
- ✅ Multi-environment testing (kind, minikube, cloud providers)
- ✅ CNI compatibility (Calico, Cilium, Weave)
- ✅ HTML report generation
- ✅ JUnit XML output
- ✅ Artifact management
- ✅ Slack/Teams notifications
- ✅ PR comments with results
- ✅ Badge generation

**For local testing, see [TESTING.md](../TESTING.md)**

## GitHub Actions

### Setup

The workflow is already configured in `.github/workflows/test.yml`. No additional setup required!

### Features

- **Automatic triggers**: Push, PR, schedule (daily at 2 AM UTC)
- **Matrix testing**: Multiple K8s versions (1.27, 1.28, 1.29) × CNI (Calico, Cilium)
- **Provider support**: kind (fast), minikube (scheduled)
- **BATS unit tests**: All 115+ recipe tests
- **Integration tests**: 25 complex scenarios
- **Pre-commit hooks**: Code quality checks
- **Coverage enforcement**: 95% threshold
- **PR comments**: Automated test result summaries
- **Badge generation**: Test status badges for README

### Usage

```yaml
# Already configured - just push your code!
git push origin feature/my-changes

# Manual trigger via workflow_dispatch
# Go to Actions → Network Policy Tests → Run workflow
```

### Configuration

Environment secrets required:
- `SLACK_WEBHOOK_URL` (optional) - For Slack notifications

### Example Output

```markdown
## ✅ Network Policy Test Results

All tests passed!

| Metric | Value |
|--------|-------|
| Total Tests | 15 |
| ✅ Passed | 15 |
| ❌ Failed | 0 |
| ⏱️ Timeout | 0 |
| 📊 Pass Rate | 100% |
```

### Viewing Results

1. Go to **Actions** tab
2. Click on workflow run
3. Download artifacts for detailed HTML reports
4. Check **Summary** for quick overview

## GitLab CI

### Setup

The pipeline is configured in `.gitlab-ci.yml`.

#### Required CI/CD Variables

Navigate to **Settings → CI/CD → Variables** and add:

```bash
# For GKE tests (optional)
GCP_SERVICE_KEY       # Base64-encoded service account JSON
GCP_PROJECT_ID        # Your GCP project ID

# For notifications (optional)
SLACK_WEBHOOK_URL     # Slack webhook for notifications
```

### Features

- **Stages**: setup → test → report → cleanup
- **Parallel jobs**: kind/Calico, kind/Cilium, GKE (scheduled)
- **GitLab Pages**: HTML reports published automatically
- **Artifact management**: 30-day retention
- **JUnit integration**: Native GitLab test reporting

### Usage

```bash
# Push to trigger
git push origin feature/my-changes

# View in GitLab
# CI/CD → Pipelines → [Your pipeline]
```

### GitLab Pages

HTML reports are automatically published to:
```
https://your-username.gitlab.io/kubernetes-network-policy-recipes/
```

Only on `master`/`main` branch.

### Manual GKE Testing

```bash
# Go to CI/CD → Pipelines → Run pipeline
# Select: test:gke:calico job
```

**⚠️ Warning**: GKE tests cost money! Cluster is auto-deleted after tests.

## Jenkins

### Setup

1. **Install plugins**:
   - Pipeline
   - HTML Publisher
   - JUnit
   - Email Extension (optional)

2. **Create Pipeline job**:
   - New Item → Pipeline
   - Configure → Pipeline Definition: Pipeline script from SCM
   - SCM: Git
   - Script Path: `Jenkinsfile`

3. **Configure credentials** (if using cloud):
   - Manage Jenkins → Credentials
   - Add `gcp-service-account` (file)
   - Add `aws-credentials` (username/password)

4. **Set environment variables**:
   ```groovy
   environment {
       GCP_PROJECT_ID = 'your-project-id'
       SLACK_WEBHOOK_URL = credentials('slack-webhook')
       EMAIL_RECIPIENTS = 'team@example.com'
   }
   ```

### Features

- **Parameterized builds**: Choose provider and CNI
- **Parallel stages**: Multiple cloud providers
- **HTML reports**: Published via HTML Publisher plugin
- **JUnit integration**: Test trend charts
- **Email notifications**: On failure
- **Workspace cleanup**: Automatic

### Usage

#### Manual Build

1. Go to job page
2. Click "Build with Parameters"
3. Select:
   - Provider: kind, minikube, gke, eks, aks
   - CNI: calico, cilium, weave
   - Skip Unsupported: true
4. Click "Build"

#### Automatic Builds

Configure SCM polling or webhooks:

```groovy
// In Jenkinsfile
triggers {
    pollSCM('H/5 * * * *')  // Poll every 5 minutes
}
```

### Viewing Results

- **Console Output**: Full test logs
- **Test Results**: JUnit graphs and trends
- **HTML Report**: Published reports with charts
- **Artifacts**: JSON results and summaries

## CircleCI

### Setup

1. **Connect repository** to CircleCI

2. **Add environment variables** (Project Settings → Environment Variables):
   ```bash
   # For cloud tests (optional)
   GCP_PROJECT_ID
   GCP_SERVICE_KEY
   AWS_ACCESS_KEY_ID
   AWS_SECRET_ACCESS_KEY

   # For notifications (optional)
   SLACK_ACCESS_TOKEN  # For Slack orb
   ```

3. **Enable workflows** in `.circleci/config.yml`

### Features

- **Parallelism**: Run tests across multiple nodes simultaneously
- **Orbs**: Kubernetes, Slack integration
- **Workflows**: `test` (on push/PR), `nightly` (scheduled)
- **Matrix testing**: Multiple K8s versions in parallel
- **Resource classes**: Configurable VM sizes

### Usage

```bash
# Push to trigger
git push origin feature/my-changes

# View on CircleCI
# Dashboard → Your project → [Pipeline]
```

### Workflows

**Test workflow** (on push/PR):
- `test-kind-calico`
- `test-kind-cilium`
- `generate-summary`
- `notify-slack` (on failure)

**Nightly workflow** (daily 2 AM UTC):
- All test jobs
- `test-k8s-versions` (1.27, 1.28, 1.29)
- Full report generation

### Artifacts

Download from:
- CircleCI UI → Job → Artifacts tab
- Includes: JSON results, HTML reports, summary

## Azure DevOps

### Setup

1. **Create pipeline**:
   - Pipelines → New Pipeline
   - Select repository
   - Existing Azure Pipelines YAML file
   - Path: `/azure-pipelines.yml`

2. **Configure variables** (optional):
   ```yaml
   # Library → Variable groups → Create new group
   Name: network-policy-secrets

   Variables:
   - SLACK_WEBHOOK_URL
   - GCP_PROJECT_ID
   - GCP_SERVICE_KEY
   ```

3. **Link variable group** to pipeline:
   ```yaml
   variables:
     - group: network-policy-secrets
   ```

### Features

- **Stages**: Test → Report
- **Multi-job parallelism**: kind/Calico, kind/Cilium, multi-version
- **Matrix strategy**: Test across K8s versions
- **Test results**: Native Azure DevOps integration
- **Artifacts**: Published with 30-day retention
- **Triggers**: Branch, PR, schedule

### Usage

```bash
# Push to trigger
git push origin feature/my-changes

# View in Azure DevOps
# Pipelines → [Your pipeline] → [Run]
```

### Viewing Results

- **Tests** tab: JUnit results with trends
- **Artifacts**: Download HTML reports
- **Summary**: Test coverage and pass rates
- **Logs**: Full console output

### Manual Runs

1. Pipelines → [Your pipeline]
2. Run pipeline
3. Select branch
4. Run

## Common Features Across All Platforms

### Test Filtering

All platforms support CNI-aware test filtering:

```bash
# Automatically skip unsupported tests for current CNI
./parallel-test-runner.sh --skip-unsupported
```

### Environment Detection

All pipelines automatically detect:
- Cloud provider (GKE, EKS, AKS, kind, minikube)
- CNI plugin (Calico, Cilium, Weave, Flannel)
- Kubernetes version
- Recommended timeout and workers

### Report Generation

All pipelines generate:
- **JSON results**: Machine-readable test data
- **HTML reports**: Interactive visualizations with Chart.js
- **JUnit XML**: For native CI/CD test integration
- **Summary**: Quick overview of results

### Artifact Management

All platforms store:
- Test results (JSON)
- HTML reports
- JUnit XML
- Test summaries
- Badges (where applicable)

Retention: 30 days (configurable)

## Best Practices

### 1. Fast Feedback with kind

Use kind for fast PR validation:

```yaml
# Run on every PR
on: pull_request
jobs:
  test-kind:
    # Fast local cluster
```

### 2. Comprehensive Nightly Tests

Use cloud providers or multi-version for nightly:

```yaml
# Run daily
schedule:
  - cron: '0 2 * * *'
jobs:
  test-gke:
    # Full cloud testing
```

### 3. Skip Unsupported Tests

Always use `--skip-unsupported` in CI:

```bash
./parallel-test-runner.sh --skip-unsupported
```

This prevents false failures on CNIs with partial support.

### 4. Artifact Retention

Keep results for trend analysis:

```yaml
artifacts:
  retention-days: 30  # GitHub Actions
  expire_in: 30 days  # GitLab CI
```

### 5. Notification Strategy

- **Slack**: Critical failures only (master/main)
- **Email**: All failures (Jenkins)
- **PR Comments**: Every PR (GitHub Actions)

### 6. Cost Optimization

**Cloud tests are expensive!** Strategies:

```yaml
# Only run cloud tests on schedule
only:
  - schedules
  - web

# Use smallest instance types
GKE_MACHINE_TYPE: e2-standard-2
EKS_INSTANCE_TYPE: t3.small

# Auto-delete clusters
after_script:
  - ./provision-cluster.sh --delete
```

### 7. Parallel Execution

Maximize parallelism for speed:

```yaml
# GitHub Actions
strategy:
  matrix:
    k8s: [1.27, 1.28, 1.29]
    cni: [calico, cilium]

# CircleCI
parallelism: 3

# Azure DevOps
strategy:
  matrix:
    k8s_1_27: ...
    k8s_1_28: ...
```

## Troubleshooting

### Tests Failing in CI but Pass Locally

**Symptom**: Tests pass on your machine, fail in CI

**Solutions**:
```bash
# 1. Check timeout (CI might be slower)
export TEST_TIMEOUT=120  # Increase from 60

# 2. Reduce parallel workers
export MAX_WORKERS=2  # Reduce from 4

# 3. Check CNI support
./parallel-test-runner.sh --detect
./parallel-test-runner.sh --skip-unsupported
```

### Cluster Creation Failing

**Symptom**: kind/minikube cluster fails to start

**Solutions**:
```bash
# 1. Check Docker daemon
docker ps

# 2. Increase resources (CI config)
resources:
  - cpu: 4
  - memory: 8192

# 3. Use lighter configuration
--workers 1  # Single worker node
```

### Artifacts Not Uploading

**Symptom**: HTML reports missing

**Solutions**:
```yaml
# Ensure paths are correct
artifacts:
  paths:
    - test-framework/results/**/*.json
    - test-framework/results/**/*.html

# Use 'when: always'
when: always  # Upload even on failure
```

### Notifications Not Sending

**Symptom**: No Slack/email notifications

**Solutions**:
```bash
# 1. Verify webhook URL
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d '{"text":"Test"}'

# 2. Check environment variables
echo $SLACK_WEBHOOK_URL

# 3. Verify secret/variable configuration
# GitHub: Settings → Secrets
# GitLab: Settings → CI/CD → Variables
# Jenkins: Credentials
```

## Advanced Configuration

### Custom Test Matrix

Add more K8s versions:

```yaml
# GitHub Actions
strategy:
  matrix:
    k8s: ['1.25.0', '1.26.0', '1.27.3', '1.28.0', '1.29.0']
```

### Cloud Provider Testing

#### GKE

```bash
export GKE_REGION=us-central1
export GKE_MACHINE_TYPE=e2-standard-2
./provision-cluster.sh --provider gke --name np-test
```

#### EKS

```bash
export AWS_REGION=us-west-2
export EKS_INSTANCE_TYPE=t3.medium
./provision-cluster.sh --provider eks --name np-test
```

#### AKS

```bash
export AKS_LOCATION=eastus
export AKS_VM_SIZE=Standard_B2s
./provision-cluster.sh --provider aks --name np-test
```

### Badge Integration

#### GitHub Actions

Add to README.md:

```markdown
![Tests](https://github.com/your-org/repo/actions/workflows/test.yml/badge.svg)
```

#### GitLab CI

```markdown
![Pipeline](https://gitlab.com/your-org/repo/badges/master/pipeline.svg)
```

#### CircleCI

```markdown
![CircleCI](https://circleci.com/gh/your-org/repo.svg?style=svg)
```

### Conditional Execution

Run specific tests based on changes:

```yaml
# GitHub Actions - paths-filter
- uses: dorny/paths-filter@v2
  id: filter
  with:
    filters: |
      recipes:
        - '[0-9][0-9]*.md'

- name: Run tests
  if: steps.filter.outputs.recipes == 'true'
```

## Performance Optimization

### Caching

Speed up builds with caching:

```yaml
# GitHub Actions
- uses: actions/cache@v3
  with:
    path: ~/.kind
    key: ${{ runner.os }}-kind-${{ hashFiles('**/kind-config.yaml') }}
```

### Parallel Jobs

Maximize parallelism:

| Platform | Strategy |
|----------|----------|
| GitHub Actions | Matrix: 20 parallel jobs |
| GitLab CI | Parallel: Unlimited |
| CircleCI | Parallelism: 3-16 (paid) |
| Jenkins | Parallel stages |
| Azure DevOps | Matrix: Unlimited |

### Resource Allocation

Optimize CI resources:

```yaml
# More CPUs = faster tests
resources:
  - cpu: 4  # vs 2
  - memory: 8192  # vs 4096

# More workers = more parallelism
MAX_WORKERS: 8  # vs 4
```

## Migration Guide

### From Manual Testing

1. Choose your CI platform
2. Copy the appropriate config file
3. Configure secrets/variables
4. Push to trigger first run
5. Adjust timeout/workers if needed

### From Existing CI

1. Add our test job to your pipeline
2. Install dependencies (kubectl, parallel, jq)
3. Run `./parallel-test-runner.sh`
4. Publish artifacts and results

Example (GitHub Actions):

```yaml
- name: Network Policy Tests
  run: |
    cd test-framework
    ./parallel-test-runner.sh --skip-unsupported

- uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: test-framework/results/
```

## Common CI/CD Issues and Solutions

### BATS Tests Failing in CI

**Symptom**: BATS tests pass locally but fail in CI

**Common Causes**:
- Timeout too short for CI environment
- CNI not fully initialized
- Resource constraints

**Solutions**:
```bash
# In CI config, increase timeout
export TEST_TIMEOUT=120  # Default is 60

# Wait longer for CNI initialization
# In workflow, add sleep after cluster creation:
- name: Wait for CNI
  run: kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s

# Reduce parallel workers
export MAX_WORKERS=2

# Increase pod ready wait time
# In BATS tests, use longer timeout:
kubectl wait --for=condition=Ready pod/app -n $NS --timeout=120s
```

### Integration Tests Timing Out

**Symptom**: Integration tests fail with timeout errors

**Solutions**:
```bash
# Increase test timeout in run-integration-tests.sh
export INTEGRATION_TEST_TIMEOUT=300  # 5 minutes

# Add more time for policy enforcement
# In integration test scenarios, increase sleep:
sleep 15  # Instead of sleep 5

# Check if pods are actually ready
kubectl get pods --all-namespaces
kubectl describe pod <pod-name> -n <namespace>
```

### Pre-commit Hooks Failing in CI

**Symptom**: Pre-commit checks fail in CI pipeline

**Common Issues**:

1. **Python version mismatch**:
   ```yaml
   # Use consistent Python version
   - uses: actions/setup-python@v5
     with:
       python-version: '3.11'
   ```

2. **Cache issues**:
   ```yaml
   # Clear pre-commit cache
   - run: pre-commit clean
   - run: pre-commit run --all-files
   ```

3. **Hook version outdated**:
   ```bash
   # Update hooks
   pre-commit autoupdate
   git add .pre-commit-config.yaml
   git commit -m "Update pre-commit hooks"
   ```

### Coverage Threshold Failing

**Symptom**: CI fails with "Coverage below 95% threshold"

**Solutions**:
```bash
# Check which recipes are missing tests
cd test-framework
./lib/coverage-tracker.sh report
./lib/coverage-enforcer.sh all

# Create missing BATS tests
# For each recipe without test:
touch bats-tests/recipes/XX-recipe-name.bats
# Copy template from existing test

# Verify coverage improved
./lib/coverage-tracker.sh report
```

### CNI Plugin Not Working

**Symptom**: NetworkPolicies not enforcing in CI

**Solutions**:
```bash
# Verify CNI is installed
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# Check CNI logs
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50

# Reinstall CNI (in CI config)
kubectl delete -f calico.yaml
kubectl apply -f calico.yaml
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s

# Use --skip-unsupported flag
./parallel-test-runner.sh --skip-unsupported
```

### Artifact Upload Failing

**Symptom**: Test results not uploaded as artifacts

**Solutions**:
```yaml
# GitHub Actions - ensure paths exist
- uses: actions/upload-artifact@v4
  if: always()  # Upload even on failure
  with:
    name: test-results
    path: |
      test-framework/results/**/*.json
      test-framework/results/**/*.html
      test-framework/results/**/*.xml
    if-no-files-found: warn  # Don't fail if missing
```

### Badge Generation Failing

**Symptom**: Coverage badges not updating

**Solutions**:
```bash
# Verify coverage report exists
cat test-framework/results/coverage-report.json

# Check badge files generated
ls -la badges/

# Regenerate badges manually
cd test-framework
./lib/coverage-tracker.sh report
./lib/badge-generator.sh all

# Verify badge JSON format
cat badges/coverage.json
jq . badges/coverage.json  # Should be valid JSON
```

### Cluster Creation Failing

**Symptom**: kind or minikube cluster fails to create

**Solutions**:
```yaml
# kind - increase Docker resources
resources:
  limits:
    cpu: 4
    memory: 8192

# Use specific kind version
- name: Create kind cluster
  uses: helm/kind-action@v1
  with:
    version: v0.20.0
    cluster_name: np-test

# minikube - specify driver
- run: minikube start --driver=docker --cni=calico
```

### Namespace Cleanup Issues

**Symptom**: Test namespaces not being deleted

**Solutions**:
```bash
# Add cleanup step to CI config
- name: Cleanup test namespaces
  if: always()
  run: |
    kubectl get namespaces -o name | \
      grep -E 'np-test-|integration-' | \
      xargs kubectl delete --wait=false || true

# Force delete stuck namespaces
kubectl delete namespace <ns> --grace-period=0 --force

# Use automated cleanup script
./test-framework/cleanup-environment.sh --all-test-ns --force
```

## Debugging CI/CD Pipelines

### Enable Debug Logging

**GitHub Actions**:
```yaml
- name: Run tests with debug
  run: |
    set -x  # Enable bash debug
    cd test-framework
    ./run-all-bats-tests.sh --verbose
  env:
    ACTIONS_STEP_DEBUG: true
```

**GitLab CI**:
```yaml
test:
  script:
    - set -x
    - cd test-framework
    - bash -x ./run-all-bats-tests.sh
  variables:
    CI_DEBUG_TRACE: "true"
```

### Access CI Logs

**GitHub Actions**:
- Go to Actions tab
- Click workflow run
- Click failed job
- Expand failed step
- Download logs (top right)

**GitLab CI**:
- Go to CI/CD → Pipelines
- Click pipeline
- Click failed job
- View logs
- Download logs (right side)

### Test Locally with CI Environment

**Replicate GitHub Actions locally**:
```bash
# Install act
brew install act  # macOS
# OR
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Run workflow locally
act -j test

# Run specific job
act -j bats-tests
```

**Replicate GitLab CI locally**:
```bash
# Install gitlab-runner
brew install gitlab-runner  # macOS

# Run pipeline locally
gitlab-runner exec docker test
```

## Performance Optimization for CI/CD

### Speed Up Cluster Creation

```yaml
# Use cached images
- uses: actions/cache@v3
  with:
    path: ~/.kind/images
    key: kind-images-${{ hashFiles('**/kind-config.yaml') }}

# Pre-pull images
- run: docker pull kindest/node:v1.27.3
```

### Parallel Job Execution

```yaml
# GitHub Actions - maximum parallelism
strategy:
  matrix:
    test: [01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14]
  max-parallel: 10

# Run each recipe in parallel job
- run: bats test-framework/bats-tests/recipes/${{ matrix.test }}-*.bats
```

### Cache Dependencies

```yaml
# Cache pre-commit hooks
- uses: actions/cache@v3
  with:
    path: ~/.cache/pre-commit
    key: pre-commit-${{ hashFiles('.pre-commit-config.yaml') }}

# Cache BATS libraries
- uses: actions/cache@v3
  with:
    path: test-framework/bats-libs
    key: bats-libs-${{ hashFiles('test-framework/bats-libs/**') }}
```

## Best Practices Summary

1. **Use kind for PR testing** - Fast feedback on every PR
2. **Cloud testing scheduled only** - Avoid cloud costs on every push
3. **Always upload artifacts** - Keep test history for debugging
4. **Enforce coverage thresholds** - Maintain test quality
5. **Cache dependencies** - Speed up pipeline execution
6. **Run pre-commit in CI** - Catch issues early
7. **Use --skip-unsupported** - Prevent false CNI failures
8. **Enable debug logging** - Easy troubleshooting
9. **Clean up namespaces** - Prevent resource exhaustion
10. **Monitor pipeline duration** - Optimize slow steps

## Additional Resources

- [TESTING.md](../TESTING.md) - Complete testing guide
- [COVERAGE.md](COVERAGE.md) - Coverage system documentation
- [PERFORMANCE.md](PERFORMANCE.md) - Performance testing
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [GitLab CI Docs](https://docs.gitlab.com/ee/ci/)
- [Jenkins Pipeline Docs](https://www.jenkins.io/doc/book/pipeline/)

## License

Same as parent project.
