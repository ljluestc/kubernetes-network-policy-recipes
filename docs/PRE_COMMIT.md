# Pre-commit Hooks Guide

This guide explains how to use pre-commit hooks in the Kubernetes Network Policy Recipes repository to ensure code quality, security, and consistency.

## Table of Contents

- [What are Pre-commit Hooks?](#what-are-pre-commit-hooks)
- [Installation](#installation)
- [Configured Hooks](#configured-hooks)
- [Running Hooks](#running-hooks)
- [Bypassing Hooks](#bypassing-hooks)
- [Troubleshooting](#troubleshooting)
- [CI/CD Integration](#cicd-integration)

## What are Pre-commit Hooks?

Pre-commit hooks are automated checks that run before you commit code. They help catch issues early:

- YAML syntax errors
- Shell script problems
- Markdown formatting issues
- Security vulnerabilities (leaked secrets)
- Missing tests
- Deprecated API versions

## Installation

### Prerequisites

- Python 3.8 or higher
- Git

### Install Pre-commit

```bash
# Using pip
pip install pre-commit

# Using pip3 (if pip doesn't work)
pip3 install pre-commit

# Using homebrew (macOS)
brew install pre-commit

# Using apt (Ubuntu/Debian)
sudo apt install pre-commit
```

### Install Git Hooks

After cloning the repository, install the pre-commit hooks:

```bash
cd kubernetes-network-policy-recipes
pre-commit install
```

This creates a Git hook that runs pre-commit checks automatically before each commit.

### Verify Installation

```bash
pre-commit --version
# Should show: pre-commit 3.x.x or higher
```

## Configured Hooks

### General File Checks

- **trailing-whitespace**: Removes trailing whitespace
- **end-of-file-fixer**: Ensures files end with a newline
- **check-yaml**: Validates YAML syntax
- **check-added-large-files**: Prevents committing files >1MB
- **check-merge-conflict**: Detects merge conflict markers
- **check-executables-have-shebangs**: Ensures scripts have shebangs
- **check-shebang-scripts-are-executable**: Makes shebang scripts executable

### YAML Linting

- **yamllint**: Enforces YAML style and best practices
  - Max line length: 120 characters
  - Allows multiple documents per file
  - Minimal spacing requirements for comments

### Shell Script Quality

- **shellcheck**: Lints bash/shell scripts for common errors
  - Ignores SC1090, SC1091 (sourcing non-constant paths)
- **shfmt**: Formats shell scripts consistently
  - 4-space indentation
  - Case indentation
  - Space redirects

### Markdown Linting

- **markdownlint**: Checks markdown formatting
  - Auto-fixes issues where possible
  - Disabled rules: MD013 (line length), MD033 (HTML), MD034 (bare URLs)

### Security

- **detect-secrets**: Scans for secrets and credentials
  - Uses `.secrets.baseline` for known false positives
  - Excludes lock files and taskmaster directory

### Custom Hooks

#### check-bats-tests

Ensures each numbered recipe file (XX-*.md) has a corresponding BATS test file.

**Location**: `test-framework/hooks/check-bats-tests.sh`

**Example**:
```bash
# If you add: 15-new-recipe.md
# You must also add: test-framework/bats-tests/recipes/15-*.bats
```

#### validate-k8s-api

Validates Kubernetes YAML files for:
- Deprecated API versions (extensions/v1beta1, networking.k8s.io/v1beta1)
- YAML syntax using `kubectl --dry-run` (if kubectl is installed)

**Location**: `test-framework/hooks/validate-k8s-api.sh`

### Markdown Link Checking

- **markdown-link-check**: Checks for broken links (manual stage only)
  - Configuration: `.markdown-link-check.json`
  - Run explicitly with: `pre-commit run --hook-stage manual markdown-link-check`

## Running Hooks

### Automatic (on commit)

Hooks run automatically when you commit:

```bash
git add .
git commit -m "Your commit message"
# Hooks run automatically here
```

### Manual (all files)

Run all hooks on all files:

```bash
pre-commit run --all-files
```

### Manual (specific files)

Run hooks on specific files:

```bash
pre-commit run --files 01-deny-all.md
```

### Manual (specific hook)

Run a specific hook:

```bash
pre-commit run shellcheck --all-files
pre-commit run yamllint --all-files
```

### Manual stages

Some hooks (like link checking) only run in manual stage:

```bash
pre-commit run --hook-stage manual
```

## Bypassing Hooks

### When to Bypass

Only bypass hooks when:
- You're working on WIP commits (use `--no-verify` cautiously)
- The hook is incorrectly flagging valid code
- You need to commit urgently and will fix issues later

### How to Bypass

#### Bypass all hooks for one commit

```bash
git commit --no-verify -m "WIP: work in progress"
```

#### Bypass specific hooks

Set environment variable:

```bash
SKIP=shellcheck,yamllint git commit -m "Skip specific hooks"
```

#### Bypass on CI (not recommended)

```bash
SKIP=all pre-commit run --all-files
```

### Important Notes

- **Never bypass security hooks** (detect-secrets) unless absolutely necessary
- **CI will still run hooks** - bypassing locally doesn't skip CI checks
- **Document why you bypassed** in commit message if you do

## Troubleshooting

### Hook Installation Failed

**Problem**: `pre-commit install` fails

**Solutions**:
```bash
# Ensure you're in the repository root
cd /path/to/kubernetes-network-policy-recipes

# Ensure Git repository is initialized
git status

# Reinstall with verbose output
pre-commit install --install-hooks -v
```

### Hook Execution Errors

#### yamllint fails

**Problem**: YAML files fail validation

**Solution**:
```bash
# Check specific file
yamllint path/to/file.yaml

# Auto-fix (manual)
# Edit file based on yamllint output
```

#### shellcheck fails

**Problem**: Shell scripts fail linting

**Solution**:
```bash
# Check specific file
shellcheck path/to/script.sh

# Common issues:
# - Use quotes around variables: "$VAR" not $VAR
# - Use [[ ]] instead of [ ] for conditionals
# - Declare variables as local in functions
```

#### detect-secrets fails

**Problem**: False positive secret detection

**Solution**:
```bash
# Add to baseline
detect-secrets scan --baseline .secrets.baseline

# Or update baseline
detect-secrets scan > .secrets.baseline

# Audit baseline
detect-secrets audit .secrets.baseline
```

#### BATS test check fails

**Problem**: Recipe file missing corresponding test

**Solution**:
```bash
# Create test file for recipe
touch test-framework/bats-tests/recipes/XX-recipe-name.bats

# Use existing tests as template
cp test-framework/bats-tests/recipes/01-deny-all-traffic.bats \
   test-framework/bats-tests/recipes/15-new-recipe.bats
```

### Performance Issues

**Problem**: Pre-commit hooks are slow

**Solutions**:

```bash
# Run only on changed files (default for git commits)
# This is automatic

# Skip expensive hooks during development
SKIP=markdown-link-check git commit -m "message"

# Update hook versions (may have performance improvements)
pre-commit autoupdate

# Clean and reinstall
pre-commit clean
pre-commit install --install-hooks
```

### Cache Issues

**Problem**: Hooks using stale cache

**Solution**:
```bash
# Clear cache
pre-commit clean

# Run with fresh environment
pre-commit run --all-files
```

### kubectl Not Found

**Problem**: `validate-k8s-api` hook warns kubectl not found

**Solution**:
```bash
# Install kubectl
# macOS
brew install kubectl

# Ubuntu/Debian
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# The hook will work but skip validation if kubectl is not installed
```

## CI/CD Integration

Pre-commit hooks automatically run in CI/CD pipelines:

### GitHub Actions

Workflow: `.github/workflows/test.yml`

```yaml
jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

### GitLab CI

Config: `.gitlab-ci.yml`

```yaml
pre-commit:
  stage: lint
  image: python:3.11-alpine
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```

### Jenkins

Jenkinsfile stage:

```groovy
stage('Pre-commit Checks') {
    steps {
        sh 'pip3 install pre-commit'
        sh 'pre-commit run --all-files'
    }
}
```

### Azure Pipelines

Config: `azure-pipelines.yml`

```yaml
- stage: PreCommit
  jobs:
    - job: PreCommitHooks
      steps:
        - task: UsePythonVersion@0
          inputs:
            versionSpec: '3.11'
        - bash: pip install pre-commit
        - bash: pre-commit run --all-files
```

### CI Behavior

- **Hooks run on all files** in CI (not just changed files)
- **Failures block merges** - fix issues before merge
- **Cache improves performance** - hook environments are cached
- **No bypass option** - all hooks must pass

## Best Practices

1. **Run hooks before pushing**
   ```bash
   pre-commit run --all-files
   ```

2. **Keep hooks updated**
   ```bash
   pre-commit autoupdate
   ```

3. **Review hook output carefully**
   - Don't blindly auto-fix
   - Understand what changed

4. **Add tests for new recipes immediately**
   - Don't wait for pre-commit to remind you

5. **Commit fixes separately**
   ```bash
   git add .
   pre-commit run --all-files
   # Fix issues
   git add .
   git commit -m "Fix pre-commit issues"
   ```

6. **Use meaningful commit messages**
   - Even if hooks auto-fix things

## Configuration Files

- `.pre-commit-config.yaml` - Main configuration
- `.secrets.baseline` - Secret detection baseline
- `.markdown-link-check.json` - Link checker config
- `test-framework/hooks/` - Custom hook scripts

## Getting Help

- **Pre-commit documentation**: https://pre-commit.com/
- **Hook issues**: Check individual tool documentation
  - yamllint: https://yamllint.readthedocs.io/
  - shellcheck: https://www.shellcheck.net/
  - markdownlint: https://github.com/DavidAnson/markdownlint
  - detect-secrets: https://github.com/Yelp/detect-secrets

- **Repository issues**: Open an issue on GitHub

## Examples

### Successful commit with hooks

```bash
$ git commit -m "Add new network policy recipe"
Trim trailing whitespace.................................................Passed
Fix end of files.........................................................Passed
Check YAML...............................................................Passed
Check for added large files..............................................Passed
Check for merge conflicts................................................Passed
Check BATS tests exist for recipes......................................Passed
Validate Kubernetes API versions.........................................Passed
[master abc1234] Add new network policy recipe
 2 files changed, 50 insertions(+)
```

### Failed commit with hook errors

```bash
$ git commit -m "Add recipe without test"
Check BATS tests exist for recipes......................................Failed
- hook id: check-bats-tests
- exit code: 1

ERROR: No BATS test found for recipe: 15-new-recipe.md
  Expected: test-framework/bats-tests/recipes/15-*.bats
  Please create a BATS test file for this recipe before committing.
```

### Auto-fixed files

```bash
$ git commit -m "Update docs"
Trim trailing whitespace.................................................Failed
- hook id: trailing-whitespace
- exit code: 1
- files were modified by this hook

Fixing README.md

Fix end of files.........................................................Passed
# ... other hooks ...

# Files were auto-fixed, add them again
$ git add .
$ git commit -m "Update docs"
# ... now passes ...
```

---

For more information, see the main [CONTRIBUTING.md](../CONTRIBUTING.md) guide.
