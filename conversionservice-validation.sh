#!/bin/bash

# Conversion Service Validation Script
# This script orchestrates the complete validation workflow for the conversion service
# It creates registries, generates credentials, sets up Kubernetes cluster, and deploys scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

function log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Configuration
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
DOGFOOD_SUBSCRIPTION_ID="${DOGFOOD_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID}}"  # Dogfood cloud subscription
PRODUCTION_SUBSCRIPTION_ID="${PRODUCTION_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID}}"  # Production cloud subscription
AZURE_LOCATION="${AZURE_LOCATION:-centralus}"  # Default for both (backward compatibility)
ACR_LOCATION="${ACR_LOCATION:-${AZURE_LOCATION}}"  # ACR registries location
AKS_LOCATION="${AKS_LOCATION:-eastus2}"  # AKS cluster location
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-conversion-validation-cluster}"
NAMESPACE="${NAMESPACE:-registry-data-generator}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_REGISTRY_CREATION="${SKIP_REGISTRY_CREATION:-false}"
SKIP_CREDENTIAL_GENERATION="${SKIP_CREDENTIAL_GENERATION:-false}"
SKIP_CLUSTER_SETUP="${SKIP_CLUSTER_SETUP:-false}"
SKIP_SCENARIO_DEPLOYMENT="${SKIP_SCENARIO_DEPLOYMENT:-false}"

function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Complete validation workflow for conversion service testing"
    echo ""
    echo "Options:"
    echo "  -h, --help                   Show this help message"
    echo "  -g, --resource-group NAME    Azure resource group name"
    echo "  -s, --subscription ID        Azure subscription ID (used for both clouds if others not specified)"
    echo "  --dogfood-sub ID             Dogfood cloud subscription ID"
    echo "  --production-sub ID          Production cloud subscription ID"
    echo "  -l, --location LOCATION      Azure location for both ACR and AKS (default: centralus)"
    echo "  --acr-location LOCATION      Azure location for ACR registries (overrides -l)"
    echo "  --aks-location LOCATION      Azure location for AKS cluster (overrides -l)"
    echo "  -c, --cluster-name NAME      AKS cluster name (default: conversion-validation-cluster)"
    echo "  -n, --namespace NAMESPACE    Kubernetes namespace (default: registry-data-generator)"
    echo "  -d, --dry-run                Show what would be done without executing"
    echo "  --skip-registries            Skip ACR registry creation"
    echo "  --skip-credentials           Skip credential generation"
    echo "  --skip-cluster               Skip cluster setup"
    echo "  --skip-scenarios             Skip scenario deployment"
    echo "  --cleanup                    Clean up all resources"
    echo "  --status                     Show current status"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_SUBSCRIPTION_ID        Azure subscription ID (fallback for both clouds)"
    echo "  DOGFOOD_SUBSCRIPTION_ID       Dogfood cloud subscription ID (for ACR operations)"
    echo "  PRODUCTION_SUBSCRIPTION_ID    Production cloud subscription ID (for AKS operations)"
    echo "  AZURE_RESOURCE_GROUP          Azure resource group name"
    echo "  AZURE_LOCATION                Azure location (for both ACR and AKS)"
    echo "  ACR_LOCATION                  Azure location for ACR registries"
    echo "  AKS_LOCATION                  Azure location for AKS cluster"
    echo "  AKS_CLUSTER_NAME              AKS cluster name"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-rg -s my-sub-id                              # Same subscription for both clouds"
    echo "  $0 -g my-rg --dogfood-sub df-sub --production-sub prod-sub  # Different subscriptions"
    echo "  $0 -g my-rg -s fallback-sub --dogfood-sub df-sub      # Dogfood specific, production uses fallback"
    echo "  $0 -g my-rg -s my-sub --acr-location eastus           # ACR in eastus, AKS in eastus (fallback)"
    echo "  $0 --skip-registries -g my-rg -s my-sub-id            # Skip registry creation"
    echo "  $0 --status                                            # Check current status"
    echo "  $0 --cleanup -g my-rg -s my-sub-id                    # Clean up resources"
    echo ""
    echo "Workflow Steps:"
    echo "  1-2. Switch to dogfood cloud and create ACR registries + generate credentials"
    echo "  3. Switch to public cloud and create AKS cluster"
    echo "  4. Configure kubectl and create Kubernetes docker-registry secrets"
    echo "  5. Deploy validation scenarios using Helm charts"
    echo ""
    echo "Note: This script will switch between Azure clouds and require authentication:"
    echo "  - Dogfood cloud: Used for ACR registry operations"
    echo "  - Public cloud (AzureCloud): Used for AKS cluster operations"
}

function check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v az &> /dev/null; then
        missing_tools+=("azure-cli")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first"
        log_info "Note: This script will require authentication to both dogfood and public clouds"
        exit 1
    fi
    
    # Check if azure clouds are available
    if ! az cloud list --query "[?name=='dogfood']" --output tsv &> /dev/null; then
        log_warning "Dogfood cloud may not be configured. Make sure you have access to dogfood cloud."
    fi
    
    # Check required parameters
    if [ -z "$AZURE_SUBSCRIPTION_ID" ] && [ -z "$DOGFOOD_SUBSCRIPTION_ID" ] && [ -z "$PRODUCTION_SUBSCRIPTION_ID" ]; then
        log_error "No subscription ID specified. Use -s, --dogfood-sub, --production-sub, or set environment variables"
        exit 1
    fi
    
    if [ -z "$DOGFOOD_SUBSCRIPTION_ID" ]; then
        log_warning "DOGFOOD_SUBSCRIPTION_ID not set, using AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
        DOGFOOD_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
    fi
    
    if [ -z "$PRODUCTION_SUBSCRIPTION_ID" ]; then
        log_warning "PRODUCTION_SUBSCRIPTION_ID not set, using AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
        PRODUCTION_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
    fi
    
    if [ -z "$AZURE_RESOURCE_GROUP" ]; then
        log_error "Resource group not specified. Use -g or set AZURE_RESOURCE_GROUP"
        exit 1
    fi
    
    # Check if scripts exist
    local required_scripts=("create-acr-registries.sh" "generate-registry-credentials.sh" "create-aks-cluster.sh" "deploy-generation-scenarios.sh")
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "Required script not found: $script"
            exit 1
        fi
        if [ ! -x "$script" ]; then
            log_warning "Making $script executable..."
            chmod +x "$script"
        fi
    done
    
    # Check if Helm chart exists
    if [ ! -d "registry-data-generator" ]; then
        log_error "Helm chart directory not found: registry-data-generator"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

function switch_to_dogfood_cloud() {
    log_info "Switching to dogfood cloud for ACR operations..."
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would execute: az cloud set --name dogfood"
        log_info "[DRY RUN] Would execute: az login"
        return 0
    fi
    
    if ! az cloud set --name dogfood; then
        log_error "Failed to set cloud to dogfood"
        return 1
    fi
    
    log_info "Please authenticate with dogfood cloud..."
    if ! az login; then
        log_error "Failed to login to dogfood cloud"
        return 1
    fi
    
    log_success "Successfully switched to dogfood cloud"
}

function switch_to_public_cloud() {
    log_info "Switching to public cloud for AKS operations..."
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would execute: az cloud set --name AzureCloud"
        log_info "[DRY RUN] Would execute: az login"
        return 0
    fi
    
    if ! az cloud set --name AzureCloud; then
        log_error "Failed to set cloud to AzureCloud"
        return 1
    fi
    
    log_info "Please authenticate with public cloud..."
    if ! az login; then
        log_error "Failed to login to public cloud"
        return 1
    fi
    
    log_success "Successfully switched to public cloud"
}

function step_dogfood_operations() {
    # Handle both registry creation and credential generation in dogfood cloud
    local skip_registries="$SKIP_REGISTRY_CREATION"
    local skip_credentials="$SKIP_CREDENTIAL_GENERATION"
    
    # If both operations are skipped, don't switch clouds at all
    if [ "$skip_registries" == "true" ] && [ "$skip_credentials" == "true" ]; then
        log_info "Skipping all dogfood cloud operations as requested"
        return 0
    fi
    
    log_step "Steps 1-2: Dogfood cloud operations (registries and credentials)..."
    
    # Switch to dogfood cloud once for both operations
    if ! switch_to_dogfood_cloud; then
        log_error "Failed to switch to dogfood cloud"
        return 1
    fi
    
    # Step 1: Create registries
    if [ "$skip_registries" != "true" ]; then
        log_info "Creating ACR registries..."
        
        local cmd_args=()
        cmd_args+=("-g" "$AZURE_RESOURCE_GROUP")
        cmd_args+=("-s" "$DOGFOOD_SUBSCRIPTION_ID")
        cmd_args+=("-l" "$ACR_LOCATION")
        
        if [ "$DRY_RUN" == "true" ]; then
            cmd_args+=("--dry-run")
        fi
        
        log_info "Executing: ./create-acr-registries.sh ${cmd_args[*]}"
        
        if ./create-acr-registries.sh "${cmd_args[@]}"; then
            log_success "Registry creation completed"
        else
            log_error "Registry creation failed"
            return 1
        fi
    else
        log_info "Skipping registry creation as requested"
    fi
    
    # Step 2: Generate credentials (no need to switch clouds again)
    if [ "$skip_credentials" != "true" ]; then
        log_info "Generating registry credentials..."
        
        local cmd_args=()
        cmd_args+=("-g" "$AZURE_RESOURCE_GROUP")
        cmd_args+=("-s" "$DOGFOOD_SUBSCRIPTION_ID")
        
        if [ "$DRY_RUN" == "true" ]; then
            cmd_args+=("--dry-run")
        fi
        
        log_info "Executing: ./generate-registry-credentials.sh ${cmd_args[*]}"
        
        if ./generate-registry-credentials.sh "${cmd_args[@]}"; then
            log_success "Credential generation completed"
            
            # Load the generated credentials
            if [ -f "config.env" ]; then
                log_info "Loading generated credentials from config.env"
                source config.env
                log_success "Credentials loaded successfully"
            else
                log_warning "config.env not found - credentials may not be available"
            fi
        else
            log_error "Credential generation failed"
            return 1
        fi
    else
        log_info "Skipping credential generation as requested"
    fi
    
    log_success "Dogfood cloud operations completed"
}

function step_setup_cluster() {
    if [ "$SKIP_CLUSTER_SETUP" == "true" ]; then
        log_info "Skipping cluster setup as requested"
        return 0
    fi
    
    log_step "Step 3: Setting up AKS cluster and Kubernetes secrets..."
    
    # Switch to public cloud for AKS operations
    if ! switch_to_public_cloud; then
        log_error "Failed to switch to public cloud for AKS operations"
        return 1
    fi
    
    local cmd_args=()
    cmd_args+=("-g" "$AZURE_RESOURCE_GROUP")
    cmd_args+=("-s" "$PRODUCTION_SUBSCRIPTION_ID")
    cmd_args+=("-l" "$AKS_LOCATION")
    cmd_args+=("-c" "$AKS_CLUSTER_NAME")
    
    if [ "$DRY_RUN" == "true" ]; then
        cmd_args+=("--dry-run")
    fi
    
    log_info "Executing: ./create-aks-cluster.sh ${cmd_args[*]}"
    
    if ./create-aks-cluster.sh "${cmd_args[@]}"; then
        log_success "Cluster setup completed"
        
        # Verify kubectl context
        if [ "$DRY_RUN" != "true" ]; then
            log_info "Verifying kubectl context..."
            if kubectl cluster-info &> /dev/null; then
                log_success "kubectl is properly configured"
                
                # Check if namespace exists
                if kubectl get namespace "$NAMESPACE" &> /dev/null; then
                    log_success "Namespace '$NAMESPACE' is ready"
                else
                    log_warning "Namespace '$NAMESPACE' not found"
                fi
                
            # Check registry secrets
            local secret_count
            secret_count=$(kubectl get secrets -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "regcred-" || echo "0")
            if [ "$secret_count" -gt 0 ]; then
                log_info "Found $secret_count registry secrets (legacy - not needed for current setup)"
            else
                log_info "No registry secrets found (expected - credentials passed directly to Helm)"
            fi            else
                log_error "kubectl is not properly configured"
                return 1
            fi
        fi
    else
        log_error "Cluster setup failed"
        return 1
    fi
}

function step_deploy_scenarios() {
    if [ "$SKIP_SCENARIO_DEPLOYMENT" == "true" ]; then
        log_info "Skipping scenario deployment as requested"
        return 0
    fi
    
    log_step "Step 4: Deploying validation scenarios..."
    
    # Make sure we have the credentials loaded
    if [ -f "config.env" ] && [ "$DRY_RUN" != "true" ]; then
        log_info "Loading credentials for scenario deployment"
        source config.env
    fi
    
    local cmd_args=()
    if [ "$DRY_RUN" == "true" ]; then
        cmd_args+=("--dry-run")
    fi
    
    log_info "Executing: ./deploy-generation-scenarios.sh ${cmd_args[*]}"
    
    if ./deploy-generation-scenarios.sh "${cmd_args[@]}"; then
        log_success "Scenario deployment completed"
    else
        log_error "Scenario deployment failed"
        return 1
    fi
}

function show_status() {
    log_info "Conversion Service Validation Status"
    echo "=================================="
    echo ""
    
    # Check Azure login
    if az account show &> /dev/null; then
        local current_subscription
        current_subscription=$(az account show --query "name" -o tsv 2>/dev/null || echo "Unknown")
        local current_cloud
        current_cloud=$(az cloud show --query "name" -o tsv 2>/dev/null || echo "Unknown")
        echo "✅ Azure CLI: Logged in (Cloud: $current_cloud, Subscription: $current_subscription)"
    else
        echo "❌ Azure CLI: Not logged in"
    fi
    
    # Check kubectl
    if kubectl cluster-info &> /dev/null; then
        local current_context
        current_context=$(kubectl config current-context 2>/dev/null || echo "None")
        echo "✅ kubectl: Connected (Context: $current_context)"
        
        # Check namespace
        if kubectl get namespace "$NAMESPACE" &> /dev/null; then
            echo "✅ Namespace: $NAMESPACE exists"
            
            # Check registry secrets (legacy check)
            local secret_count
            secret_count=$(kubectl get secrets -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "regcred-" || echo "0")
            if [ "$secret_count" -gt 0 ]; then
                echo "ℹ️  Registry Secrets: $secret_count legacy secrets found (not needed)"
            else
                echo "✅ Registry Authentication: Direct credential passing (no secrets needed)"
            fi
            
            # Check deployments
            local deployment_count
            deployment_count=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$deployment_count" -gt 0 ]; then
                echo "✅ Deployments: $deployment_count scenarios deployed"
                
                # Show deployment status
                echo ""
                echo "Deployment Status:"
                kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r name ready _ _ _; do
                    if [[ "$ready" == *"/"* ]]; then
                        local current=$(echo "$ready" | cut -d'/' -f1)
                        local desired=$(echo "$ready" | cut -d'/' -f2)
                        if [ "$current" == "$desired" ] && [ "$current" -gt 0 ]; then
                            echo "  ✅ $name: $ready"
                        else
                            echo "  ⚠️  $name: $ready"
                        fi
                    else
                        echo "  ❓ $name: $ready"
                    fi
                done
            else
                echo "❌ Deployments: No scenarios deployed"
            fi
        else
            echo "❌ Namespace: $NAMESPACE not found"
        fi
    else
        echo "❌ kubectl: Not connected"
    fi
    
    # Check config file
    if [ -f "config.env" ]; then
        echo "✅ Configuration: config.env exists"
    else
        echo "❌ Configuration: config.env not found"
    fi
    
    # Check ACR registries (if subscription is set)
    if [ -n "$DOGFOOD_SUBSCRIPTION_ID" ] && [ -n "$AZURE_RESOURCE_GROUP" ]; then
        echo ""
        echo "Checking ACR registries (in dogfood cloud)..."
        local registry_count
        # Note: This check might not work if currently in production cloud
        registry_count=$(az acr list --resource-group "$AZURE_RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        if [ "$registry_count" -gt 0 ]; then
            echo "✅ ACR Registries: $registry_count registries found"
        else
            echo "❌ ACR Registries: No registries found (or not in dogfood cloud)"
        fi
    fi
    
    echo ""
    echo "Next steps:"
    if ! az account show &> /dev/null; then
        echo "  1. Run 'az login' to authenticate with Azure"
    elif [ -z "$DOGFOOD_SUBSCRIPTION_ID" ] || [ -z "$PRODUCTION_SUBSCRIPTION_ID" ] || [ -z "$AZURE_RESOURCE_GROUP" ]; then
        echo "  1. Set subscription IDs and resource group:"
        echo "     export DOGFOOD_SUBSCRIPTION_ID=<dogfood-sub-id>"
        echo "     export PRODUCTION_SUBSCRIPTION_ID=<production-sub-id>"
        echo "     export AZURE_RESOURCE_GROUP=<resource-group>"
        echo "  2. Run '$0 --dogfood-sub <df-sub> --production-sub <prod-sub> -g <rg>' to start validation"
    elif ! kubectl cluster-info &> /dev/null; then
        echo "  1. Run '$0 --dogfood-sub $DOGFOOD_SUBSCRIPTION_ID --production-sub $PRODUCTION_SUBSCRIPTION_ID -g $AZURE_RESOURCE_GROUP' to set up cluster"
    else
        echo "  1. Monitor deployments: kubectl get deployments -n $NAMESPACE -w"
        echo "  2. View logs: kubectl logs -n $NAMESPACE -l app=registry-data-generator"
        echo "  3. Clean up: $0 --cleanup --dogfood-sub $DOGFOOD_SUBSCRIPTION_ID --production-sub $PRODUCTION_SUBSCRIPTION_ID -g $AZURE_RESOURCE_GROUP"
    fi
}

function cleanup_resources() {
    log_step "Cleaning up all validation resources..."
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would clean up the following resources:"
        log_info "  - AKS cluster: $AKS_CLUSTER_NAME"
        log_info "  - All ACR registries in resource group: $AZURE_RESOURCE_GROUP"
        log_info "  - Local config.env file"
        return 0
    fi
    
    # Clean up AKS cluster (in public cloud)
    log_info "Cleaning up AKS cluster..."
    if ! switch_to_public_cloud; then
        log_warning "Failed to switch to public cloud for cleanup"
    elif ./create-aks-cluster.sh --cleanup -g "$AZURE_RESOURCE_GROUP" -s "$PRODUCTION_SUBSCRIPTION_ID"; then
        log_success "AKS cluster cleanup completed"
    else
        log_warning "AKS cluster cleanup failed or cluster doesn't exist"
    fi
    
    # Clean up ACR registries (in dogfood cloud)
    log_info "Cleaning up ACR registries..."
    if ! switch_to_dogfood_cloud; then
        log_warning "Failed to switch to dogfood cloud for cleanup"
    elif ./create-acr-registries.sh --cleanup -g "$AZURE_RESOURCE_GROUP" -s "$DOGFOOD_SUBSCRIPTION_ID"; then
        log_success "ACR registries cleanup completed"
    else
        log_warning "ACR registries cleanup failed or registries don't exist"
    fi
    
    # Clean up local config file
    if [ -f "config.env" ]; then
        log_info "Removing local config.env file..."
        rm -f config.env
        log_success "Local config file removed"
    fi
    
    log_success "Cleanup completed"
}

function run_full_workflow() {
    log_info "Starting Conversion Service Validation Workflow"
    log_info "=============================================="
    echo ""
    log_info "Configuration:"
    log_info "  Dogfood Subscription: $DOGFOOD_SUBSCRIPTION_ID"
    log_info "  Production Subscription: $PRODUCTION_SUBSCRIPTION_ID"
    log_info "  Resource Group: $AZURE_RESOURCE_GROUP"
    log_info "  ACR Location: $ACR_LOCATION"
    log_info "  AKS Location: $AKS_LOCATION"
    log_info "  Cluster Name: $AKS_CLUSTER_NAME"
    log_info "  Namespace: $NAMESPACE"
    log_info "  Dry Run: $DRY_RUN"
    echo ""
    
    local start_time
    start_time=$(date +%s)
    
    # Execute workflow steps
    step_dogfood_operations
    step_setup_cluster
    step_deploy_scenarios
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_success "🎉 Conversion Service Validation Workflow Completed!"
    log_info "Total execution time: $duration seconds"
    echo ""
    log_info "What's next?"
    log_info "  1. Monitor scenario deployments: kubectl get deployments -n $NAMESPACE -w"
    log_info "  2. View logs: kubectl logs -n $NAMESPACE -l app=registry-data-generator --follow"
    log_info "  3. Check validation results in your registries"
    log_info "  4. Clean up when done: $0 --cleanup"
}

# Parse command line arguments
CLEANUP=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -g|--resource-group)
            AZURE_RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            AZURE_SUBSCRIPTION_ID="$2"
            # Update both subscriptions if they haven't been explicitly set
            if [ -z "$DOGFOOD_SUBSCRIPTION_ID" ] || [ "$DOGFOOD_SUBSCRIPTION_ID" == "$AZURE_SUBSCRIPTION_ID" ]; then
                DOGFOOD_SUBSCRIPTION_ID="$2"
            fi
            if [ -z "$PRODUCTION_SUBSCRIPTION_ID" ] || [ "$PRODUCTION_SUBSCRIPTION_ID" == "$AZURE_SUBSCRIPTION_ID" ]; then
                PRODUCTION_SUBSCRIPTION_ID="$2"
            fi
            shift 2
            ;;
        --dogfood-sub)
            DOGFOOD_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --production-sub)
            PRODUCTION_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -l|--location)
            AZURE_LOCATION="$2"
            # Update both ACR and AKS locations if they haven't been explicitly set
            if [ "${ACR_LOCATION}" == "centralus" ] || [ "${ACR_LOCATION}" == "${AZURE_LOCATION}" ]; then
                ACR_LOCATION="$2"
            fi
            if [ "${AKS_LOCATION}" == "centralus" ] || [ "${AKS_LOCATION}" == "${AZURE_LOCATION}" ]; then
                AKS_LOCATION="$2"
            fi
            shift 2
            ;;
        --acr-location)
            ACR_LOCATION="$2"
            shift 2
            ;;
        --aks-location)
            AKS_LOCATION="$2"
            shift 2
            ;;
        -c|--cluster-name)
            AKS_CLUSTER_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        --skip-registries)
            SKIP_REGISTRY_CREATION="true"
            shift
            ;;
        --skip-credentials)
            SKIP_CREDENTIAL_GENERATION="true"
            shift
            ;;
        --skip-cluster)
            SKIP_CLUSTER_SETUP="true"
            shift
            ;;
        --skip-scenarios)
            SKIP_SCENARIO_DEPLOYMENT="true"
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Main execution
if [ "$SHOW_STATUS" == "true" ]; then
    show_status
    exit 0
fi

if [ "$CLEANUP" == "true" ]; then
    check_prerequisites
    cleanup_resources
    exit 0
fi

# Run the full workflow
check_prerequisites
run_full_workflow
