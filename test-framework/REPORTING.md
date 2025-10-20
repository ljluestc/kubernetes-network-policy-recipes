# Test Reporting Guide

Comprehensive documentation for the test reporting system.

## Features

- **HTML Reports**: Beautiful, interactive reports with charts and visualizations
- **Historical Comparison**: Track test results over time and detect regressions
- **CI/CD Integration**: GitHub Actions, GitLab CI, Jenkins, and more
- **Multiple Formats**: JSON, HTML, JUnit XML
- **Notifications**: Slack, GitHub PR comments
- **Badges**: Dynamic test badges for README

## Quick Start

Run tests and automatically generate all reports:

```bash
./parallel-test-runner.sh
```

This will create:
- `results/aggregate-{timestamp}.json` - Machine-readable results
- `results/html/report-{timestamp}.html` - Interactive HTML report
- `results/history/result-{timestamp}.json` - Archived for historical comparison

## HTML Reports

### Automatic Generation

HTML reports are automatically generated after each test run. They include:

- 📊 Summary cards (total, passed, failed, timeout, pass rate, duration)
- 📈 Interactive charts (duration by recipe, results pie chart)
- 📋 Detailed results table with drill-down modals
- 🎨 Beautiful, responsive design

### Manual Generation

Generate HTML report from existing JSON:

```bash
./lib/report-generator.sh results/aggregate-20250115.json output.html
```

###Open the report:

```bash
# Linux
xdg-open results/html/report-20250115.html

# macOS
open results/html/report-20250115.html

# Or use your web browser
firefox results/html/report-20250115.html
```

## Historical Comparison

### Archive Results

Archive a test result for historical tracking:

```bash
./lib/historical-comparison.sh archive results/aggregate-20250115.json
```

### Compare Results

Compare two test runs:

```bash
./lib/historical-comparison.sh compare \
    results/history/result-20250114.json \
    results/aggregate-20250115.json
```

Output:
```json
{
  "baseline": {
    "passed": 13,
    "failed": 2
  },
  "current": {
    "passed": 15,
    "failed": 0
  },
  "delta": {
    "passed": 2,
    "failed": -2
  },
  "regression": false,
  "improvement": true
}
```

### Generate Trend Report

Create historical trend visualization:

```bash
./lib/historical-comparison.sh trend results/trend.html
```

### Detect Regressions

Exit with error if regressions detected:

```bash
if ! ./lib/historical-comparison.sh regression \
    results/baseline.json \
    results/current.json; then
    echo "Regression detected!"
    exit 1
fi
```

## CI/CD Integration

### GitHub Actions

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

      - name: Run tests
        run: |
          cd test-framework
          ./parallel-test-runner.sh

      - name: Post PR comment
        if: github.event_name == 'pull_request'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_PR_NUMBER: ${{ github.event.pull_request.number }}
          GITHUB_REPOSITORY: ${{ github.repository }}
        run: |
          cd test-framework
          ./lib/ci-helpers.sh github-comment results/aggregate-*.json

      - name: Upload reports
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-reports
          path: |
            test-framework/results/**/*.json
            test-framework/results/**/*.html
```

### GitLab CI

```yaml
test:
  stage: test
  image: gcr.io/google.com/cloudsdktool/cloud-sdk:latest
  before_script:
    - apt-get update && apt-get install -y parallel jq bc
  script:
    - cd test-framework
    - ./parallel-test-runner.sh
    - ./lib/ci-helpers.sh junit-xml results/aggregate-*.json junit.xml
  artifacts:
    paths:
      - test-framework/results/
    reports:
      junit: test-framework/junit.xml
    when: always
```

### Jenkins

```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                sh 'cd test-framework && ./parallel-test-runner.sh'
                sh 'cd test-framework && ./lib/ci-helpers.sh junit-xml results/aggregate-*.json junit.xml'
            }
            post {
                always {
                    junit 'test-framework/junit.xml'
                    publishHTML([
                        reportDir: 'test-framework/results/html',
                        reportFiles: 'report-*.html',
                        reportName: 'Test Report'
                    ])
                }
            }
        }
    }
}
```

## CI Helper Commands

### GitHub PR Comments

Post results as PR comment:

```bash
./lib/ci-helpers.sh github-comment results/aggregate.json [pr-number] [repo]
```

Environment variables:
- `GITHUB_TOKEN` - GitHub API token
- `GITHUB_PR_NUMBER` - PR number (optional if provided as arg)
- `GITHUB_REPOSITORY` - Repository (owner/repo)

### JUnit XML

Generate JUnit XML for Jenkins/GitLab:

```bash
./lib/ci-helpers.sh junit-xml results/aggregate.json test-results.xml
```

### Slack Notifications

Send results to Slack:

```bash
./lib/ci-helpers.sh slack results/aggregate.json https://hooks.slack.com/services/...
```

Or use environment variable:
```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
./lib/ci-helpers.sh slack results/aggregate.json
```

### Shields.io Badges

Generate badge JSON for shields.io:

```bash
./lib/ci-helpers.sh badge results/aggregate.json badge.json
```

Use in README:
```markdown
![Tests](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/user/repo/main/badge.json)
```

## Report Structure

### JSON Format

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
      "output": "Testing NP-01...\nPASS"
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

### HTML Report Features

- **Responsive Design**: Works on desktop, tablet, and mobile
- **Interactive Charts**: Powered by Chart.js
- **Drill-down Details**: Click any test to see full output
- **Print-friendly**: Clean printing layout
- **No External Dependencies**: Self-contained HTML file

## Best Practices

### 1. Archive Every Run

Always archive results for trend analysis:

```bash
# In your CI/CD pipeline
./parallel-test-runner.sh
./lib/historical-comparison.sh archive results/aggregate-*.json
```

### 2. Detect Regressions

Fail builds on regressions:

```bash
if ! ./lib/historical-comparison.sh regression baseline.json current.json; then
    echo "Regression detected - failing build"
    exit 1
fi
```

### 3. Generate Trends Regularly

Create trend reports weekly or monthly:

```bash
# Weekly cron job
./lib/historical-comparison.sh trend results/trend-$(date +%Y-week-%V).html
```

### 4. Notify on Failures

Send notifications for test failures:

```bash
if [[ $(jq -r '.summary.failed' results/aggregate.json) -gt 0 ]]; then
    ./lib/ci-helpers.sh slack results/aggregate.json
fi
```

### 5. Keep Historical Data

Don't delete old results - they're valuable for trend analysis:

```bash
# Results directory structure
results/
├── aggregate-20250101-120000.json
├── aggregate-20250102-120000.json
├── history/
│   ├── result-20250101-120000.json
│   ├── result-20250102-120000.json
└── html/
    ├── report-20250101-120000.html
    ├── report-20250102-120000.html
```

## Troubleshooting

### Charts Not Rendering

Ensure internet connection for Chart.js CDN, or download and host locally.

### Historical Comparison Needs More Data

Need at least 2 archived results for trend reports:

```bash
./lib/historical-comparison.sh archive results/aggregate-run1.json
./lib/historical-comparison.sh archive results/aggregate-run2.json
./lib/historical-comparison.sh trend results/trend.html
```

### GitHub PR Comments Not Posting

Check environment variables:
```bash
echo $GITHUB_TOKEN
echo $GITHUB_PR_NUMBER
echo $GITHUB_REPOSITORY
```

### Slack Notifications Failing

Verify webhook URL is correct and accessible:
```bash
curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test message"}' \
    $SLACK_WEBHOOK_URL
```

## Advanced Usage

### Custom Report Templates

Modify `lib/report-generator.sh` to customize HTML template.

### Multiple Baseline Comparisons

Compare against multiple baselines:

```bash
for baseline in results/history/result-202501*.json; do
    ./lib/historical-comparison.sh compare "$baseline" results/current.json
done
```

### Automated Regression Alerts

```bash
if ./lib/historical-comparison.sh regression baseline.json current.json; then
    ./lib/ci-helpers.sh slack current.json
    ./lib/ci-helpers.sh github-comment current.json
fi
```

## License

Same as parent project.
