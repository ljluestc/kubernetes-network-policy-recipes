# GitLab CI/CD Quick Start Guide

## 5-Minute Setup

### Step 1: Fork or Clone Repository

```bash
git clone <your-gitlab-repo-url>
cd kubernetes-network-policy-recipes
```

### Step 2: Verify Pipeline Configuration

The enhanced `.gitlab-ci.yml` is already configured. You can push to trigger your first pipeline:

```bash
git add .
git commit -m "Initial commit with enhanced GitLab CI"
git push origin main
```

### Step 3: Monitor First Pipeline Run

1. Go to your GitLab project
2. Navigate to **CI/CD > Pipelines**
3. Watch the pipeline execute

**Expected first run**:
- ✅ Build stage: ~5-10 minutes (builds test runner image)
- ✅ Lint stage: ~2-3 minutes
- ✅ Scan stage: ~3-5 minutes
- ✅ BATS tests: ~10-15 minutes
- ✅ Kind tests: ~15-20 minutes (Calico, Cilium, Weave)
- ⏭️ Cloud tests: Skipped (requires schedule/manual trigger + credentials)

**Total time**: ~35-50 minutes for first run
**Subsequent runs**: ~15-25 minutes (with caching)

### Step 4: View Results

After pipeline completes:

1. **GitLab Pages**: Visit `https://<username>.gitlab.io/<project-name>`
2. **Test Reports**: Check **CI/CD > Pipelines > [Pipeline] > Tests**
3. **Artifacts**: Download from **CI/CD > Pipelines > [Pipeline] > Artifacts**

## Testing Locally (Before Push)

### Validate GitLab CI Syntax

```bash
# Install gitlab-ci-local (optional)
npm install -g gitlab-ci-local

# Validate syntax
gitlab-ci-local --list
```

### Run BATS Tests Locally

```bash
cd test-framework
./run-all-bats-tests.sh --verbose
```

### Run with kind Locally

```bash
# Create kind cluster
kind create cluster

# Run tests
cd test-framework
./parallel-test-runner.sh
```

## Quick Configuration Checklist

### Essential Setup (Required)

- [x] `.gitlab-ci.yml` exists in repository root
- [x] GitLab Runner available with Docker executor
- [x] GitLab Container Registry enabled

### Optional Setup (Recommended)

- [ ] **GitLab Pages**: Enable in **Settings > Pages**
- [ ] **Slack Notifications**: Set `SLACK_WEBHOOK_URL` in **Settings > CI/CD > Variables**
- [ ] **Pipeline Schedules**: Configure in **CI/CD > Schedules**

### Cloud Provider Setup (Optional)

Only needed for cloud provider testing:

- [ ] **GKE**: Set `GCP_SERVICE_KEY` and `GCP_PROJECT_ID`
- [ ] **EKS**: Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- [ ] **AKS**: Set Azure credentials (4 variables)

## Common First-Run Issues

### Issue: Build job fails with "Cannot connect to Docker daemon"

**Solution**: Ensure your GitLab Runner has Docker-in-Docker configured.

**Runner config.toml**:
```toml
[[runners]]
  [runners.docker]
    privileged = true
```

### Issue: Pages job succeeds but dashboard not accessible

**Solution**:
1. Ensure pipeline ran on `main` or `master` branch
2. Wait 5-10 minutes for GitLab Pages to deploy
3. Check **Settings > Pages** for the URL

### Issue: Tests timeout

**Solution**: Increase timeout in variables:

```yaml
variables:
  TEST_TIMEOUT: "900"  # Increase to 15 minutes
```

## Running Specific Tests

### Only Lint and Unit Tests (Fast)

Modify `.gitlab-ci.yml` to comment out cloud test jobs, or create `.gitlab-ci-fast.yml`:

```yaml
include:
  - local: '.gitlab-ci.yml'

# Disable cloud tests for faster iteration
test:gke:calico:
  rules:
    - when: never

test:eks:default:
  rules:
    - when: never

test:aks:azure-cni:
  rules:
    - when: never
```

Then run:
```bash
git ci -m "Fast CI" --ci-config-file=.gitlab-ci-fast.yml
```

### Manual Cloud Test Trigger

1. Go to **CI/CD > Pipelines**
2. Click **Run Pipeline**
3. Set variables:
   - `ENV_TYPE` = `production`
4. Click **Run Pipeline**

## Next Steps

1. **Customize**: Edit `.gitlab-ci.yml` to match your needs
2. **Schedule**: Set up nightly/weekly pipelines in **CI/CD > Schedules**
3. **Monitor**: Check GitLab Pages dashboard for trends
4. **Optimize**: Review caching and parallel execution settings

## Helpful Resources

- [Full Configuration Guide](./gitlab-ci-configuration.md)
- [Test Framework Documentation](../test-framework/README.md)
- [Network Policy Recipes](../README.md)

## Quick Commands Reference

```bash
# Validate pipeline locally
gitlab-ci-local --list

# Run BATS tests
cd test-framework && ./run-all-bats-tests.sh

# Run with specific CNI
cd test-framework && CNI_PLUGIN=calico ./parallel-test-runner.sh

# Clean up kind clusters
kind delete cluster --all

# Check test coverage
cd test-framework && ./generate-all-badges.sh

# View pipeline status
git log --oneline --decorate | head -10
```

## Getting Help

- **Pipeline Logs**: Check **CI/CD > Pipelines > [Job] > Logs**
- **Artifacts**: Download from **CI/CD > Pipelines > [Job] > Artifacts**
- **Issues**: Report at project issues page
- **Documentation**: See [gitlab-ci-configuration.md](./gitlab-ci-configuration.md)
