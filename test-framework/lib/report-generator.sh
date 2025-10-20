#!/bin/bash
# HTML Report Generator for Network Policy Test Results
# Converts JSON test results into comprehensive HTML reports with charts and visualizations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$(dirname "$SCRIPT_DIR")/results}"
REPORTS_DIR="${REPORTS_DIR:-$RESULTS_DIR/html}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for console output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[REPORT]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }

# Generate HTML report from JSON results
generate_html_report() {
    local json_file="$1"
    local output_file="${2:-$REPORTS_DIR/report-${TIMESTAMP}.html}"

    # Validate JSON file
    if [[ ! -f "$json_file" ]]; then
        error "JSON file not found: $json_file"
        return 1
    fi

    if ! jq empty "$json_file" 2>/dev/null; then
        error "Invalid JSON file: $json_file"
        return 1
    fi

    # Extract data from JSON
    local test_run_timestamp=$(jq -r '.test_run.timestamp' "$json_file")
    local workers=$(jq -r '.test_run.workers' "$json_file")
    local timeout=$(jq -r '.test_run.timeout' "$json_file")
    local total=$(jq -r '.summary.total' "$json_file")
    local passed=$(jq -r '.summary.passed' "$json_file")
    local failed=$(jq -r '.summary.failed' "$json_file")
    local timeout_count=$(jq -r '.summary.timeout' "$json_file")
    local pass_rate=$(jq -r '.summary.pass_rate' "$json_file")
    local total_duration=$(jq -r '.summary.total_duration_seconds' "$json_file")

    # Generate results table rows
    local results_rows=""
    while IFS= read -r result; do
        local recipe_id=$(echo "$result" | jq -r '.recipe_id')
        local status=$(echo "$result" | jq -r '.status')
        local duration=$(echo "$result" | jq -r '.duration_seconds')
        local error_msg=$(echo "$result" | jq -r '.error_message // ""')
        local output_preview=$(echo "$result" | jq -r '.output' | head -c 100)

        local status_badge=""
        local status_class=""
        case "$status" in
            PASS)
                status_badge="<span class='badge badge-success'>✓ PASS</span>"
                status_class="success"
                ;;
            FAIL)
                status_badge="<span class='badge badge-danger'>✗ FAIL</span>"
                status_class="danger"
                ;;
            TIMEOUT)
                status_badge="<span class='badge badge-warning'>⏱ TIMEOUT</span>"
                status_class="warning"
                ;;
        esac

        results_rows+="
        <tr class='$status_class'>
            <td><strong>NP-$recipe_id</strong></td>
            <td>$status_badge</td>
            <td>${duration}s</td>
            <td class='error-cell'>${error_msg:-N/A}</td>
            <td>
                <button class='btn btn-sm btn-info' onclick='showDetails(\"$recipe_id\")'>View Details</button>
            </td>
        </tr>"
    done < <(jq -c '.results[]' "$json_file")

    # Generate detailed modals for each test
    local detail_modals=""
    while IFS= read -r result; do
        local recipe_id=$(echo "$result" | jq -r '.recipe_id')
        local status=$(echo "$result" | jq -r '.status')
        local duration=$(echo "$result" | jq -r '.duration_seconds')
        local namespace=$(echo "$result" | jq -r '.namespace')
        local test_timestamp=$(echo "$result" | jq -r '.timestamp')
        local error_msg=$(echo "$result" | jq -r '.error_message // "No errors"')
        local output=$(echo "$result" | jq -r '.output' | sed 's/$/\\n/g' | tr -d '\n')

        detail_modals+="
        <div id='modal-$recipe_id' class='modal'>
            <div class='modal-content'>
                <span class='close' onclick='closeModal(\"$recipe_id\")'>&times;</span>
                <h2>Recipe NP-$recipe_id Details</h2>
                <div class='detail-grid'>
                    <div class='detail-item'><strong>Status:</strong> $status</div>
                    <div class='detail-item'><strong>Duration:</strong> ${duration}s</div>
                    <div class='detail-item'><strong>Namespace:</strong> $namespace</div>
                    <div class='detail-item'><strong>Timestamp:</strong> $test_timestamp</div>
                </div>
                <h3>Error Message</h3>
                <pre class='error-output'>$error_msg</pre>
                <h3>Test Output</h3>
                <pre class='test-output'>$output</pre>
            </div>
        </div>"
    done < <(jq -c '.results[]' "$json_file")

    # Generate chart data
    local chart_data=$(jq -c '{
        labels: [.results[].recipe_id],
        durations: [.results[].duration_seconds],
        statuses: [.results[].status]
    }' "$json_file")

    # Create HTML report
    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Policy Test Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: #f5f7fa;
            color: #333;
            line-height: 1.6;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px 0;
            margin-bottom: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }

        header p {
            font-size: 1.1em;
            opacity: 0.9;
        }

        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .card {
            background: white;
            padding: 25px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            transition: transform 0.2s;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.15);
        }

        .card-title {
            font-size: 0.9em;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 10px;
        }

        .card-value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }

        .card-subtitle {
            font-size: 0.9em;
            color: #999;
        }

        .card.success .card-value { color: #48bb78; }
        .card.danger .card-value { color: #f56565; }
        .card.warning .card-value { color: #ed8936; }
        .card.info .card-value { color: #4299e1; }

        .chart-container {
            background: white;
            padding: 25px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }

        .chart-container h2 {
            margin-bottom: 20px;
            color: #2d3748;
        }

        table {
            width: 100%;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        th {
            background: #667eea;
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }

        td {
            padding: 15px;
            border-bottom: 1px solid #e2e8f0;
        }

        tr:last-child td {
            border-bottom: none;
        }

        tr.success { background: #f0fff4; }
        tr.danger { background: #fff5f5; }
        tr.warning { background: #fffaf0; }

        .badge {
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }

        .badge-success {
            background: #48bb78;
            color: white;
        }

        .badge-danger {
            background: #f56565;
            color: white;
        }

        .badge-warning {
            background: #ed8936;
            color: white;
        }

        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.9em;
            transition: background 0.2s;
        }

        .btn-info {
            background: #4299e1;
            color: white;
        }

        .btn-info:hover {
            background: #3182ce;
        }

        .error-cell {
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            color: #e53e3e;
            font-size: 0.9em;
        }

        .modal {
            display: none;
            position: fixed;
            z-index: 1000;
            left: 0;
            top: 0;
            width: 100%;
            height: 100%;
            overflow: auto;
            background-color: rgba(0,0,0,0.6);
        }

        .modal-content {
            background-color: white;
            margin: 50px auto;
            padding: 30px;
            border-radius: 8px;
            width: 80%;
            max-width: 900px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        }

        .close {
            color: #aaa;
            float: right;
            font-size: 28px;
            font-weight: bold;
            cursor: pointer;
        }

        .close:hover {
            color: #000;
        }

        .detail-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
            margin: 20px 0;
        }

        .detail-item {
            padding: 10px;
            background: #f7fafc;
            border-radius: 4px;
        }

        pre {
            background: #2d3748;
            color: #e2e8f0;
            padding: 15px;
            border-radius: 4px;
            overflow-x: auto;
            margin: 10px 0;
            font-size: 0.9em;
            line-height: 1.5;
        }

        .error-output {
            background: #742a2a;
            color: #fed7d7;
        }

        footer {
            text-align: center;
            padding: 20px;
            color: #718096;
            font-size: 0.9em;
        }

        @media print {
            .modal, .btn { display: none !important; }
            body { background: white; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔒 Network Policy Test Report</h1>
            <p>Comprehensive test results for Kubernetes Network Policy recipes</p>
        </header>

        <div class="summary-cards">
            <div class="card info">
                <div class="card-title">Total Tests</div>
                <div class="card-value">__TOTAL__</div>
                <div class="card-subtitle">__WORKERS__ parallel workers</div>
            </div>
            <div class="card success">
                <div class="card-title">Passed</div>
                <div class="card-value">__PASSED__</div>
                <div class="card-subtitle">__PASS_RATE__%</div>
            </div>
            <div class="card danger">
                <div class="card-title">Failed</div>
                <div class="card-value">__FAILED__</div>
                <div class="card-subtitle">Test failures</div>
            </div>
            <div class="card warning">
                <div class="card-title">Timeout</div>
                <div class="card-value">__TIMEOUT__</div>
                <div class="card-subtitle">__TIMEOUT_LIMIT__s limit</div>
            </div>
            <div class="card info">
                <div class="card-title">Duration</div>
                <div class="card-value">__DURATION__s</div>
                <div class="card-subtitle">Total execution time</div>
            </div>
            <div class="card">
                <div class="card-title">Timestamp</div>
                <div class="card-value" style="font-size: 1.2em;">__TIMESTAMP__</div>
                <div class="card-subtitle">Test run time</div>
            </div>
        </div>

        <div class="chart-container">
            <h2>📊 Test Duration by Recipe</h2>
            <canvas id="durationChart"></canvas>
        </div>

        <div class="chart-container">
            <h2>📈 Test Results Overview</h2>
            <canvas id="resultsChart"></canvas>
        </div>

        <div class="chart-container">
            <h2>📋 Detailed Test Results</h2>
            <table>
                <thead>
                    <tr>
                        <th>Recipe</th>
                        <th>Status</th>
                        <th>Duration</th>
                        <th>Error</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    __RESULTS_ROWS__
                </tbody>
            </table>
        </div>

        <footer>
            <p>Generated by Network Policy Test Framework • __TIMESTAMP__</p>
        </footer>
    </div>

    __DETAIL_MODALS__

    <script>
        const chartData = __CHART_DATA__;

        // Duration chart
        new Chart(document.getElementById('durationChart'), {
            type: 'bar',
            data: {
                labels: chartData.labels.map(id => `NP-${id}`),
                datasets: [{
                    label: 'Duration (seconds)',
                    data: chartData.durations,
                    backgroundColor: chartData.statuses.map(status =>
                        status === 'PASS' ? 'rgba(72, 187, 120, 0.6)' :
                        status === 'FAIL' ? 'rgba(245, 101, 101, 0.6)' :
                        'rgba(237, 137, 54, 0.6)'
                    ),
                    borderColor: chartData.statuses.map(status =>
                        status === 'PASS' ? 'rgb(72, 187, 120)' :
                        status === 'FAIL' ? 'rgb(245, 101, 101)' :
                        'rgb(237, 137, 54)'
                    ),
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                return context.parsed.y + 's (' + chartData.statuses[context.dataIndex] + ')';
                            }
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: { display: true, text: 'Duration (seconds)' }
                    }
                }
            }
        });

        // Results pie chart
        const statusCounts = chartData.statuses.reduce((acc, status) => {
            acc[status] = (acc[status] || 0) + 1;
            return acc;
        }, {});

        new Chart(document.getElementById('resultsChart'), {
            type: 'doughnut',
            data: {
                labels: Object.keys(statusCounts),
                datasets: [{
                    data: Object.values(statusCounts),
                    backgroundColor: [
                        'rgba(72, 187, 120, 0.8)',
                        'rgba(245, 101, 101, 0.8)',
                        'rgba(237, 137, 54, 0.8)'
                    ],
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { position: 'bottom' }
                }
            }
        });

        // Modal functions
        function showDetails(recipeId) {
            document.getElementById('modal-' + recipeId).style.display = 'block';
        }

        function closeModal(recipeId) {
            document.getElementById('modal-' + recipeId).style.display = 'none';
        }

        window.onclick = function(event) {
            if (event.target.className === 'modal') {
                event.target.style.display = 'none';
            }
        };
    </script>
</body>
</html>
EOF

    # Replace placeholders
    sed -i "s|__TOTAL__|$total|g" "$output_file"
    sed -i "s|__PASSED__|$passed|g" "$output_file"
    sed -i "s|__FAILED__|$failed|g" "$output_file"
    sed -i "s|__TIMEOUT__|$timeout_count|g" "$output_file"
    sed -i "s|__PASS_RATE__|$pass_rate|g" "$output_file"
    sed -i "s|__DURATION__|$total_duration|g" "$output_file"
    sed -i "s|__WORKERS__|$workers|g" "$output_file"
    sed -i "s|__TIMEOUT_LIMIT__|$timeout|g" "$output_file"
    sed -i "s|__TIMESTAMP__|$test_run_timestamp|g" "$output_file"
    sed -i "s|__RESULTS_ROWS__|$(echo "$results_rows" | sed 's/|/\\|/g')|g" "$output_file"
    sed -i "s|__DETAIL_MODALS__|$(echo "$detail_modals" | sed 's/|/\\|/g')|g" "$output_file"
    sed -i "s|__CHART_DATA__|$(echo "$chart_data" | sed 's/|/\\|/g')|g" "$output_file"

    success "HTML report generated: $output_file"
    echo "$output_file"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        error "Usage: $0 <json-file> [output-html-file]"
        exit 1
    fi

    generate_html_report "$@"
fi
