#!/usr/bin/env bash
# Coverage tracking for BATS and integration tests
# Part of the comprehensive test coverage reporting system

set -euo pipefail

# Calculate BATS test coverage based on recipe files
calculate_bats_coverage() {
    local bats_tests_dir="test-framework/bats-tests/recipes"
    local total_recipes=15
    local recipes_with_tests=0

    # Count recipes with BATS tests (including recipe 02a)
    for i in $(seq -w 0 14); do
        if compgen -G "${bats_tests_dir}/${i}-"*.bats > /dev/null 2>&1 || \
           compgen -G "${bats_tests_dir}/${i}a-"*.bats > /dev/null 2>&1; then
            recipes_with_tests=$((recipes_with_tests + 1))
        fi
    done

    # Use bc for floating point arithmetic
    echo "scale=2; ($recipes_with_tests / $total_recipes) * 100" | bc
}

# Calculate integration test coverage
calculate_integration_coverage() {
    # Count actual test scenarios (test_* functions) in integration test files
    local scenario_files=$(find test-framework/integration-tests/scenarios -name "*.sh" -type f 2>/dev/null)
    local total_scenarios=0

    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local count=$(grep -c "^test_" "$file" 2>/dev/null || echo 0)
            total_scenarios=$((total_scenarios + count))
        fi
    done <<< "$scenario_files"

    # Expected total scenarios (25 across all integration tests)
    local expected_scenarios=25

    # Calculate coverage percentage
    if [[ $expected_scenarios -gt 0 ]]; then
        echo "scale=2; ($total_scenarios / $expected_scenarios) * 100" | bc
    else
        echo "0"
    fi
}

# Calculate recipe coverage (recipes with any kind of test)
calculate_recipe_coverage() {
    local total_recipes=15
    local covered_recipes=0

    # Check each recipe (00-14 plus 02a)
    for i in $(seq -w 0 14); do
        if compgen -G "test-framework/bats-tests/recipes/${i}-"*.bats > /dev/null 2>&1 || \
           compgen -G "test-framework/bats-tests/recipes/${i}a-"*.bats > /dev/null 2>&1 || \
           compgen -G "test-framework/*${i}-"*.sh > /dev/null 2>&1; then
            covered_recipes=$((covered_recipes + 1))
        fi
    done

    echo "scale=2; ($covered_recipes / $total_recipes) * 100" | bc
}

# Count total BATS test cases
count_bats_test_cases() {
    local bats_tests_dir="test-framework/bats-tests/recipes"
    local total=0

    if [[ -d "$bats_tests_dir" ]]; then
        while IFS= read -r file; do
            local count=$(grep -c "^@test" "$file" 2>/dev/null || echo 0)
            total=$((total + count))
        done < <(find "$bats_tests_dir" -name "*.bats" 2>/dev/null)
    fi

    echo "$total"
}

# Count total BATS test files
count_bats_test_files() {
    local bats_tests_dir="test-framework/bats-tests/recipes"

    if [[ -d "$bats_tests_dir" ]]; then
        find "$bats_tests_dir" -name "*.bats" 2>/dev/null | wc -l
    else
        echo 0
    fi
}

# Count integration test files
count_integration_test_files() {
    find test-framework -name "*integration*.sh" -o -name "*e2e*.sh" 2>/dev/null | wc -l
}

# Count integration test scenarios (test_* functions)
count_integration_test_scenarios() {
    local scenario_files=$(find test-framework/integration-tests/scenarios -name "*.sh" -type f 2>/dev/null)
    local total=0

    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local count=$(grep -c "^test_" "$file" 2>/dev/null || echo 0)
            total=$((total + count))
        fi
    done <<< "$scenario_files"

    echo "$total"
}

# Generate comprehensive coverage report
generate_coverage_report() {
    local output_file="${1:-test-framework/results/coverage-report.json}"

    # Create results directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"

    # Calculate all coverage metrics
    local bats_coverage=$(calculate_bats_coverage)
    local integration_coverage=$(calculate_integration_coverage)
    local recipe_coverage=$(calculate_recipe_coverage)
    local overall_coverage=$(echo "scale=2; ($bats_coverage + $integration_coverage) / 2" | bc)

    # Count test files and cases
    local total_test_cases=$(count_bats_test_cases)
    local bats_test_files=$(count_bats_test_files)
    local integration_test_files=$(count_integration_test_files)
    local integration_test_scenarios=$(count_integration_test_scenarios)

    # Determine status based on threshold
    local threshold_status="FAIL"
    if (( $(echo "$overall_coverage >= 95" | bc -l) )); then
        threshold_status="PASS"
    fi

    # Generate JSON report
    cat > "$output_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "coverage": {
    "bats_unit_tests": ${bats_coverage},
    "integration_tests": ${integration_coverage},
    "recipe_coverage": ${recipe_coverage},
    "overall": ${overall_coverage}
  },
  "details": {
    "total_recipes": 15,
    "bats_test_files": ${bats_test_files},
    "bats_test_cases": ${total_test_cases},
    "integration_test_files": ${integration_test_files},
    "integration_test_scenarios": ${integration_test_scenarios}
  },
  "thresholds": {
    "minimum": 95,
    "target": 100,
    "status": "${threshold_status}"
  }
}
EOF

    # Output the report to stdout
    cat "$output_file"
}

# Generate HTML coverage report
generate_html_coverage_report() {
    local json_file="${1:-test-framework/results/coverage-report.json}"
    local output_file="${2:-test-framework/results/coverage-report.html}"

    if [[ ! -f "$json_file" ]]; then
        echo "Error: JSON coverage report not found at $json_file"
        return 1
    fi

    local overall=$(jq -r '.coverage.overall' "$json_file")
    local bats=$(jq -r '.coverage.bats_unit_tests' "$json_file")
    local integration=$(jq -r '.coverage.integration_tests' "$json_file")
    local recipe=$(jq -r '.coverage.recipe_coverage' "$json_file")
    local timestamp=$(jq -r '.timestamp' "$json_file")
    local status=$(jq -r '.thresholds.status' "$json_file")
    local test_cases=$(jq -r '.details.total_test_cases' "$json_file")

    local status_color="red"
    local status_emoji="❌"
    if [[ "$status" == "PASS" ]]; then
        status_color="green"
        status_emoji="✅"
    fi

    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Test Coverage Report - Kubernetes Network Policy Recipes</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 {
            margin: 0 0 10px 0;
        }
        .header .timestamp {
            opacity: 0.9;
            font-size: 14px;
        }
        .cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .card h3 {
            margin: 0 0 15px 0;
            color: #333;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .coverage-value {
            font-size: 48px;
            font-weight: bold;
            color: #667eea;
        }
        .progress-bar {
            width: 100%;
            height: 10px;
            background-color: #e0e0e0;
            border-radius: 5px;
            overflow: hidden;
            margin-top: 10px;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            transition: width 0.3s ease;
        }
        .status {
            display: inline-block;
            padding: 10px 20px;
            border-radius: 5px;
            font-weight: bold;
            margin-top: 10px;
        }
        .status.pass {
            background-color: #4caf50;
            color: white;
        }
        .status.fail {
            background-color: #f44336;
            color: white;
        }
        .details {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .details h2 {
            margin-top: 0;
        }
        .details table {
            width: 100%;
            border-collapse: collapse;
        }
        .details th, .details td {
            text-align: left;
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        .details th {
            background-color: #f5f5f5;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Test Coverage Report</h1>
        <div class="timestamp">Generated: ${timestamp}</div>
    </div>

    <div class="cards">
        <div class="card">
            <h3>Overall Coverage</h3>
            <div class="coverage-value">${overall}%</div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${overall}%"></div>
            </div>
            <div class="status ${status_color}">${status_emoji} ${status}</div>
        </div>

        <div class="card">
            <h3>BATS Unit Tests</h3>
            <div class="coverage-value">${bats}%</div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${bats}%"></div>
            </div>
        </div>

        <div class="card">
            <h3>Integration Tests</h3>
            <div class="coverage-value">${integration}%</div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${integration}%"></div>
            </div>
        </div>

        <div class="card">
            <h3>Recipe Coverage</h3>
            <div class="coverage-value">${recipe}%</div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${recipe}%"></div>
            </div>
        </div>
    </div>

    <div class="details">
        <h2>Coverage Details</h2>
        <table>
            <tr>
                <th>Metric</th>
                <th>Value</th>
            </tr>
            <tr>
                <td>Total Network Policy Recipes</td>
                <td>15</td>
            </tr>
            <tr>
                <td>BATS Test Cases</td>
                <td>${test_cases}</td>
            </tr>
            <tr>
                <td>BATS Test Files</td>
                <td>$(jq -r '.details.bats_test_files' "$json_file")</td>
            </tr>
            <tr>
                <td>Integration Test Scenarios</td>
                <td>$(jq -r '.details.integration_test_scenarios' "$json_file")</td>
            </tr>
            <tr>
                <td>Integration Test Files</td>
                <td>$(jq -r '.details.integration_test_files' "$json_file")</td>
            </tr>
            <tr>
                <td>Coverage Threshold</td>
                <td>95% (minimum)</td>
            </tr>
        </table>
    </div>
</body>
</html>
EOF

    echo "HTML report generated: $output_file"
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-report}" in
        report)
            generate_coverage_report "${2:-test-framework/results/coverage-report.json}"
            ;;
        html)
            generate_coverage_report "test-framework/results/coverage-report.json"
            generate_html_coverage_report "test-framework/results/coverage-report.json" \
                "${2:-test-framework/results/coverage-report.html}"
            ;;
        bats)
            calculate_bats_coverage
            ;;
        integration)
            calculate_integration_coverage
            ;;
        recipe)
            calculate_recipe_coverage
            ;;
        *)
            echo "Usage: $0 {report|html|bats|integration|recipe} [output_file]"
            exit 1
            ;;
    esac
fi
