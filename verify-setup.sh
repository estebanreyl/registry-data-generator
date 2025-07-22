#!/bin/bash

# Verification script for Registry Data Generator Validation Scenarios
# This script validates the setup before deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

function check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local errors=0
    
    # Check kubectl
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is installed"
        if kubectl cluster-info &> /dev/null; then
            log_success "kubectl can connect to cluster"
        else
            log_error "kubectl cannot connect to cluster"
            errors=$((errors + 1))
        fi
    else
        log_error "kubectl is not installed"
        errors=$((errors + 1))
    fi
    
    # Check helm
    if command -v helm &> /dev/null; then
        log_success "helm is installed"
        local helm_version
        helm_version=$(helm version --short 2>/dev/null | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | head -1)
        log_info "Helm version: $helm_version"
    else
        log_error "helm is not installed"
        errors=$((errors + 1))
    fi
    
    # Check chart directory
    if [ -d "./registry-data-generator" ]; then
        log_success "Helm chart directory exists"
    else
        log_error "Helm chart directory not found: ./registry-data-generator"
        errors=$((errors + 1))
    fi
    
    return $errors
}

function check_values_files() {
    log_info "Checking values files..."
    
    local errors=0
    local scenarios=(
        "acr-5l-50mb" "acr-5l-100mb" "acr-5l-300mb" "acr-5l-1gb" "acr-5l-2gb"
        "acr-20l-50mb" "acr-20l-100mb" "acr-20l-300mb" "acr-20l-1gb" "acr-20l-2gb"
        "acr-50l-50mb" "acr-50l-100mb" "acr-50l-300mb" "acr-50l-1gb" "acr-50l-2gb"
    )
    
    for scenario in "${scenarios[@]}"; do
        local values_file="./registry-data-generator/values-${scenario}.yaml"
        if [ -f "$values_file" ]; then
            log_success "Values file exists: $scenario"
        else
            log_error "Values file missing: $scenario"
            errors=$((errors + 1))
        fi
    done
    
    return $errors
}

function check_cluster_resources() {
    log_info "Checking cluster resources..."
    
    # Get node information
    local nodes
    nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    log_info "Cluster has $nodes nodes"
    
    # Get total cluster resources
    local total_cpu
    local total_memory
    total_cpu=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.cpu}' | tr ' ' '\n' | awk '{sum += $1} END {print sum}')
    total_memory=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.memory}' | tr ' ' '\n' | sed 's/Ki//' | awk '{sum += $1} END {print sum/1024/1024 " GB"}')
    
    log_info "Total cluster CPU: ${total_cpu} cores"
    log_info "Total cluster Memory: ${total_memory}"
    
    # Check if cluster has sufficient resources for at least one scenario
    if [ "$total_cpu" -lt 4 ]; then
        log_warning "Cluster may not have sufficient CPU resources for larger scenarios"
    else
        log_success "Cluster has sufficient CPU resources"
    fi
    
    return 0
}

function check_registry_access() {
    log_info "Checking registry access..."
    
    # Check if registry base URI is set
    if [ -z "$REGISTRY_BASE_URI" ]; then
        log_warning "REGISTRY_BASE_URI not set. Will use default placeholder."
        return 1
    fi
    
    log_info "Base Registry URI: $REGISTRY_BASE_URI"
    
    # Check individual registry configurations
    local scenarios=(
        "acr-5l-50mb" "acr-5l-100mb" "acr-5l-300mb" "acr-5l-1gb" "acr-5l-2gb"
        "acr-20l-50mb" "acr-20l-100mb" "acr-20l-300mb" "acr-20l-1gb" "acr-20l-2gb"
        "acr-50l-50mb" "acr-50l-100mb" "acr-50l-300mb" "acr-50l-1gb" "acr-50l-2gb"
    )
    
    local configured_registries=0
    for scenario in "${scenarios[@]}"; do
        local var_name="REGISTRY_$(echo "$scenario" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
        local registry_uri="${!var_name}"
        
        if [ -n "$registry_uri" ]; then
            configured_registries=$((configured_registries + 1))
            log_info "Registry for $scenario: $registry_uri"
        else
            log_warning "No registry configured for $scenario (using default pattern)"
        fi
    done
    
    log_info "Configured registries: $configured_registries/15"
    
    # Check if credentials are set
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
        log_warning "Docker credentials not set. Assuming public registry or existing auth."
        return 1
    fi
    
    log_info "Docker credentials provided"
    
    # Try to test registry access (optional) - test with base registry
    if command -v docker &> /dev/null; then
        log_info "Testing registry access with base registry..."
        if echo "$DOCKER_PASSWORD" | docker login "$REGISTRY_BASE_URI" -u "$DOCKER_USERNAME" --password-stdin &> /dev/null; then
            log_success "Registry authentication successful"
            docker logout "$REGISTRY_BASE_URI" &> /dev/null
        else
            log_error "Registry authentication failed"
            return 1
        fi
    else
        log_info "Docker not available for registry testing"
    fi
    
    return 0
}

function validate_helm_chart() {
    log_info "Validating Helm chart..."
    
    # Check if chart can be parsed
    if helm template registry-data-generator ./registry-data-generator &> /dev/null; then
        log_success "Helm chart is valid"
    else
        log_error "Helm chart validation failed"
        return 1
    fi
    
    return 0
}

function show_deployment_summary() {
    log_info "Deployment Summary:"
    echo ""
    echo "Scenarios to be deployed: 15"
    echo "Registry model: Each scenario deploys to its own dedicated registry"
    echo "Estimated total data: ~225 TB (15 TB per scenario)"
    echo "Estimated completion time: 24-72 hours (varies by cluster and registry)"
    echo ""
    echo "Resource requirements per scenario:"
    echo "  - CPU: 1-4 cores"
    echo "  - Memory: 1-40 GB"
    echo "  - Network: High bandwidth for uploads"
    echo ""
    echo "Registry structure:"
    echo "  - Each scenario uses a dedicated registry (e.g., acr-5l-50mb.azurecr.io)"
    echo "  - Repository path: docker-auto (default)"
    echo "  - This allows for independent testing and isolation"
    echo ""
    echo "Example registry mappings:"
    echo "  - acr-5l-50mb → acr5l50mb.azurecr-test.io"
    echo "  - acr-5l-100mb → acr5l100mb.azurecr-test.io"
    echo "  - acr-20l-1gb → acr20l1gb.azurecr-test.io"
    echo ""
}

function main() {
    echo "==============================================================================="
    echo "Registry Data Generator - Validation Scenarios Verification"
    echo "==============================================================================="
    echo ""
    
    local total_errors=0
    
    # Load config if available
    if [ -f "config.env" ]; then
        log_info "Loading configuration from config.env"
        source config.env
    else
        log_info "No config.env found. Using environment variables or defaults."
    fi
    
    # Run checks
    check_prerequisites
    total_errors=$((total_errors + $?))
    
    echo ""
    check_values_files
    total_errors=$((total_errors + $?))
    
    echo ""
    check_cluster_resources
    total_errors=$((total_errors + $?))
    
    echo ""
    check_registry_access
    # Don't count registry access as hard error
    
    echo ""
    validate_helm_chart
    total_errors=$((total_errors + $?))
    
    echo ""
    show_deployment_summary
    
    echo ""
    echo "==============================================================================="
    
    if [ $total_errors -eq 0 ]; then
        log_success "All checks passed! Ready for deployment."
        echo ""
        echo "Next steps:"
        echo "1. Review and update config.env with your registry details"
        echo "2. Run: source config.env"
        echo "3. Run: ./deploy-generation-scenarios.sh"
        echo "4. Monitor: ./monitor-validation-scenarios.sh --watch"
        return 0
    else
        log_error "Found $total_errors errors. Please fix them before deployment."
        return 1
    fi
}

# Run main function
main "$@"
