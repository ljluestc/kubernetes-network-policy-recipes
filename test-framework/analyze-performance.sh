#!/usr/bin/env bash

#############################################################################
# Performance Analysis and Reporting Tool
#
# This script analyzes benchmark results and generates comprehensive reports:
# - Historical trend analysis
# - Performance comparison across different CNIs
# - Regression detection and tracking
# - Multi-format report generation (JSON, HTML, Markdown)
# - Performance metrics visualization
# - Recommendations and insights
#
# Usage:
#   ./analyze-performance.sh [options]
#
# Options:
#   --results-dir <dir>      Directory with benchmark results (default: ./benchmark-results)
#   --output <file>          Output report file
#   --format <type>          Report format: json, html, markdown, all (default: html)
#   --compare <ids>          Compare specific benchmark IDs (comma-separated)
#   --trend <days>           Analyze trends over N days (default: 30)
#   --threshold <percent>    Highlight changes above threshold (default: 5)
#   --cni-comparison         Generate CNI comparison report
#   --recommendations        Include optimization recommendations
#   --verbose                Enable verbose output
#   --help                   Show this help message
#
#############################################################################

set -euo pipefail

# Default configuration
RESULTS_DIR="./benchmark-results"
OUTPUT_FILE=""
OUTPUT_FORMAT="html"
COMPARE_IDS=""
TREND_DAYS=30
THRESHOLD=5
CNI_COMPARISON=false
RECOMMENDATIONS=false
VERBOSE=false

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#############################################################################
# Helper Functions
#############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
    fi
}

show_usage() {
    grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# *//'
    exit 0
}

#############################################################################
# Data Collection
#############################################################################

load_benchmark_results() {
    local results_dir="$1"

    log "Loading benchmark results from: $results_dir"

    if [[ ! -d "$results_dir" ]]; then
        log_error "Results directory not found: $results_dir"
        exit 1
    fi

    local results=()
    local count=0

    while IFS= read -r file; do
        if [[ -f "$file" ]] && [[ "$file" != *"/baseline.json" ]]; then
            results+=("$file")
            ((count++))
            log_info "  Loaded: $(basename "$file")"
        fi
    done < <(find "$results_dir" -name "*.json" -type f | sort)

    if [[ $count -eq 0 ]]; then
        log_error "No benchmark results found in $results_dir"
        exit 1
    fi

    log "Loaded $count benchmark result(s)"
    printf '%s\n' "${results[@]}"
}

filter_by_date_range() {
    local days="$1"
    shift
    local all_results=("$@")

    local cutoff_date=$(date -d "$days days ago" +%s)
    local filtered=()

    for file in "${all_results[@]}"; do
        local timestamp=$(jq -r '.timestamp' "$file" 2>/dev/null || echo "")
        if [[ -n "$timestamp" ]]; then
            local file_date=$(date -d "${timestamp:0:8}" +%s 2>/dev/null || echo "0")
            if [[ $file_date -ge $cutoff_date ]]; then
                filtered+=("$file")
            fi
        fi
    done

    printf '%s\n' "${filtered[@]}"
}

#############################################################################
# Analysis Functions
#############################################################################

calculate_statistics() {
    local metric="$1"
    shift
    local values=("$@")

    if [[ ${#values[@]} -eq 0 ]]; then
        echo "0:0:0:0"  # min:max:avg:stddev
        return
    fi

    local sum=0
    local min=""
    local max=""

    for val in "${values[@]}"; do
        # Skip non-numeric values
        if ! [[ "$val" =~ ^[0-9.]+$ ]]; then
            continue
        fi

        sum=$(echo "$sum + $val" | bc)

        if [[ -z "$min" ]] || [[ $(echo "$val < $min" | bc) -eq 1 ]]; then
            min="$val"
        fi

        if [[ -z "$max" ]] || [[ $(echo "$val > $max" | bc) -eq 1 ]]; then
            max="$val"
        fi
    done

    local avg=0
    if [[ ${#values[@]} -gt 0 ]]; then
        avg=$(echo "scale=2; $sum / ${#values[@]}" | bc)
    fi

    # Calculate standard deviation
    local variance_sum=0
    for val in "${values[@]}"; do
        if [[ "$val" =~ ^[0-9.]+$ ]]; then
            local diff=$(echo "$val - $avg" | bc)
            local squared=$(echo "$diff * $diff" | bc)
            variance_sum=$(echo "$variance_sum + $squared" | bc)
        fi
    done

    local stddev=0
    if [[ ${#values[@]} -gt 1 ]]; then
        local variance=$(echo "scale=2; $variance_sum / (${#values[@]} - 1)" | bc)
        stddev=$(echo "scale=2; sqrt($variance)" | bc)
    fi

    echo "${min}:${max}:${avg}:${stddev}"
}

analyze_trends() {
    local results=("$@")

    log "Analyzing performance trends..."

    local enforcement_latencies=()
    local throughput_impacts=()
    local latency_impacts=()

    for file in "${results[@]}"; do
        local enforcement=$(jq -r '.enforcement.latency_seconds' "$file" 2>/dev/null || echo "0")
        local throughput=$(jq -r '.throughput.impact_percent' "$file" 2>/dev/null || echo "0")
        local latency=$(jq -r '.latency.impact_percent' "$file" 2>/dev/null || echo "0")

        enforcement_latencies+=("$enforcement")
        throughput_impacts+=("$throughput")
        latency_impacts+=("$latency")
    done

    local enforcement_stats=$(calculate_statistics "enforcement" "${enforcement_latencies[@]}")
    local throughput_stats=$(calculate_statistics "throughput" "${throughput_impacts[@]}")
    local latency_stats=$(calculate_statistics "latency" "${latency_impacts[@]}")

    jq -n \
        --arg enforcement "$enforcement_stats" \
        --arg throughput "$throughput_stats" \
        --arg latency "$latency_stats" \
        '{
            enforcement_latency: {
                min: ($enforcement | split(":")[0]),
                max: ($enforcement | split(":")[1]),
                avg: ($enforcement | split(":")[2]),
                stddev: ($enforcement | split(":")[3])
            },
            throughput_impact: {
                min: ($throughput | split(":")[0]),
                max: ($throughput | split(":")[1]),
                avg: ($throughput | split(":")[2]),
                stddev: ($throughput | split(":")[3])
            },
            latency_impact: {
                min: ($latency | split(":")[0]),
                max: ($latency | split(":")[1]),
                avg: ($latency | split(":")[2]),
                stddev: ($latency | split(":")[3])
            }
        }'
}

compare_benchmarks() {
    local id1="$1"
    local id2="$2"

    log "Comparing benchmarks: $id1 vs $id2"

    local file1="${RESULTS_DIR}/${id1}.json"
    local file2="${RESULTS_DIR}/${id2}.json"

    if [[ ! -f "$file1" ]] || [[ ! -f "$file2" ]]; then
        log_error "One or both benchmark files not found"
        return 1
    fi

    local comparison=$(jq -s \
        --arg id1 "$id1" \
        --arg id2 "$id2" \
        '{
            benchmark1: {
                id: $id1,
                enforcement_latency: .[0].enforcement.latency_seconds,
                throughput_impact: .[0].throughput.impact_percent,
                latency_impact: .[0].latency.impact_percent,
                cni: .[0].cluster.cni
            },
            benchmark2: {
                id: $id2,
                enforcement_latency: .[1].enforcement.latency_seconds,
                throughput_impact: .[1].throughput.impact_percent,
                latency_impact: .[1].latency.impact_percent,
                cni: .[1].cluster.cni
            },
            differences: {
                enforcement_latency_delta: ((.[1].enforcement.latency_seconds | tonumber) - (.[0].enforcement.latency_seconds | tonumber)),
                throughput_impact_delta: ((.[1].throughput.impact_percent | tonumber) - (.[0].throughput.impact_percent | tonumber)),
                latency_impact_delta: ((.[1].latency.impact_percent | tonumber) - (.[0].latency.impact_percent | tonumber))
            }
        }' "$file1" "$file2")

    echo "$comparison"
}

analyze_by_cni() {
    local results=("$@")

    log "Analyzing performance by CNI plugin..."

    local cni_data="{}"

    for file in "${results[@]}"; do
        local cni=$(jq -r '.cluster.cni' "$file" 2>/dev/null || echo "unknown")
        local enforcement=$(jq -r '.enforcement.latency_seconds' "$file" 2>/dev/null || echo "0")
        local throughput=$(jq -r '.throughput.impact_percent' "$file" 2>/dev/null || echo "0")

        # Aggregate data by CNI
        cni_data=$(echo "$cni_data" | jq \
            --arg cni "$cni" \
            --arg enforcement "$enforcement" \
            --arg throughput "$throughput" \
            '.[$cni] += {
                enforcement: [.[$cni].enforcement[]?, $enforcement],
                throughput: [.[$cni].throughput[]?, $throughput]
            }')
    done

    # Calculate averages for each CNI
    local cni_summary="{}"
    while IFS= read -r cni; do
        if [[ -n "$cni" ]] && [[ "$cni" != "null" ]]; then
            local enforcement_values=$(echo "$cni_data" | jq -r ".\"$cni\".enforcement[]" 2>/dev/null)
            local throughput_values=$(echo "$cni_data" | jq -r ".\"$cni\".throughput[]" 2>/dev/null)

            local enforcement_avg=0
            local throughput_avg=0
            local count=0

            while IFS= read -r val; do
                if [[ -n "$val" ]]; then
                    enforcement_avg=$(echo "$enforcement_avg + $val" | bc)
                    ((count++))
                fi
            done <<< "$enforcement_values"

            if [[ $count -gt 0 ]]; then
                enforcement_avg=$(echo "scale=3; $enforcement_avg / $count" | bc)
            fi

            count=0
            while IFS= read -r val; do
                if [[ -n "$val" ]]; then
                    throughput_avg=$(echo "$throughput_avg + $val" | bc)
                    ((count++))
                fi
            done <<< "$throughput_values"

            if [[ $count -gt 0 ]]; then
                throughput_avg=$(echo "scale=2; $throughput_avg / $count" | bc)
            fi

            cni_summary=$(echo "$cni_summary" | jq \
                --arg cni "$cni" \
                --arg enforcement "$enforcement_avg" \
                --arg throughput "$throughput_avg" \
                '.[$cni] = {
                    avg_enforcement_latency: $enforcement,
                    avg_throughput_impact: $throughput
                }')
        fi
    done < <(echo "$cni_data" | jq -r 'keys[]')

    echo "$cni_summary"
}

#############################################################################
# Recommendations Engine
#############################################################################

generate_recommendations() {
    local trends="$1"

    log "Generating optimization recommendations..."

    local recommendations=()

    # Check enforcement latency
    local avg_enforcement=$(echo "$trends" | jq -r '.enforcement_latency.avg')
    if [[ $(echo "$avg_enforcement > 2" | bc) -eq 1 ]]; then
        recommendations+=("High policy enforcement latency detected (${avg_enforcement}s). Consider optimizing policy complexity or upgrading CNI plugin.")
    fi

    # Check throughput impact
    local avg_throughput=$(echo "$trends" | jq -r '.throughput_impact.avg')
    if [[ $(echo "$avg_throughput > 10" | bc) -eq 1 ]]; then
        recommendations+=("Significant throughput impact (${avg_throughput}%). Review policy rules for optimization opportunities.")
    fi

    # Check latency impact
    local avg_latency=$(echo "$trends" | jq -r '.latency_impact.avg')
    if [[ $(echo "$avg_latency > 15" | bc) -eq 1 ]]; then
        recommendations+=("High latency impact (${avg_latency}%). Consider reviewing egress rules and DNS policies.")
    fi

    # Check variability
    local enforcement_stddev=$(echo "$trends" | jq -r '.enforcement_latency.stddev')
    if [[ $(echo "$enforcement_stddev > 0.5" | bc) -eq 1 ]]; then
        recommendations+=("High variability in enforcement latency (stddev: ${enforcement_stddev}s). Investigate cluster load and resource constraints.")
    fi

    # Default recommendation if all metrics are good
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        recommendations+=("Performance metrics are within acceptable ranges. Continue monitoring for regressions.")
    fi

    printf '%s\n' "${recommendations[@]}" | jq -R . | jq -s .
}

#############################################################################
# Report Generation
#############################################################################

generate_json_report() {
    local trends="$1"
    local cni_analysis="$2"
    local recommendations="$3"
    local output_file="$4"

    log "Generating JSON report..."

    jq -n \
        --argjson trends "$trends" \
        --argjson cni "$cni_analysis" \
        --argjson recs "$recommendations" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            report_type: "performance_analysis",
            generated_at: $timestamp,
            trends: $trends,
            cni_comparison: $cni,
            recommendations: $recs
        }' > "$output_file"

    log "JSON report saved to: $output_file"
}

generate_markdown_report() {
    local trends="$1"
    local cni_analysis="$2"
    local recommendations="$3"
    local output_file="$4"

    log "Generating Markdown report..."

    cat > "$output_file" <<EOF
# Network Policy Performance Analysis Report

**Generated:** $(date)

## Executive Summary

This report analyzes the performance characteristics of Kubernetes NetworkPolicy enforcement across multiple benchmarks.

## Performance Trends

### Enforcement Latency
- **Average:** $(echo "$trends" | jq -r '.enforcement_latency.avg')s
- **Min:** $(echo "$trends" | jq -r '.enforcement_latency.min')s
- **Max:** $(echo "$trends" | jq -r '.enforcement_latency.max')s
- **StdDev:** $(echo "$trends" | jq -r '.enforcement_latency.stddev')s

### Throughput Impact
- **Average:** $(echo "$trends" | jq -r '.throughput_impact.avg')%
- **Min:** $(echo "$trends" | jq -r '.throughput_impact.min')%
- **Max:** $(echo "$trends" | jq -r '.throughput_impact.max')%
- **StdDev:** $(echo "$trends" | jq -r '.throughput_impact.stddev')%

### Latency Impact
- **Average:** $(echo "$trends" | jq -r '.latency_impact.avg')%
- **Min:** $(echo "$trends" | jq -r '.latency_impact.min')%
- **Max:** $(echo "$trends" | jq -r '.latency_impact.max')%
- **StdDev:** $(echo "$trends" | jq -r '.latency_impact.stddev')%

## CNI Plugin Comparison

EOF

    # Add CNI comparison table
    echo "| CNI Plugin | Avg Enforcement Latency | Avg Throughput Impact |" >> "$output_file"
    echo "|------------|-------------------------|----------------------|" >> "$output_file"

    while IFS= read -r cni; do
        if [[ -n "$cni" ]] && [[ "$cni" != "null" ]]; then
            local enforcement=$(echo "$cni_analysis" | jq -r ".\"$cni\".avg_enforcement_latency")
            local throughput=$(echo "$cni_analysis" | jq -r ".\"$cni\".avg_throughput_impact")
            echo "| $cni | ${enforcement}s | ${throughput}% |" >> "$output_file"
        fi
    done < <(echo "$cni_analysis" | jq -r 'keys[]')

    cat >> "$output_file" <<EOF

## Recommendations

EOF

    # Add recommendations
    echo "$recommendations" | jq -r '.[]' | while read -r rec; do
        echo "- $rec" >> "$output_file"
    done

    cat >> "$output_file" <<EOF

---
*Report generated by kubernetes-network-policy-recipes performance analysis tool*
EOF

    log "Markdown report saved to: $output_file"
}

generate_html_report() {
    local trends="$1"
    local cni_analysis="$2"
    local recommendations="$3"
    local output_file="$4"

    log "Generating HTML report..."

    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Network Policy Performance Analysis</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #667eea;
            padding-bottom: 15px;
            margin-bottom: 30px;
        }
        h2 {
            color: #555;
            margin-top: 40px;
            padding-bottom: 10px;
            border-bottom: 2px solid #f0f0f0;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .metric-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .metric-label {
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 5px;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
        }
        .metric-stats {
            font-size: 0.85em;
            opacity: 0.8;
            margin-top: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        th, td {
            padding: 15px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
        }
        th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-weight: 600;
        }
        tr:hover {
            background-color: #f8f9fa;
        }
        .recommendations {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 20px;
            margin: 20px 0;
            border-radius: 4px;
        }
        .recommendations ul {
            margin: 10px 0;
            padding-left: 20px;
        }
        .recommendations li {
            margin: 10px 0;
            line-height: 1.6;
        }
        .footer {
            margin-top: 60px;
            padding-top: 20px;
            border-top: 2px solid #e0e0e0;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: 600;
            margin-left: 8px;
        }
        .badge-good { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Network Policy Performance Analysis</h1>
        <p><strong>Generated:</strong> $(date) | <strong>Analysis Period:</strong> Last $TREND_DAYS days</p>

        <h2>📊 Performance Trends</h2>
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">Enforcement Latency</div>
                <div class="metric-value">$(echo "$trends" | jq -r '.enforcement_latency.avg')s</div>
                <div class="metric-stats">
                    Range: $(echo "$trends" | jq -r '.enforcement_latency.min')s - $(echo "$trends" | jq -r '.enforcement_latency.max')s<br>
                    StdDev: $(echo "$trends" | jq -r '.enforcement_latency.stddev')s
                </div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Throughput Impact</div>
                <div class="metric-value">$(echo "$trends" | jq -r '.throughput_impact.avg')%</div>
                <div class="metric-stats">
                    Range: $(echo "$trends" | jq -r '.throughput_impact.min')% - $(echo "$trends" | jq -r '.throughput_impact.max')%<br>
                    StdDev: $(echo "$trends" | jq -r '.throughput_impact.stddev')%
                </div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Latency Impact</div>
                <div class="metric-value">$(echo "$trends" | jq -r '.latency_impact.avg')%</div>
                <div class="metric-stats">
                    Range: $(echo "$trends" | jq -r '.latency_impact.min')% - $(echo "$trends" | jq -r '.latency_impact.max')%<br>
                    StdDev: $(echo "$trends" | jq -r '.latency_impact.stddev')%
                </div>
            </div>
        </div>

        <h2>🔌 CNI Plugin Comparison</h2>
        <table>
            <thead>
                <tr>
                    <th>CNI Plugin</th>
                    <th>Avg Enforcement Latency</th>
                    <th>Avg Throughput Impact</th>
                    <th>Performance Rating</th>
                </tr>
            </thead>
            <tbody>
EOF

    # Add CNI comparison rows
    while IFS= read -r cni; do
        if [[ -n "$cni" ]] && [[ "$cni" != "null" ]]; then
            local enforcement=$(echo "$cni_analysis" | jq -r ".\"$cni\".avg_enforcement_latency")
            local throughput=$(echo "$cni_analysis" | jq -r ".\"$cni\".avg_throughput_impact")

            # Determine badge
            local badge="good"
            if [[ $(echo "$throughput > 10" | bc) -eq 1 ]]; then
                badge="warning"
            fi
            if [[ $(echo "$throughput > 20" | bc) -eq 1 ]]; then
                badge="danger"
            fi

            cat >> "$output_file" <<EOTR
                <tr>
                    <td><strong>$cni</strong></td>
                    <td>${enforcement}s</td>
                    <td>${throughput}%</td>
                    <td><span class="badge badge-$badge">$([ "$badge" == "good" ] && echo "Good" || ([ "$badge" == "warning" ] && echo "Fair" || echo "Needs Attention"))</span></td>
                </tr>
EOTR
        fi
    done < <(echo "$cni_analysis" | jq -r 'keys[]')

    cat >> "$output_file" <<EOF
            </tbody>
        </table>

        <h2>💡 Recommendations</h2>
        <div class="recommendations">
            <ul>
EOF

    # Add recommendations
    echo "$recommendations" | jq -r '.[]' | while read -r rec; do
        echo "                <li>$rec</li>" >> "$output_file"
    done

    cat >> "$output_file" <<EOF
            </ul>
        </div>

        <div class="footer">
            <p>Generated by <strong>kubernetes-network-policy-recipes</strong> performance analysis tool</p>
            <p>For more information, visit the project repository</p>
        </div>
    </div>
</body>
</html>
EOF

    log "HTML report saved to: $output_file"
}

#############################################################################
# Main Execution
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --results-dir)
                RESULTS_DIR="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --compare)
                COMPARE_IDS="$2"
                shift 2
                ;;
            --trend)
                TREND_DAYS="$2"
                shift 2
                ;;
            --threshold)
                THRESHOLD="$2"
                shift 2
                ;;
            --cni-comparison)
                CNI_COMPARISON=true
                shift
                ;;
            --recommendations)
                RECOMMENDATIONS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    # Check for jq dependency
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    # Set default output file if not specified
    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="performance-analysis-$(date +%Y%m%d).${OUTPUT_FORMAT}"
    fi

    # Load benchmark results
    local results_files=()
    mapfile -t results_files < <(load_benchmark_results "$RESULTS_DIR")

    # Filter by date range
    local filtered_results=()
    mapfile -t filtered_results < <(filter_by_date_range "$TREND_DAYS" "${results_files[@]}")

    if [[ ${#filtered_results[@]} -eq 0 ]]; then
        log_error "No results found in the specified time range"
        exit 1
    fi

    # Perform analysis
    local trends=$(analyze_trends "${filtered_results[@]}")
    local cni_analysis=$(analyze_by_cni "${filtered_results[@]}")
    local recommendations=$(generate_recommendations "$trends")

    # Generate reports based on format
    case "$OUTPUT_FORMAT" in
        json)
            generate_json_report "$trends" "$cni_analysis" "$recommendations" "$OUTPUT_FILE"
            ;;
        markdown|md)
            generate_markdown_report "$trends" "$cni_analysis" "$recommendations" "$OUTPUT_FILE"
            ;;
        html)
            generate_html_report "$trends" "$cni_analysis" "$recommendations" "$OUTPUT_FILE"
            ;;
        all)
            generate_json_report "$trends" "$cni_analysis" "$recommendations" "${OUTPUT_FILE%.html}.json"
            generate_markdown_report "$trends" "$cni_analysis" "$recommendations" "${OUTPUT_FILE%.html}.md"
            generate_html_report "$trends" "$cni_analysis" "$recommendations" "${OUTPUT_FILE%.html}.html"
            ;;
        *)
            log_error "Unknown format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac

    log "✓ Analysis complete!"
}

# Run main function
main "$@"
