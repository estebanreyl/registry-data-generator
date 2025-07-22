#!/bin/bash

# Deployment script for Registry Data Generator Scenarios
# This script deploys all data generation scenarios to generate test data for registry streaming conversion

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="registry-data-generator"
CHART_PATH="./registry-data-generator"
REGISTRY_BASE_URI="${REGISTRY_BASE_URI:-your-registry.azurecr-test.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"
DRY_RUN="${DRY_RUN:-false}"
PARALLEL_DEPLOYMENTS="${PARALLEL_DEPLOYMENTS:-3}"

# Registry mapping for each generation scenario
declare -A SCENARIO_REGISTRIES=(
    ["acr-5l-50mb"]="${REGISTRY_ACR5L50MB:-acr5l50mb.azurecr-test.io}"
    ["acr-5l-100mb"]="${REGISTRY_ACR5L100MB:-acr5l100mb.azurecr-test.io}"
    ["acr-5l-300mb"]="${REGISTRY_ACR5L300MB:-acr5l300mb.azurecr-test.io}"
    ["acr-5l-1gb"]="${REGISTRY_ACR5L1GB:-acr5l1gb.azurecr-test.io}"
    ["acr-5l-2gb"]="${REGISTRY_ACR5L2GB:-acr5l2gb.azurecr-test.io}"
    ["acr-20l-50mb"]="${REGISTRY_ACR20L50MB:-acr20l50mb.azurecr-test.io}"
    ["acr-20l-100mb"]="${REGISTRY_ACR20L100MB:-acr20l100mb.azurecr-test.io}"
    ["acr-20l-300mb"]="${REGISTRY_ACR20L300MB:-acr20l300mb.azurecr-test.io}"
    ["acr-20l-1gb"]="${REGISTRY_ACR20L1GB:-acr20l1gb.azurecr-test.io}"
    ["acr-20l-2gb"]="${REGISTRY_ACR20L2GB:-acr20l2gb.azurecr-test.io}"
    ["acr-50l-50mb"]="${REGISTRY_ACR50L50MB:-acr50l50mb.azurecr-test.io}"
    ["acr-50l-100mb"]="${REGISTRY_ACR50L100MB:-acr50l100mb.azurecr-test.io}"
    ["acr-50l-300mb"]="${REGISTRY_ACR50L300MB:-acr50l300mb.azurecr-test.io}"
    ["acr-50l-1gb"]="${REGISTRY_ACR50L1GB:-acr50l1gb.azurecr-test.io}"
    ["acr-50l-2gb"]="${REGISTRY_ACR50L2GB:-acr50l2gb.azurecr-test.io}"
)

# Environment variable name mapping for each scenario
declare -A SCENARIO_ENV_VARS=(
    ["acr-5l-50mb"]="ACR5L50MB"
    ["acr-5l-100mb"]="ACR5L100MB" 
    ["acr-5l-300mb"]="ACR5L300MB"
    ["acr-5l-1gb"]="ACR5L1GB"
    ["acr-5l-2gb"]="ACR5L2GB"
    ["acr-20l-50mb"]="ACR20L50MB"
    ["acr-20l-100mb"]="ACR20L100MB"
    ["acr-20l-300mb"]="ACR20L300MB"
    ["acr-20l-1gb"]="ACR20L1GB"
    ["acr-20l-2gb"]="ACR20L2GB"
    ["acr-50l-50mb"]="ACR50L50MB"
    ["acr-50l-100mb"]="ACR50L100MB"
    ["acr-50l-300mb"]="ACR50L300MB"
    ["acr-50l-1gb"]="ACR50L1GB"
    ["acr-50l-2gb"]="ACR50L2GB"
)

# Data generation scenarios array
declare -a SCENARIOS=(
    "acr-5l-50mb"
    "acr-5l-100mb"
    "acr-5l-300mb"
    "acr-5l-1gb"
    "acr-5l-2gb"
    "acr-20l-50mb"
    "acr-20l-100mb"
    "acr-20l-300mb"
    "acr-20l-1gb"
    "acr-20l-2gb"
    "acr-50l-50mb"
    "acr-50l-100mb"
    "acr-50l-300mb"
    "acr-50l-1gb"
    "acr-50l-2gb"
)

function print_usage() {
    echo "Usage: $0 [OPTIONS] [SCENARIOS...]"
    echo ""
    echo "Deploy registry data generator scenarios to AKS cluster"
    echo "Each scenario deploys to its own dedicated registry"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -n, --namespace NAME       Kubernetes namespace (default: registry-data-generator)"
    echo "  -r, --registry-base URI    Base registry URI (default: your-registry.azurecr.io)"
    echo "  -u, --username USER        Docker registry username"
    echo "  -p, --password PASS        Docker registry password"
    echo "  -d, --dry-run              Perform a dry run (validate only)"
    echo "  -j, --parallel NUM         Number of parallel deployments (default: 3)"
    echo "  --list                     List all available scenarios"
    echo "  --clean                    Clean up all existing deployments"
    echo "  --status                   Show status of all deployments"
    echo "  --show-registries          Show registry mapping for all scenarios"
    echo ""
    echo "Scenarios:"
    echo "  If no scenarios are specified, all scenarios will be deployed"
    echo "  Available scenarios: ${SCENARIOS[*]}"
    echo ""
    echo "Registry Configuration:"
    echo "  Each scenario uses a dedicated registry. Configure individual"
    echo "  registry URIs using environment variables in config.env"
    echo ""
    echo "Examples:"
    echo "  $0 --registry-base myregistry.azurecr.io --username myuser --password mypass"
    echo "  $0 acr-5l-50mb acr-5l-100mb"
    echo "  $0 --dry-run --status"
    echo "  $0 --clean"
    echo "  $0 --show-registries"
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

function check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if chart directory exists
    if [ ! -d "$CHART_PATH" ]; then
        log_error "Helm chart directory not found: $CHART_PATH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

function create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

function create_docker_secret() {
    if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
        log_info "Creating Docker registry secrets for all scenarios..."
        
        # Create a secret for each unique registry
        local unique_registries=()
        for registry in "${SCENARIO_REGISTRIES[@]}"; do
            if [[ ! " ${unique_registries[@]} " =~ " ${registry} " ]]; then
                unique_registries+=("$registry")
            fi
        done
        
        for registry in "${unique_registries[@]}"; do
            local secret_name="regcred-$(echo "$registry" | tr '.' '-' | tr '[:upper:]' '[:lower:]')"
            log_info "Creating secret for registry: $registry"
            
            kubectl create secret docker-registry "$secret_name" \
                --docker-server="$registry" \
                --docker-username="$DOCKER_USERNAME" \
                --docker-password="$DOCKER_PASSWORD" \
                --namespace="$NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
        done
    else
        log_warning "Docker credentials not provided. Assuming public registry or existing auth."
    fi
}

function update_values_file() {
    local scenario=$1
    local values_file="${CHART_PATH}/values-${scenario}.yaml"
    local registry_name="${SCENARIO_REGISTRIES[$scenario]}"
    
    if [ ! -f "$values_file" ]; then
        log_error "Values file not found: $values_file" >&2
        return 1
    fi
    
    if [ -z "$registry_name" ]; then
        log_error "No registry name found for scenario: $scenario" >&2
        return 1
    fi
    
    # Get registry credentials for this scenario (dogfood environment requires admin credentials)
    local registry_var_base="${SCENARIO_ENV_VARS[$scenario]}"
    if [ -z "$registry_var_base" ]; then
        log_error "No environment variable mapping found for scenario: $scenario"
        return 1
    fi
    
    local registry_var="REGISTRY_${registry_var_base}"
    local username_var="${registry_var}_USERNAME"
    local password_var="${registry_var}_PASSWORD"
    
    local registry_uri="${!registry_var}"
    local username="${!username_var}"
    local password="${!password_var}"
    
    if [ -z "$registry_uri" ] || [ -z "$username" ] || [ -z "$password" ]; then
        log_error "Missing credentials for scenario: $scenario" >&2
        log_error "Expected variables: $registry_var, $username_var, $password_var" >&2
        log_error "For dogfood registries, use ./generate-registry-credentials.sh to generate credentials" >&2
        return 1
    fi
    
    # Create temporary values file with updated registry URI and credentials
    local temp_values="/tmp/values-${scenario}-temp.yaml"
    cp "$values_file" "$temp_values"
    
    # Update registry URI in temporary file
    sed -i "s|registryUri: your-registry.azurecr-test.io|registryUri: $registry_uri|g" "$temp_values"
    sed -i "s|registryUri: .*|registryUri: $registry_uri|g" "$temp_values"
    
    # Update Docker credentials for dogfood registry authentication
    sed -i "s|dockerUser: \"\"|dockerUser: \"$username\"|g" "$temp_values"
    sed -i "s|dockerUser: .*|dockerUser: \"$username\"|g" "$temp_values"
    
    sed -i "s|dockerPassword: \"\"|dockerPassword: \"$password\"|g" "$temp_values"
    sed -i "s|dockerPassword: .*|dockerPassword: \"$password\"|g" "$temp_values"
    
    # Update repo path to use scenario name as default
    sed -i "s|repoPath: .*|repoPath: docker-auto|g" "$temp_values"
    
    log_info "Updated values file for scenario $scenario using registry: $registry_uri" >&2
    log_info "Using admin credentials for dogfood registry authentication" >&2
    echo "$temp_values"
}

function deploy_scenario() {
    local scenario=$1
    local release_name="rdg-$scenario"
    
    log_info "Deploying scenario: $scenario"
    
    # Update values file
    local temp_values
    temp_values=$(update_values_file "$scenario")
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "Dry run for scenario: $scenario"
        helm upgrade --install "$release_name" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --values "$temp_values" \
            --dry-run
    else
        # Deploy the helm release
        helm upgrade --install "$release_name" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --values "$temp_values" \
            --wait \
            --timeout 600s
            
        if [ $? -eq 0 ]; then
            log_success "Successfully deployed scenario: $scenario"
        else
            log_error "Failed to deploy scenario: $scenario"
        fi
    fi
    
    # Clean up temporary file
    rm -f "$temp_values"
}

function deploy_scenarios_parallel() {
    local scenarios=("$@")
    local pids=()
    local active_jobs=0
    
    for scenario in "${scenarios[@]}"; do
        # Wait if we have reached the parallel limit
        while [ $active_jobs -ge $PARALLEL_DEPLOYMENTS ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    wait "${pids[i]}"
                    unset pids[i]
                    active_jobs=$((active_jobs - 1))
                fi
            done
            sleep 1
        done
        
        # Start deployment in background
        deploy_scenario "$scenario" &
        pids+=($!)
        active_jobs=$((active_jobs + 1))
        
        # Small delay to avoid overwhelming the system
        sleep 2
    done
    
    # Wait for all remaining jobs to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

function show_status() {
    log_info "Showing deployment status..."
    
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Available pods:"
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "No pods found"
    
    echo ""
    echo "Helm releases:"
    helm list -n "$NAMESPACE" 2>/dev/null || echo "No releases found"
    
    echo ""
    echo "Jobs status:"
    kubectl get jobs -n "$NAMESPACE" --no-headers 2>/dev/null || echo "No jobs found"
}

function clean_deployments() {
    log_info "Cleaning up all deployments..."
    
    # Delete all helm releases in the namespace
    local releases
    releases=$(helm list -n "$NAMESPACE" --short 2>/dev/null || true)
    
    if [ -n "$releases" ]; then
        echo "$releases" | while read -r release; do
            log_info "Deleting release: $release"
            helm delete "$release" -n "$NAMESPACE"
        done
    fi
    
    # Delete the namespace (this will clean up any remaining resources)
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    
    log_success "Cleanup completed"
}

function list_scenarios() {
    echo "Available data generation scenarios:"
    echo ""
    for scenario in "${SCENARIOS[@]}"; do
        echo "  - $scenario"
    done
}

function show_registry_mappings() {
    echo "Registry mappings for data generation scenarios:"
    echo ""
    printf "%-20s %-50s\n" "SCENARIO" "REGISTRY"
    printf "%-20s %-50s\n" "--------" "--------"
    
    for scenario in "${SCENARIOS[@]}"; do
        local registry="${SCENARIO_REGISTRIES[$scenario]}"
        printf "%-20s %-50s\n" "$scenario" "$registry"
    done
    echo ""
    echo "Note: Configure individual registry URIs in config.env using environment variables"
    echo "      like REGISTRY_ACR_5L_50MB, REGISTRY_ACR_5L_100MB, etc."
}

# Parse command line arguments
SCENARIOS_TO_DEPLOY=()
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
        -r|--registry-base)
            REGISTRY_BASE_URI="$2"
            shift 2
            ;;
        -u|--username)
            DOCKER_USERNAME="$2"
            shift 2
            ;;
        -p|--password)
            DOCKER_PASSWORD="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -j|--parallel)
            PARALLEL_DEPLOYMENTS="$2"
            shift 2
            ;;
        --list)
            list_scenarios
            exit 0
            ;;
        --show-registries)
            show_registry_mappings
            exit 0
            ;;
        --clean)
            clean_deployments
            exit 0
            ;;
        --status)
            show_status
            exit 0
            ;;
        *)
            # Check if it's a valid scenario
            if [[ " ${SCENARIOS[*]} " =~ " $1 " ]]; then
                SCENARIOS_TO_DEPLOY+=("$1")
            else
                log_error "Unknown option or invalid scenario: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# If no specific scenarios provided, deploy all
if [ ${#SCENARIOS_TO_DEPLOY[@]} -eq 0 ]; then
    SCENARIOS_TO_DEPLOY=("${SCENARIOS[@]}")
fi

# Main execution
log_info "Starting Registry Data Generator deployment..."
log_info "Base Registry URI: $REGISTRY_BASE_URI"
log_info "Namespace: $NAMESPACE"
log_info "Scenarios to deploy: ${SCENARIOS_TO_DEPLOY[*]}"
log_info "Each scenario will deploy to its own dedicated registry"

# Show registry mappings for scenarios being deployed
echo ""
echo "Registry mappings for selected scenarios:"
printf "%-20s %-50s\n" "SCENARIO" "REGISTRY"
printf "%-20s %-50s\n" "--------" "--------"
for scenario in "${SCENARIOS_TO_DEPLOY[@]}"; do
    registry="${SCENARIO_REGISTRIES[$scenario]}"
    printf "%-20s %-50s\n" "$scenario" "$registry"
done
echo ""

check_prerequisites
create_namespace
create_docker_secret

if [ "$DRY_RUN" == "true" ]; then
    log_info "Performing dry run..."
else
    log_info "Starting deployment of ${#SCENARIOS_TO_DEPLOY[@]} scenarios..."
fi

deploy_scenarios_parallel "${SCENARIOS_TO_DEPLOY[@]}"

if [ "$DRY_RUN" == "false" ]; then
    log_success "Deployment completed!"
    show_status
fi

log_info "Done!"
