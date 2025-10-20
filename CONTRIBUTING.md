---
id: NP-CONTRIBUTING
title: Contributing to Kubernetes Network Policy Recipes
type: documentation
category: meta
priority: medium
status: ready
estimated_time: 10m
dependencies: []
tags: [contributing, community, cla, code-review]
---

## Overview

We welcome your contributions to this Kubernetes Network Policy Recipes project! This guide outlines the process for contributing patches, improvements, and new recipes to the repository.

## Objectives

- Understand the contribution process
- Complete necessary legal requirements
- Follow code review procedures
- Maintain quality and consistency
- Build a collaborative community

## Contribution Requirements

### Pre-commit Hooks (Required)

All contributors must use pre-commit hooks to ensure code quality and consistency.

**Installation:**
```bash
# Install pre-commit
pip install pre-commit

# Install hooks in your local repository
cd kubernetes-network-policy-recipes
pre-commit install
```

**What hooks check:**
- YAML syntax and formatting
- Shell script linting (shellcheck)
- Markdown formatting
- Security (secret detection)
- Kubernetes API version validation
- BATS test existence for new recipes

**Running hooks:**
```bash
# Automatic on commit
git commit -m "Your message"

# Manual on all files
pre-commit run --all-files

# Manual on specific files
pre-commit run --files path/to/file
```

For detailed information, see [Pre-commit Hooks Guide](docs/PRE_COMMIT.md).

### Contributor License Agreement

Contributions to this project must be accompanied by a Contributor License Agreement (CLA). You (or your employer) retain the copyright to your contribution; this simply gives us permission to use and redistribute your contributions as part of the project.

**CLA Submission:**
- Visit <https://cla.developers.google.com/> to see your current agreements on file or to sign a new one
- You generally only need to submit a CLA once
- If you've already submitted one (even if it was for a different project), you probably don't need to do it again

**Important Notes:**
- Individual contributors sign individual CLA
- Corporate contributors require corporate CLA signed by employer
- CLA must be on file before pull requests can be merged

## Code Review Process

### Pull Request Requirements

All submissions, including submissions by project members, require review. We use GitHub pull requests for this purpose.

**Before Submitting:**
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test your changes thoroughly
5. Commit with clear, descriptive messages
6. Push to your fork
7. Open a pull request

**Pull Request Guidelines:**
- Clear title describing the change
- Detailed description of what changed and why
- Reference any related issues
- Include testing steps if applicable
- Ensure all tests pass
- Follow existing code style and formatting

### Review Process

**Timeline:**
- Initial review typically within 2-3 business days
- Follow-up reviews within 1-2 business days
- Merge after approval from maintainers

**Review Criteria:**
- Code quality and correctness
- Documentation completeness
- Adherence to project standards
- Test coverage (if applicable)
- Security considerations
- Performance implications

**Addressing Feedback:**
- Respond to all review comments
- Make requested changes promptly
- Push updates to the same branch
- Request re-review when ready

## Contribution Types

### New NetworkPolicy Recipes

When contributing new recipes:

**Required Elements:**
- YAML frontmatter with metadata (id, title, type, category, priority, status, estimated_time, dependencies, tags)
- Clear overview and objectives
- Comprehensive background and use cases
- Step-by-step requirements with tasks
- Complete YAML manifests
- Testing instructions
- Acceptance criteria
- Technical specifications
- Implementation details
- Verification steps
- Cleanup procedures
- References and notes

**Recipe Template:**
```yaml
---
id: NP-XX
title: Recipe Title
type: policy
category: [basics|namespaces|advanced|egress]
priority: [high|medium|low]
status: ready
estimated_time: XXm
dependencies: [NP-00]
tags: [relevant, tags, here]
---

## Overview
## Objectives
## Background
## Requirements
## Acceptance Criteria
## Technical Specifications
## Implementation Details
## Verification
## Cleanup
## References
## Notes
```

### Documentation Improvements

We welcome:
- Clarifications and corrections
- Additional examples
- Troubleshooting tips
- Best practices
- Common patterns
- Performance notes
- Security considerations

### Bug Reports

When reporting bugs:
- Use GitHub Issues
- Provide clear description
- Include steps to reproduce
- Share relevant environment details
- Attach logs if applicable
- Specify expected vs actual behavior

### Feature Requests

For new features:
- Check existing issues first
- Describe the use case
- Explain expected benefits
- Suggest implementation approach
- Consider backward compatibility

## Style Guidelines

### Markdown Formatting

- Use ATX-style headers (# Header)
- Wrap lines at 80-100 characters where practical
- Use code blocks with language specification
- Include alt text for images
- Use consistent bullet point style

### YAML Style

- 2-space indentation
- No tabs
- Quote strings when necessary
- Comment complex configurations
- Follow Kubernetes conventions

### Command Examples

```bash
# Use clear, copy-pasteable commands
kubectl apply -f policy.yaml

# Show expected output
# Expected:
# networkpolicy "example" created

# Include comments for clarity
```

## Testing

**Comprehensive Testing Guide**: See [TESTING.md](TESTING.md) for complete testing documentation.

### Testing Requirements

All contributions must meet these testing requirements:

1. **Pre-commit hooks pass** - All hooks must pass before committing
2. **BATS tests required** - Every new recipe must have BATS unit tests
3. **Integration tests** - Complex scenarios need integration tests
4. **Coverage threshold** - Overall coverage must be ≥ 95%
5. **Manual verification** - Test on actual Kubernetes cluster

### Quick Testing Checklist

```bash
# 1. Install pre-commit hooks (first time only)
pip install pre-commit
pre-commit install

# 2. Run pre-commit checks
pre-commit run --all-files

# 3. Run BATS tests locally
cd test-framework
./run-all-bats-tests.sh

# 4. Run integration tests (if applicable)
./run-integration-tests.sh

# 5. Check coverage
./lib/coverage-tracker.sh report
./lib/coverage-enforcer.sh all
```

### Adding Tests for New Recipes

When adding a new NetworkPolicy recipe:

**Required: BATS Unit Test**

1. Create test file: `test-framework/bats-tests/recipes/XX-recipe-name.bats`
2. Include these test cases:
   - YAML syntax validation
   - Policy application
   - Traffic blocking (if deny policy)
   - Traffic allowing (if allow policy)
   - Label selector matching
   - Policy retrieval via kubectl
3. Use existing tests as templates
4. Verify locally: `bats test-framework/bats-tests/recipes/XX-recipe-name.bats`

**Optional: Integration Test**

Add integration test if recipe involves:
- Multiple policies working together
- Cross-namespace communication
- Complex multi-tier scenarios
- Performance-sensitive configurations

See [TESTING.md#writing-new-tests](TESTING.md#writing-new-tests) for detailed instructions.

### Pre-commit Checks

Before committing, ensure all pre-commit hooks pass:

```bash
# Run all hooks
pre-commit run --all-files

# Check specific aspects
pre-commit run yamllint --all-files      # YAML files
pre-commit run shellcheck --all-files    # Shell scripts
pre-commit run check-bats-tests          # Test coverage
```

**Pre-commit will automatically check:**
- YAML syntax and formatting
- Shell script linting (shellcheck)
- Markdown formatting
- Security (secret detection)
- Kubernetes API version validation
- BATS test existence for recipes

See [docs/PRE_COMMIT.md](docs/PRE_COMMIT.md) for complete pre-commit documentation.

### Manual Testing

Before submitting a pull request:

1. **Create test cluster** (if you don't have one)
   ```bash
   # Using kind
   kind create cluster --name np-test
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
   ```

2. **Apply the policy**
   ```bash
   kubectl apply -f XX-recipe-name.md
   ```

3. **Verify expected behavior**
   ```bash
   # Create test pods
   kubectl run web --image=nginx --labels="app=web"
   kubectl run client --image=nginx --labels="app=client"

   # Test connectivity
   kubectl exec client -- wget -qO- --timeout=2 http://web
   ```

4. **Test edge cases**
   - Empty selectors
   - Cross-namespace scenarios
   - Port restrictions
   - Egress/ingress isolation

5. **Clean up resources**
   ```bash
   kubectl delete networkpolicy <policy-name>
   kubectl delete pod web client
   ```

6. **Document test results** in PR description

### CI/CD Testing

All pull requests trigger automated testing:

- **GitHub Actions** - Runs on every PR
  - Pre-commit hooks (all files)
  - BATS unit tests (115+ tests)
  - Integration tests (25 scenarios)
  - Coverage enforcement (95% threshold)
  - Performance regression checks

**PR must pass all CI checks before merge.**

See [test-framework/CICD.md](test-framework/CICD.md) for CI/CD documentation.

### Coverage Requirements

| Metric | Minimum | Target | Status |
|--------|---------|--------|--------|
| Overall Coverage | 95% | 100% | Enforced in CI |
| BATS Unit Tests | 95% | 100% | Warning if below |
| Integration Tests | 90% | 100% | Warning if below |
| Recipe Coverage | 100% | 100% | Enforced in CI |

**Coverage is automatically calculated and enforced in CI/CD.**

Generate coverage report locally:
```bash
cd test-framework
./lib/coverage-tracker.sh report
./lib/coverage-tracker.sh html
open results/coverage-report.html
```

See [test-framework/COVERAGE.md](test-framework/COVERAGE.md) for coverage system documentation.

### Test Checklist

Before submitting your PR, verify:

- [ ] Pre-commit hooks pass (`pre-commit run --all-files`)
- [ ] BATS test exists for new recipe (in `test-framework/bats-tests/recipes/`)
- [ ] BATS test passes locally (`bats test-framework/bats-tests/recipes/XX-*.bats`)
- [ ] Integration test added if needed
- [ ] Policy applies without errors (`kubectl apply -f XX-recipe.md`)
- [ ] Target pods correctly selected (`kubectl get networkpolicy -o yaml`)
- [ ] Allowed traffic flows as expected (tested with `kubectl exec`)
- [ ] Blocked traffic is actually blocked (tested with `kubectl exec`)
- [ ] DNS resolution works if applicable
- [ ] Coverage threshold maintained (≥ 95%)
- [ ] Cleanup removes all resources
- [ ] Instructions are clear and accurate
- [ ] CI/CD checks pass on GitHub

### Troubleshooting Test Failures

If tests fail, see [TESTING.md#troubleshooting](TESTING.md#troubleshooting) for solutions to common issues:

- Tests passing locally but failing in CI
- Pods not starting
- NetworkPolicy not enforcing
- Coverage threshold failures
- Pre-commit hook errors

---

For complete testing documentation, see **[TESTING.md](TESTING.md)**.

## Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Provide constructive feedback
- Focus on the technical merits
- Assume good intentions
- Help others learn

### Communication

- GitHub Issues for bugs and features
- Pull requests for contributions
- Discussions for questions
- Kubernetes Slack #sig-network for community chat

## Getting Help

### Resources

- [GitHub Help - Pull Requests](https://help.github.com/articles/about-pull-requests/)
- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Contributor Guide](https://kubernetes.io/docs/contribute/)

### Questions

- Check existing issues and documentation first
- Search closed issues for previous discussions
- Ask in GitHub Discussions
- Join Kubernetes Slack

## Recognition

Contributors are recognized in:
- Git commit history
- GitHub contributors page
- Release notes (for significant contributions)
- Project acknowledgments

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0, the same license as the project.

## Acknowledgments

Thank you for contributing to making Kubernetes networking more secure and accessible for everyone!

---

For questions about this process, please open an issue or reach out to the maintainers.
