#!/bin/bash

# Monitor script for Registry Data Generator Validation Scenarios
# This script monitors the progress of all deployed validation scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="registry-data-generator"
REFRESH_INTERVAL=30
WATCH_MODE=false

function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Monitor registry data generator validation scenarios"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -n, --namespace NAME       Kubernetes namespace (default: registry-data-generator)"
    echo "  -i, --interval SECONDS     Refresh interval in seconds (default: 30)"
    echo "  -w, --watch               Watch mode (continuous monitoring)"
    echo "  --logs SCENARIO           Show logs for specific scenario"
    echo "  --summary                 Show summary only"
    echo ""
    echo "Examples:"
    echo "  $0                        # One-time status check"
    echo "  $0 --watch                # Continuous monitoring"
    echo "  $0 --logs acr-5l-50mb     # Show logs for specific scenario"
}

function log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function get_job_status() {
    local job_name=$1
    local status
    status=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "NotFound")
    
    if [ "$status" == "True" ]; then
        echo "Completed"
    elif [ "$status" == "NotFound" ]; then
        echo "Not Found"
    else
        local failed_status
        failed_status=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "False")
        if [ "$failed_status" == "True" ]; then
            echo "Failed"
        else
            echo "Running"
        fi
    fi
}

function get_pod_status() {
    local job_name=$1
    kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown"
}

function get_job_progress() {
    local job_name=$1
    local succeeded
    local total
    
    succeeded=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    total=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.spec.completions}' 2>/dev/null || echo "1")
    
    echo "${succeeded}/${total}"
}

function get_job_duration() {
    local job_name=$1
    local start_time
    local end_time
    
    start_time=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
    
    if [ -z "$start_time" ]; then
        echo "N/A"
        return
    fi
    
    # Check if job is completed
    local status
    status=$(get_job_status "$job_name")
    
    if [ "$status" == "Completed" ] || [ "$status" == "Failed" ]; then
        end_time=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.completionTime}' 2>/dev/null || echo "")
        if [ -z "$end_time" ]; then
            # If no completion time, use current time
            end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        fi
    else
        end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi
    
    # Calculate duration using date command
    local start_epoch
    local end_epoch
    start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -d "$end_time" +%s 2>/dev/null || echo "0")
    
    if [ "$start_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
        local duration=$((end_epoch - start_epoch))
        local hours=$((duration / 3600))
        local minutes=$(((duration % 3600) / 60))
        local seconds=$((duration % 60))
        
        if [ "$hours" -gt 0 ]; then
            printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
        else
            printf "%02d:%02d" "$minutes" "$seconds"
        fi
    else
        echo "N/A"
    fi
}

function show_detailed_status() {
    clear
    echo "==============================================================================="
    echo "Registry Data Generator - Validation Scenarios Monitor"
    echo "==============================================================================="
    echo "Namespace: $NAMESPACE"
    echo "Timestamp: $(date)"
    echo ""
    
    # Get all jobs in the namespace
    local jobs
    jobs=$(kubectl get jobs -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
    
    if [ -z "$jobs" ]; then
        log_warning "No jobs found in namespace: $NAMESPACE"
        return
    fi
    
    # Table header
    printf "%-20s %-12s %-15s %-10s %-12s %-10s\n" "SCENARIO" "STATUS" "POD_STATUS" "PROGRESS" "DURATION" "RESTART"
    printf "%-20s %-12s %-15s %-10s %-12s %-10s\n" "--------" "------" "----------" "--------" "--------" "-------"
    
    # Process each job
    echo "$jobs" | while read -r job_name; do
        if [ -n "$job_name" ]; then
            local scenario
            scenario=$(echo "$job_name" | sed 's/^rdg-//')
            
            local job_status
            job_status=$(get_job_status "$job_name")
            
            local pod_status
            pod_status=$(get_pod_status "$job_name")
            
            local progress
            progress=$(get_job_progress "$job_name")
            
            local duration
            duration=$(get_job_duration "$job_name")
            
            local restart_count
            restart_count=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
            
            # Color coding for status
            case $job_status in
                "Completed")
                    job_status="${GREEN}Completed${NC}"
                    ;;
                "Failed")
                    job_status="${RED}Failed${NC}"
                    ;;
                "Running")
                    job_status="${YELLOW}Running${NC}"
                    ;;
                *)
                    job_status="${RED}$job_status${NC}"
                    ;;
            esac
            
            printf "%-20s %-20s %-15s %-10s %-12s %-10s\n" "$scenario" "$job_status" "$pod_status" "$progress" "$duration" "$restart_count"
        fi
    done
    
    echo ""
    echo "==============================================================================="
    
    # Overall summary
    local total_jobs
    local completed_jobs
    local failed_jobs
    local running_jobs
    
    total_jobs=$(echo "$jobs" | wc -l)
    completed_jobs=$(echo "$jobs" | xargs -I {} kubectl get job {} -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -c "True" || echo "0")
    failed_jobs=$(echo "$jobs" | xargs -I {} kubectl get job {} -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null | grep -c "True" || echo "0")
    running_jobs=$((total_jobs - completed_jobs - failed_jobs))
    
    echo "Summary: Total: $total_jobs | Completed: $completed_jobs | Running: $running_jobs | Failed: $failed_jobs"
}

function show_summary() {
    local jobs
    jobs=$(kubectl get jobs -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
    
    if [ -z "$jobs" ]; then
        log_warning "No jobs found in namespace: $NAMESPACE"
        return
    fi
    
    local total_jobs
    local completed_jobs
    local failed_jobs
    local running_jobs
    
    total_jobs=$(echo "$jobs" | wc -l)
    completed_jobs=$(echo "$jobs" | xargs -I {} kubectl get job {} -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -c "True" || echo "0")
    failed_jobs=$(echo "$jobs" | xargs -I {} kubectl get job {} -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null | grep -c "True" || echo "0")
    running_jobs=$((total_jobs - completed_jobs - failed_jobs))
    
    echo "Registry Data Generator Status Summary"
    echo "======================================"
    echo "Total Jobs: $total_jobs"
    echo "Completed: $completed_jobs"
    echo "Running: $running_jobs"
    echo "Failed: $failed_jobs"
    echo "Completion Rate: $(( completed_jobs * 100 / total_jobs ))%"
}

function show_logs() {
    local scenario=$1
    local job_name="rdg-$scenario"
    
    log_info "Showing logs for scenario: $scenario"
    
    # Get the pod name for this job
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$pod_name" ]; then
        log_error "No pod found for scenario: $scenario"
        return 1
    fi
    
    # Show logs
    kubectl logs -n "$NAMESPACE" "$pod_name" --tail=100 -f
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -w|--watch)
            WATCH_MODE=true
            shift
            ;;
        --logs)
            show_logs "$2"
            exit 0
            ;;
        --summary)
            show_summary
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
if [ "$WATCH_MODE" == "true" ]; then
    log_info "Starting watch mode with refresh interval: ${REFRESH_INTERVAL}s"
    log_info "Press Ctrl+C to exit"
    
    while true; do
        show_detailed_status
        sleep "$REFRESH_INTERVAL"
    done
else
    show_detailed_status
fi
