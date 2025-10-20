# GitLab CI Deployment Checklist

## ✅ Pre-Deployment Checklist

### Required (Before First Push)

- [ ] **Validate configuration**
  ```bash
  ./validate-gitlab-ci.sh
  ```

- [ ] **Commit all files**
  ```bash
  git status
  # Ensure all new files are tracked:
  # - .gitlab-ci.yml
  # - docs/gitlab-ci-*.md
  # - GITLAB_CI_IMPLEMENTATION.md
  # - validate-gitlab-ci.sh
  # - DEPLOYMENT_CHECKLIST.md
  ```

- [ ] **Review pipeline configuration**
  ```bash
  # Check the pipeline file
  cat .gitlab-ci.yml | grep -E "^(stages:|[a-z-]+:)" | head -30
  ```

### Optional (Can Configure Later)

- [ ] **Enable GitLab Pages**
  1. Go to your GitLab project
  2. Settings > Pages
  3. Ensure "Pages" is enabled

- [ ] **Set up GitLab Runner**
  - Ensure you have a GitLab Runner with Docker executor
  - Runner must support Docker-in-Docker (privileged mode)
  - Minimum specs: 2 CPU, 4 GB RAM

## 🔐 GitLab CI/CD Variables

### Essential Variables (Auto-Configured)

These are automatically provided by GitLab:

✅ `CI_REGISTRY` - GitLab Container Registry URL
✅ `CI_REGISTRY_USER` - Registry username
✅ `CI_REGISTRY_PASSWORD` - Registry password
✅ `CI_REGISTRY_IMAGE` - Full image path

**No action needed** - GitLab provides these automatically!

### Optional: Cloud Provider Credentials

Only needed if you want to run cloud provider tests (GKE, EKS, AKS):

#### Google Cloud Platform (GKE)

Go to **Settings > CI/CD > Variables** and add:

- [ ] `GCP_SERVICE_KEY`
  - Type: Variable
  - Protected: Yes
  - Masked: Yes
  - Value: Base64-encoded GCP service account JSON
  ```bash
  # Create the value:
  cat gcp-service-account.json | base64 -w 0
  ```

- [ ] `GCP_PROJECT_ID`
  - Type: Variable
  - Value: Your GCP project ID (e.g., "my-project-12345")

#### Amazon Web Services (EKS)

- [ ] `AWS_ACCESS_KEY_ID`
  - Type: Variable
  - Protected: Yes
  - Masked: Yes

- [ ] `AWS_SECRET_ACCESS_KEY`
  - Type: Variable
  - Protected: Yes
  - Masked: Yes

#### Microsoft Azure (AKS)

- [ ] `AZURE_CLIENT_ID`
  - Type: Variable
  - Protected: Yes

- [ ] `AZURE_CLIENT_SECRET`
  - Type: Variable
  - Protected: Yes
  - Masked: Yes

- [ ] `AZURE_TENANT_ID`
  - Type: Variable

- [ ] `AZURE_SUBSCRIPTION_ID`
  - Type: Variable

### Optional: Notifications

- [ ] `SLACK_WEBHOOK_URL`
  - Type: Variable
  - Protected: No
  - Masked: Yes
  - Value: Your Slack webhook URL
  - See: https://api.slack.com/messaging/webhooks

## 📅 Pipeline Schedules

Configure in **CI/CD > Schedules**:

### 1. Nightly Full Test Run

- [ ] **Create schedule**
  - Description: "Nightly comprehensive tests"
  - Interval Pattern: `0 2 * * *` (2 AM daily)
  - Target Branch: `main` or `master`
  - Variables:
    - `ENV_TYPE` = `staging`

### 2. Weekly Cloud Provider Tests

- [ ] **Create schedule**
  - Description: "Weekly cloud provider testing"
  - Interval Pattern: `0 3 * * 0` (3 AM Sunday)
  - Target Branch: `main` or `master`
  - Variables:
    - `ENV_TYPE` = `production`

### 3. Weekly Cleanup

- [ ] **Create schedule**
  - Description: "Clean up old Docker images"
  - Interval Pattern: `0 4 * * 1` (4 AM Monday)
  - Target Branch: `main` or `master`

## 🚀 First Deployment

### 1. Commit and Push

```bash
# Add all new files
git add .gitlab-ci.yml \
  docs/gitlab-ci-configuration.md \
  docs/gitlab-ci-quick-start.md \
  GITLAB_CI_IMPLEMENTATION.md \
  validate-gitlab-ci.sh \
  DEPLOYMENT_CHECKLIST.md

# Commit
git commit -m "feat: Enhanced GitLab CI with multi-platform testing

- Add multi-platform testing (kind, GKE, EKS, AKS)
- Implement container registry integration
- Add GitLab Pages with interactive dashboard
- Implement advanced caching (30-50% improvement)
- Add security scanning (Trivy, safety, TruffleHog)
- Add pipeline schedules and environment variables
- Create comprehensive documentation

Implements subtask 12.2"

# Push to GitLab
git push origin main  # or master
```

### 2. Monitor First Pipeline

1. Go to **CI/CD > Pipelines** in GitLab
2. Watch the pipeline execute
3. Expected stages:
   - ✅ Build (~5-10 min) - Builds test runner image
   - ✅ Lint (~2-3 min) - Code quality checks
   - ✅ Scan (~3-5 min) - Security scanning
   - ✅ BATS Tests (~10-15 min) - Unit tests
   - ✅ Kind Tests (~15-20 min) - Local K8s tests
   - ⏭️ Cloud Tests - Skipped (requires schedule or manual)
   - ✅ Report (~2-3 min) - Aggregate results
   - ✅ Deploy (~3-5 min) - GitLab Pages
   - ✅ Cleanup (~1 min) - Resource cleanup

**Total first run**: ~35-50 minutes

### 3. View Results

After pipeline completes:

- **GitLab Pages**: `https://<username>.gitlab.io/<project-name>`
- **Test Reports**: CI/CD > Pipelines > [Pipeline] > Tests
- **Artifacts**: CI/CD > Pipelines > [Pipeline] > Download artifacts
- **Container Registry**: Packages & Registries > Container Registry

## ✅ Verification Checklist

After first successful pipeline:

- [ ] Pipeline completed successfully
- [ ] Container image pushed to registry
- [ ] GitLab Pages deployed (may take 5-10 minutes)
- [ ] Test reports visible in GitLab
- [ ] Artifacts downloadable
- [ ] Cache populated (check next run is faster)

## 🔍 Troubleshooting

### Pipeline Fails at Build Stage

**Issue**: Docker build fails

**Solutions**:
- Check runner has Docker-in-Docker enabled
- Verify runner config has `privileged = true`
- Check runner has internet access

### GitLab Pages Not Accessible

**Issue**: Dashboard not loading

**Solutions**:
- Wait 5-10 minutes after pipeline completes
- Check pipeline ran on `main`/`master` branch
- Verify Pages are enabled in Settings > Pages
- Check `pages` job completed successfully

### Tests Timing Out

**Issue**: Tests fail with timeout errors

**Solutions**:
- Increase `TEST_TIMEOUT` variable (default: 600s)
- Check network connectivity
- Verify runner has sufficient resources

### Cache Not Working

**Issue**: Subsequent runs not faster

**Solutions**:
- Clear cache: CI/CD > Pipelines > Clear runner caches
- Wait for 2-3 pipeline runs (cache warms up)
- Check runner supports caching

## 📊 Success Metrics

After 3-5 pipeline runs, you should see:

✅ **Performance**
- First run: ~35-50 minutes
- Cached runs: ~25-35 minutes
- Improvement: 30-50% faster

✅ **Test Coverage**
- All BATS tests passing
- Kind tests with 3 CNI plugins
- Integration tests complete
- Coverage reports generated

✅ **GitLab Pages**
- Dashboard accessible
- Test statistics accurate
- Reports linked correctly
- Interactive features working

✅ **Container Registry**
- Test runner image stored
- Tags: `latest` + commit SHA
- Image metadata available
- Cache hit rate >80%

## 📚 Next Steps

1. **Review dashboard**: Check GitLab Pages for test results
2. **Configure schedules**: Set up nightly/weekly runs
3. **Add cloud credentials**: Enable GKE/EKS/AKS tests (optional)
4. **Set up notifications**: Add Slack webhook (optional)
5. **Customize**: Adjust variables for your needs

## 📖 Additional Resources

- [Full Configuration Guide](docs/gitlab-ci-configuration.md)
- [Quick Start Guide](docs/gitlab-ci-quick-start.md)
- [Implementation Summary](GITLAB_CI_IMPLEMENTATION.md)
- [GitLab CI/CD Docs](https://docs.gitlab.com/ee/ci/)

---

**Ready to deploy?** Check all the boxes above and run your first pipeline! 🚀
