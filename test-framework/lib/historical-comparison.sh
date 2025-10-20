#!/bin/bash
# Historical Test Results Comparison Tool
# Compares test results across multiple runs to detect regressions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$(dirname "$SCRIPT_DIR")/results}"
HISTORY_DIR="${HISTORY_DIR:-$RESULTS_DIR/history}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[COMPARE]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }

# Archive a test result for historical comparison
archive_result() {
    local json_file="$1"

    if [[ ! -f "$json_file" ]]; then
        error "JSON file not found: $json_file"
        return 1
    fi

    mkdir -p "$HISTORY_DIR"

    local timestamp=$(jq -r '.test_run.timestamp' "$json_file" | sed 's/[^0-9]//g')
    local archive_file="$HISTORY_DIR/result-${timestamp}.json"

    cp "$json_file" "$archive_file"
    success "Archived result: $archive_file"
}

# Compare two test results
compare_results() {
    local baseline_file="$1"
    local current_file="$2"

    if [[ ! -f "$baseline_file" ]] || [[ ! -f "$current_file" ]]; then
        error "One or both files not found"
        return 1
    fi

    local baseline_pass=$(jq -r '.summary.passed' "$baseline_file")
    local baseline_fail=$(jq -r '.summary.failed' "$baseline_file")
    local baseline_timeout=$(jq -r '.summary.timeout' "$baseline_file")
    local baseline_duration=$(jq -r '.summary.total_duration_seconds' "$baseline_file")

    local current_pass=$(jq -r '.summary.passed' "$current_file")
    local current_fail=$(jq -r '.summary.failed' "$current_file")
    local current_timeout=$(jq -r '.summary.timeout' "$current_file")
    local current_duration=$(jq -r '.summary.total_duration_seconds' "$current_file")

    # Calculate deltas
    local pass_delta=$((current_pass - baseline_pass))
    local fail_delta=$((current_fail - baseline_fail))
    local timeout_delta=$((current_timeout - baseline_timeout))
    local duration_delta=$(echo "$current_duration - $baseline_duration" | bc)

    # Generate comparison JSON
    cat <<EOF
{
  "baseline": {
    "file": "$baseline_file",
    "passed": $baseline_pass,
    "failed": $baseline_fail,
    "timeout": $baseline_timeout,
    "duration": $baseline_duration
  },
  "current": {
    "file": "$current_file",
    "passed": $current_pass,
    "failed": $current_fail,
    "timeout": $current_timeout,
    "duration": $current_duration
  },
  "delta": {
    "passed": $pass_delta,
    "failed": $fail_delta,
    "timeout": $timeout_delta,
    "duration": $duration_delta
  },
  "regression": $([ "$fail_delta" -gt 0 ] || [ "$timeout_delta" -gt 0 ] && echo "true" || echo "false"),
  "improvement": $([ "$pass_delta" -gt 0 ] && [ "$fail_delta" -le 0 ] && echo "true" || echo "false")
}
EOF
}

# Generate historical trend report
generate_trend_report() {
    local output_file="${1:-$RESULTS_DIR/trend-report.html}"

    # Find all historical results
    local history_files=($(find "$HISTORY_DIR" -name "result-*.json" 2>/dev/null | sort))

    if [[ ${#history_files[@]} -lt 2 ]]; then
        warn "Not enough historical data (found ${#history_files[@]} results, need at least 2)"
        return 1
    fi

    # Extract trend data
    local timestamps=()
    local pass_rates=()
    local durations=()

    for file in "${history_files[@]}"; do
        local ts=$(jq -r '.test_run.timestamp' "$file")
        local pass_rate=$(jq -r '.summary.pass_rate' "$file")
        local duration=$(jq -r '.summary.total_duration_seconds' "$file")

        timestamps+=("\"$ts\"")
        pass_rates+=("$pass_rate")
        durations+=("$duration")
    done

    # Generate HTML trend report
    cat > "$output_file" <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Test Trend Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f7fa; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #2d3748; }
        .chart-container { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <div class="container">
        <h1>📈 Historical Test Trend Report</h1>
        <div class="chart-container">
            <h2>Pass Rate Trend</h2>
            <canvas id="passRateChart"></canvas>
        </div>
        <div class="chart-container">
            <h2>Duration Trend</h2>
            <canvas id="durationChart"></canvas>
        </div>
    </div>
    <script>
        const timestamps = [TIMESTAMPS];
        const passRates = [PASS_RATES];
        const durations = [DURATIONS];

        new Chart(document.getElementById('passRateChart'), {
            type: 'line',
            data: {
                labels: timestamps,
                datasets: [{
                    label: 'Pass Rate (%)',
                    data: passRates,
                    borderColor: 'rgb(72, 187, 120)',
                    backgroundColor: 'rgba(72, 187, 120, 0.1)',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: { beginAtZero: true, max: 100 }
                }
            }
        });

        new Chart(document.getElementById('durationChart'), {
            type: 'line',
            data: {
                labels: timestamps,
                datasets: [{
                    label: 'Duration (seconds)',
                    data: durations,
                    borderColor: 'rgb(66, 153, 225)',
                    backgroundColor: 'rgba(66, 153, 225, 0.1)',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
    </script>
</body>
</html>
HTMLEOF

    # Replace placeholders
    sed -i "s|TIMESTAMPS|$(IFS=,; echo "${timestamps[*]}")|g" "$output_file"
    sed -i "s|PASS_RATES|$(IFS=,; echo "${pass_rates[*]}")|g" "$output_file"
    sed -i "s|DURATIONS|$(IFS=,; echo "${durations[*]}")|g" "$output_file"

    success "Trend report generated: $output_file"
    echo "$output_file"
}

# Detect regressions
detect_regressions() {
    local baseline_file="$1"
    local current_file="$2"

    local comparison=$(compare_results "$baseline_file" "$current_file")
    local is_regression=$(echo "$comparison" | jq -r '.regression')

    if [[ "$is_regression" == "true" ]]; then
        error "REGRESSION DETECTED!"
        echo "$comparison" | jq '.'
        return 1
    else
        success "No regressions detected"
        echo "$comparison" | jq '.'
        return 0
    fi
}

# Main CLI
main() {
    local command="${1:-help}"

    case "$command" in
        archive)
            archive_result "${2:-}"
            ;;
        compare)
            compare_results "${2:-}" "${3:-}"
            ;;
        trend)
            generate_trend_report "${2:-}"
            ;;
        regression)
            detect_regressions "${2:-}" "${3:-}"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [args]

Commands:
    archive <json-file>              Archive test result for history
    compare <baseline> <current>     Compare two test results
    trend [output-file]              Generate historical trend report
    regression <baseline> <current>  Detect regressions (exit 1 if found)

Examples:
    $0 archive results/aggregate-20250115.json
    $0 compare results/history/result-old.json results/aggregate-new.json
    $0 trend results/trend.html
    $0 regression results/baseline.json results/current.json
EOF
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
