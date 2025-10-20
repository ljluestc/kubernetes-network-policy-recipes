# GitLab CI/CD Pipeline Configuration Guide

## Overview

The enhanced GitLab CI/CD pipeline provides comprehensive testing for Kubernetes Network Policy recipes across multiple platforms, CNI plugins, and Kubernetes versions. This guide covers setup, configuration, and usage.

## Features

### Core Capabilities

- **Multi-Platform Testing**: kind (local), GKE, EKS, AKS
- **Multiple CNI Plugins**: Calico, Cilium, Weave, Azure CNI, AWS VPC CNI
- **Kubernetes Version Matrix**: 1.27, 1.28, 1.29, 1.30
- **Container Registry Integration**: Build and cache test runner images
- **Advanced Caching**: Docker layer caching, dependency caching (30%+ faster builds)
- **Security Scanning**: Container scanning (Trivy), dependency scanning, secrets detection
- **Interactive Dashboards**: GitLab Pages with HTML reports and test metrics
- **Automated Notifications**: Slack integration for pipeline results
- **Pipeline Schedules**: Nightly and weekly test runs

### Pipeline Stages

1. **Build** - Build and push test runner container images to GitLab Container Registry
2. **Lint** - Code quality checks (pre-commit, shellcheck, yamllint)
3. **Scan** - Security scanning (container, dependencies, secrets)
4. **BATS Tests** - Unit tests with parallel execution across K8s versions
5. **Kind Tests** - Local testing with different CNI plugins
6. **Cloud Tests** - GKE, EKS, AKS testing (scheduled/manual)
7. **Integration** - End-to-end integration tests
8. **Report** - Aggregate results and generate badges
9. **Deploy** - GitLab Pages deployment with interactive dashboard
10. **Cleanup** - Resource cleanup

## Setup Instructions

### 1. Required GitLab CI/CD Variables

Configure these variables in GitLab UI: **Settings > CI/CD > Variables**

#### Essential Variables

```bash
# GitLab Container Registry (auto-configured)
CI_REGISTRY          # Automatically provided by GitLab
CI_REGISTRY_USER     # Automatically provided by GitLab
CI_REGISTRY_PASSWORD # Automatically provided by GitLab
CI_REGISTRY_IMAGE    # Automatically provided by GitLab
```

#### Optional: Cloud Provider Credentials

**Google Cloud Platform (GKE)**
```bash
GCP_SERVICE_KEY      # Base64-encoded GCP service account JSON
GCP_PROJECT_ID       # Your GCP project ID
```

**Amazon Web Services (EKS)**
```bash
AWS_ACCESS_KEY_ID        # AWS access key
AWS_SECRET_ACCESS_KEY    # AWS secret key
```

**Microsoft Azure (AKS)**
```bash
AZURE_CLIENT_ID          # Azure service principal client ID
AZURE_CLIENT_SECRET      # Azure service principal secret
AZURE_TENANT_ID          # Azure tenant ID
AZURE_SUBSCRIPTION_ID    # Azure subscription ID
```

#### Optional: Notifications

```bash
SLACK_WEBHOOK_URL    # Slack webhook URL for notifications
```

### 2. Enable GitLab Pages

1. Go to **Settings > Pages**
2. Ensure Pages are enabled for your project
3. After the first successful pipeline on `main`/`master`, your dashboard will be available at: `https://<username>.gitlab.io/<project-name>`

### 3. Configure Pipeline Schedules

Go to **CI/CD > Schedules** and create:

#### Nightly Full Test Run
- **Description**: Nightly comprehensive testing
- **Interval Pattern**: `0 2 * * *` (2 AM daily)
- **Target Branch**: `main` or `master`
- **Variables**:
  - `ENV_TYPE` = `staging`

#### Weekly Cloud Provider Tests
- **Description**: Weekly GKE/EKS/AKS testing
- **Interval Pattern**: `0 3 * * 0` (3 AM Sunday)
- **Target Branch**: `main` or `master`
- **Variables**:
  - `ENV_TYPE` = `production`

#### Weekly Container Cleanup
- **Description**: Clean up old Docker images
- **Interval Pattern**: `0 4 * * 1` (4 AM Monday)
- **Target Branch**: `main` or `master`

## Pipeline Configuration

### Environment Variables

Customize pipeline behavior with these variables (set in `.gitlab-ci.yml` or override via GitLab UI):

```yaml
# Test configuration
PARALLEL_JOBS: "4"              # Number of parallel test jobs
TEST_TIMEOUT: "600"             # Test timeout in seconds

# Environment type (affects which tests run)
ENV_TYPE: "development"         # Options: development, staging, production

# Security scanning
ENABLE_SECURITY_SCAN: "true"    # Enable container security scanning
ENABLE_DEPENDENCY_SCAN: "true"  # Enable dependency scanning

# Container registry
REGISTRY_IMAGE: "${CI_REGISTRY_IMAGE}/test-runner"
REGISTRY_TAG: "${CI_COMMIT_REF_SLUG}-${CI_COMMIT_SHORT_SHA}"

# Caching
DOCKER_BUILDKIT: "1"
BUILDKIT_INLINE_CACHE: "1"
```

### Kubernetes Versions

Modify tested Kubernetes versions in `.gitlab-ci.yml`:

```yaml
variables:
  K8S_VERSION_127: "1.27.3"
  K8S_VERSION_128: "1.28.0"
  K8S_VERSION_129: "1.29.0"
  K8S_VERSION_130: "1.30.0"
```

## Pipeline Behavior

### Automatic Triggers

The pipeline runs automatically on:

- **Push to `main`/`master`**: Full pipeline with GitLab Pages deployment
- **Merge Requests**: Build, lint, scan, and kind tests only
- **Scheduled Pipelines**: Full pipeline including cloud provider tests
- **Manual Trigger** (`Web`): Full pipeline including cloud provider tests

### Cloud Provider Tests

Cloud tests (GKE, EKS, AKS) only run when:
- Pipeline source is `schedule`
- Pipeline source is `web` (manual trigger)
- `ENV_TYPE` is `staging` or `production`

To run cloud tests manually:
1. Go to **CI/CD > Pipelines**
2. Click **Run Pipeline**
3. Select branch and optionally set `ENV_TYPE=production`

## Container Registry

### Test Runner Image

The pipeline builds a custom test runner image with all dependencies:
- kubectl, kind, helm
- Cloud CLIs (gcloud, aws, az)
- Test tools (BATS, parallel, jq, shellcheck)

**Image Location**: `registry.gitlab.com/<namespace>/<project>/test-runner:latest`

### Benefits

- **Faster tests**: Dependencies pre-installed
- **Consistency**: Same environment across all jobs
- **Caching**: Docker layer caching reduces build time by 30%+

## Caching Strategy

### Global Cache

```yaml
cache:
  key:
    files:
      - test-framework/requirements.txt
      - test-framework/package.json
    prefix: ${CI_COMMIT_REF_SLUG}
  paths:
    - test-framework/.cache/
    - ~/.cache/pip
    - ~/.cache/pre-commit
```

### Docker Cache

```yaml
cache:
  key: docker-${CI_COMMIT_REF_SLUG}
  paths:
    - docker-cache/
```

### Expected Performance Improvements

- **First run**: Full build (~5-10 minutes)
- **Subsequent runs**: Cached build (~2-3 minutes)
- **Overall improvement**: 30-50% faster pipeline execution

## GitLab Pages Dashboard

### Features

- **Interactive Dashboard**: Real-time test statistics
- **Test Reports**: Browse BATS, integration, and coverage reports
- **Test Matrix**: View supported platforms and plugins
- **Pipeline Info**: Track commit, branch, and pipeline details
- **Responsive Design**: Mobile-friendly interface

### Access

After deployment: `https://<username>.gitlab.io/<project-name>`

### Dashboard Sections

1. **Statistics**: Total tests, passed, failed, pass rate
2. **Pipeline Information**: Commit, branch, date, trigger source
3. **Test Reports**: Links to detailed reports
4. **Test Matrix**: Platforms, CNI plugins, K8s versions
5. **Recipes Tested**: List of all network policy recipes

## Security Scanning

### Container Scanning (Trivy)

Scans the test runner image for vulnerabilities:
- HIGH and CRITICAL severity vulnerabilities
- Generates JSON report
- Displays in GitLab Security Dashboard

### Dependency Scanning

Scans Python dependencies:
- Uses `safety` and `pip-audit`
- Checks for known vulnerabilities
- Generates detailed reports

### Secrets Scanning (TruffleHog)

Scans codebase for exposed secrets:
- API keys, passwords, tokens
- Fails pipeline if secrets detected
- Can be configured as warning-only

## Artifacts

### Artifact Types

1. **Test Results**
   - JUnit XML (for GitLab test reports)
   - TAP output
   - JSON summaries

2. **HTML Reports**
   - BATS test reports
   - Coverage reports
   - Integration test results

3. **Security Reports**
   - Container scan results (Trivy)
   - Dependency scan results
   - Secrets scan results

4. **Cluster Information**
   - Node details
   - Pod status
   - CNI configuration

### Artifact Retention

- **Test results**: 30 days
- **Reports**: 90 days
- **GitLab Pages**: 90 days

## Notifications

### Slack Integration

Configure `SLACK_WEBHOOK_URL` to receive notifications for:

**Success Notification** (on `main`/`master`):
```
✅ Network Policy tests PASSED on main
Branch: main
Commit: abc1234
Pipeline: #12345
Reports: View Dashboard
```

**Failure Notification** (on `main`/`master`):
```
❌ Network Policy tests FAILED on main
Branch: main
Commit: abc1234
Pipeline: #12345
Action: Check the logs for details
```

### Creating a Slack Webhook

1. Go to https://api.slack.com/apps
2. Create a new app
3. Enable "Incoming Webhooks"
4. Add webhook to your channel
5. Copy webhook URL to GitLab CI/CD variables

## Troubleshooting

### Common Issues

#### 1. Pipeline Fails at Build Stage

**Problem**: Docker build fails or timeout

**Solution**:
- Check runner has Docker-in-Docker enabled
- Verify runner has sufficient resources (2 CPU, 4GB RAM minimum)
- Check GitLab Container Registry is accessible

#### 2. Cloud Tests Don't Run

**Problem**: GKE/EKS/AKS tests are skipped

**Solution**:
- Ensure cloud credentials are configured in GitLab CI/CD variables
- Verify `ENV_TYPE` is set to `staging` or `production`, OR
- Run pipeline manually or via schedule

#### 3. GitLab Pages Not Deploying

**Problem**: Dashboard not accessible

**Solution**:
- Ensure pipeline ran on `main` or `master` branch
- Check GitLab Pages is enabled in project settings
- Verify `pages` job completed successfully
- Wait 5-10 minutes for Pages to deploy

#### 4. Cache Not Working

**Problem**: Pipeline doesn't seem faster on subsequent runs

**Solution**:
- Clear cache in **CI/CD > Pipelines > Clear runner caches**
- Check cache keys match between runs
- Verify runner supports caching

#### 5. Tests Timing Out

**Problem**: Tests fail with timeout errors

**Solution**:
- Increase `TEST_TIMEOUT` variable (default: 600 seconds)
- Check cluster creation isn't failing
- Verify network connectivity for CNI installation

### Debug Mode

Enable verbose output:

```yaml
variables:
  CI_DEBUG_TRACE: "true"  # Enable debug output (use carefully)
```

## Performance Optimization

### Recommended Settings

```yaml
# Optimal parallel execution
PARALLEL_JOBS: "8"  # For runners with 4+ CPU cores

# Faster feedback for MRs
only:
  - merge_requests
stages:
  - lint
  - bats-tests
  - test-kind  # Skip cloud tests for MRs
```

### Resource Requirements

**Minimum Runner Specs**:
- 2 CPU cores
- 4 GB RAM
- 20 GB disk space
- Docker-in-Docker support

**Recommended Runner Specs**:
- 4 CPU cores
- 8 GB RAM
- 50 GB disk space
- SSD storage

## Advanced Configuration

### Custom Test Selection

Run specific tests by modifying job scripts:

```yaml
test:kind:calico:
  script:
    - cd test-framework
    - ./run-all-bats-tests.sh --filter "01,02,03"  # Only recipes 01-03
```

### Custom CNI Plugins

Add new CNI plugins:

```yaml
test:kind:flannel:
  <<: *test_kind_template
  variables:
    CNI_PLUGIN: "flannel"
  script:
    - kind create cluster --config kind-config.yaml
    - kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
    - cd test-framework
    - ./parallel-test-runner.sh --skip-unsupported
```

### Pipeline Templates

Extend for other projects:

```yaml
include:
  - project: 'your-group/network-policy-recipes'
    file: '.gitlab-ci.yml'
```

## Monitoring and Metrics

### Pipeline Metrics

Track in GitLab:
- **CI/CD > Pipelines**: Overall success rate
- **CI/CD > Pipelines > Charts**: Duration trends
- **Repository > Analytics > CI/CD**: Pipeline efficiency

### Test Metrics

Monitor in GitLab Pages dashboard:
- Pass rate over time
- Test duration
- Platform-specific results
- Recipe coverage

## Cost Optimization

### Cloud Provider Testing

Cloud tests can be expensive. Optimize by:

1. **Scheduled Testing**: Run cloud tests weekly instead of per-commit
2. **Smaller Clusters**: Use minimum node counts
3. **Fast Cleanup**: Ensure `after_script` cleans up resources
4. **Spot Instances**: Configure cloud providers to use spot/preemptible instances

### Estimated Costs (per run)

- **GKE**: ~$0.50-1.00 per test run
- **EKS**: ~$0.40-0.80 per test run
- **AKS**: ~$0.40-0.80 per test run
- **kind**: Free (local)

**Monthly estimate** (with nightly kind + weekly cloud):
- Daily kind tests: Free
- Weekly cloud tests: ~$10-15/month

## Best Practices

1. **Use MR Pipelines**: Fast feedback with kind tests only
2. **Schedule Cloud Tests**: Weekly or on-demand for cost efficiency
3. **Monitor Cache Hit Rate**: Should be >80% after first run
4. **Keep Images Small**: Minimize test runner image size
5. **Parallel Execution**: Utilize all available runner cores
6. **Fail Fast**: Run linting and security scans early
7. **Clean Up**: Always clean up cloud resources in `after_script`

## Support and Contributing

### Getting Help

- Check GitLab pipeline logs for detailed error messages
- Review job artifacts for test results
- Consult this guide for configuration options

### Contributing

To improve the pipeline:

1. Fork the repository
2. Make changes to `.gitlab-ci.yml`
3. Test in your fork
4. Submit merge request with description

## References

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [GitLab Container Registry](https://docs.gitlab.com/ee/user/packages/container_registry/)
- [GitLab Pages](https://docs.gitlab.com/ee/user/project/pages/)
- [Docker-in-Docker](https://docs.gitlab.com/ee/ci/docker/using_docker_build.html)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
