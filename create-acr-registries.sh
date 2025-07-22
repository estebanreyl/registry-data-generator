#!/bin/bash

# Azure Container Registry Creation Script for Validation Scenarios
# This script creates all 15 registries needed for the validation scenarios

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

# Configuration
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
SUBSCRIPTION="${AZURE_SUBSCRIPTION_ID:-}"
LOCATION="${AZURE_LOCATION:-centralus}"
SKU="${ACR_SKU:-Premium}"
ADMIN_ENABLED="${ACR_ADMIN_ENABLED:-true}"
DRY_RUN="${DRY_RUN:-false}"

# Validation scenarios - using valid ACR names (no dashes)
SCENARIOS=(
    "acr5l50mb" "acr5l100mb" "acr5l300mb" "acr5l1gb" "acr5l2gb"
    "acr20l50mb" "acr20l100mb" "acr20l300mb" "acr20l1gb" "acr20l2gb"
    "acr50l50mb" "acr50l100mb" "acr50l300mb" "acr50l1gb" "acr50l2gb"
)

function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Create Azure Container Registries for validation scenarios"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group GROUP    Azure resource group name"
    echo "  -s, --subscription SUB        Azure subscription ID"
    echo "  -l, --location LOCATION       Azure location (default: centralus)"
    echo "  --sku SKU                     ACR SKU (default: Premium)"
    echo "  --admin-enabled BOOL          Enable admin user (default: true)"
    echo "  -d, --dry-run                 Show what would be created without creating"
    echo "  --generate-config             Generate configuration entries"
    echo "  --cleanup                     Delete all registries"
    echo "  --check-existing              Check which registries exist"
    echo "  --create-missing-only         Create only missing registries"
    echo "  --show-credentials            Show admin credentials"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -g, --resource-group NAME  Azure resource group name"
    echo "  -s, --subscription ID      Azure subscription ID"
    echo "  -l, --location LOCATION    Azure location (default: centralus)"
    echo "  --sku SKU                  ACR SKU (default: Premium)"
    echo "  --admin-enabled BOOL       Enable admin user (default: true)"
    echo "  -d, --dry-run              Show what would be created without creating"
    echo "  --generate-config          Generate config.env entries"
    echo "  --cleanup                  Delete all created registries"
    echo "  --check-existing           Check which registries already exist"
    echo "  --create-missing           Create only missing registries"
    echo "  --show-credentials         Show admin credentials for existing registries"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_RESOURCE_GROUP       Default resource group"
    echo "  AZURE_SUBSCRIPTION_ID      Default subscription"
    echo "  AZURE_LOCATION              Default location"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-rg -s my-sub-id"
    echo "  $0 --generate-config"
    echo "  $0 --cleanup"
    echo "  $0 --check-existing"
    echo "  $0 --create-missing -g my-rg -s my-sub-id"
    echo "  $0 --show-credentials"
}

function check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first"
        exit 1
    fi
    
    # Check required parameters
    if [ -z "$RESOURCE_GROUP" ]; then
        log_error "Resource group not specified. Use -g or set AZURE_RESOURCE_GROUP"
        exit 1
    fi
    
    if [ -z "$SUBSCRIPTION" ]; then
        log_error "Subscription not specified. Use -s or set AZURE_SUBSCRIPTION_ID"
        exit 1
    fi
    
    # Set subscription
    az account set --subscription "$SUBSCRIPTION"
    
    # Check if resource group exists
    # if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    #     log_error "Resource group '$RESOURCE_GROUP' not found"
    #     exit 1
    # fi
    
    log_success "Prerequisites check passed"
}

function create_registry() {
    local registry_name=$1
    
    log_info "Creating registry: $registry_name"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would create registry: $registry_name"
        return 0
    fi
    
    # Check if registry already exists
    if az acr show --name "$registry_name" &> /dev/null; then
        log_warning "Registry '$registry_name' already exists, skipping"
        return 0
    fi
    
    # Create the registry
    if az acr create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$registry_name" \
        --sku "$SKU" \
        --location "$LOCATION" \
        --admin-enabled "$ADMIN_ENABLED" \
        --output none; then
        log_success "Created registry: $registry_name"
    else
        log_error "Failed to create registry: $registry_name"
        return 1
    fi
}

function create_all_registries() {
    log_info "Creating all validation scenario registries..."
    
    local failed_registries=()
    
    for scenario in "${SCENARIOS[@]}"; do
        if ! create_registry "$scenario"; then
            failed_registries+=("$scenario")
        fi
    done
    
    if [ ${#failed_registries[@]} -eq 0 ]; then
        log_success "All registries created successfully!"
    else
        log_error "Failed to create ${#failed_registries[@]} registries: ${failed_registries[*]}"
        return 1
    fi
}

function generate_config() {
    log_info "Generating config.env entries..."
    
    echo "# Generated Azure Container Registry configuration"
    echo "# Add these to your config.env file"
    echo ""
    echo "# Azure Configuration"
    echo "export AZURE_SUBSCRIPTION_ID=\"$SUBSCRIPTION\""
    echo "export AZURE_RESOURCE_GROUP=\"$RESOURCE_GROUP\""
    echo ""
    echo "# Base registry configuration"
    echo "export REGISTRY_BASE_URI=\"$(echo "${SCENARIOS[0]}" | tr '[:upper:]' '[:lower:]').azurecr-test.io\""
    echo ""
    echo "# Individual registry URIs"
    
    # Map scenario names to environment variable names
    declare -A SCENARIO_TO_VAR=(
        ["acr5l50mb"]="REGISTRY_ACR_5L_50MB"
        ["acr5l100mb"]="REGISTRY_ACR_5L_100MB"
        ["acr5l300mb"]="REGISTRY_ACR_5L_300MB"
        ["acr5l1gb"]="REGISTRY_ACR_5L_1GB"
        ["acr5l2gb"]="REGISTRY_ACR_5L_2GB"
        ["acr20l50mb"]="REGISTRY_ACR_20L_50MB"
        ["acr20l100mb"]="REGISTRY_ACR_20L_100MB"
        ["acr20l300mb"]="REGISTRY_ACR_20L_300MB"
        ["acr20l1gb"]="REGISTRY_ACR_20L_1GB"
        ["acr20l2gb"]="REGISTRY_ACR_20L_2GB"
        ["acr50l50mb"]="REGISTRY_ACR_50L_50MB"
        ["acr50l100mb"]="REGISTRY_ACR_50L_100MB"
        ["acr50l300mb"]="REGISTRY_ACR_50L_300MB"
        ["acr50l1gb"]="REGISTRY_ACR_50L_1GB"
        ["acr50l2gb"]="REGISTRY_ACR_50L_2GB"
    )
    
    for scenario in "${SCENARIOS[@]}"; do
        local var_name="${SCENARIO_TO_VAR[$scenario]}"
        local registry_uri
        
        if [ "$DRY_RUN" == "true" ]; then
            registry_uri="${scenario}.azurecr-test.io"
        else
            registry_uri=$(az acr show --name "$scenario" --query loginServer --output tsv 2>/dev/null || echo "${scenario}.azurecr-test.io")
        fi
        
        echo "export $var_name=\"$registry_uri\""
    done
    
    echo ""
    echo "# Docker credentials (use admin credentials or service principal)"
    echo "export DOCKER_USERNAME=\"\""
    echo "export DOCKER_PASSWORD=\"\""
    echo ""
    echo "# To get admin credentials for a registry:"
    echo "# az acr credential show --name REGISTRY_NAME --query passwords[0].value --output tsv"
}

function cleanup_registries() {
    log_info "Cleaning up all validation scenario registries..."
    
    local failed_deletions=()
    
    for scenario in "${SCENARIOS[@]}"; do
        log_info "Deleting registry: $scenario"
        
        if [ "$DRY_RUN" == "true" ]; then
            log_info "[DRY RUN] Would delete registry: $scenario"
            continue
        fi
        
        if az acr delete \
            --name "$scenario" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null; then
            log_success "Deleted registry: $scenario"
        else
            log_warning "Failed to delete registry: $scenario (may not exist)"
            failed_deletions+=("$scenario")
        fi
    done
    
    if [ ${#failed_deletions[@]} -eq 0 ]; then
        log_success "All registries cleaned up successfully!"
    else
        log_warning "Some registries could not be deleted: ${failed_deletions[*]}"
    fi
}

function check_existing_registries() {
    log_info "Checking existing registries..."
    
    echo ""
    printf "%-20s %-15s %-30s\n" "REGISTRY" "STATUS" "LOGIN SERVER"
    printf "%-20s %-15s %-30s\n" "--------" "------" "------------"
    
    local existing_count=0
    local missing_count=0
    
    for scenario in "${SCENARIOS[@]}"; do
        local login_server
        login_server=$(az acr show --name "$scenario" --query loginServer --output tsv 2>/dev/null || echo "")
        
        if [ -n "$login_server" ]; then
            printf "%-20s %-15s %-30s\n" "$scenario" "EXISTS" "$login_server"
            existing_count=$((existing_count + 1))
        else
            printf "%-20s %-15s %-30s\n" "$scenario" "MISSING" "N/A"
            missing_count=$((missing_count + 1))
        fi
    done
    
    echo ""
    log_info "Summary: $existing_count existing, $missing_count missing"
    return $missing_count
}

function create_missing_registries() {
    log_info "Creating only missing registries..."
    
    local missing_registries=()
    
    # Check which registries are missing
    for scenario in "${SCENARIOS[@]}"; do
        if ! az acr show --name "$scenario" &> /dev/null; then
            missing_registries+=("$scenario")
        fi
    done
    
    if [ ${#missing_registries[@]} -eq 0 ]; then
        log_success "All registries already exist!"
        return 0
    fi
    
    log_info "Found ${#missing_registries[@]} missing registries: ${missing_registries[*]}"
    
    local failed_registries=()
    
    for scenario in "${missing_registries[@]}"; do
        if ! create_registry "$scenario"; then
            failed_registries+=("$scenario")
        fi
    done
    
    if [ ${#failed_registries[@]} -eq 0 ]; then
        log_success "All missing registries created successfully!"
    else
        log_error "Failed to create ${#failed_registries[@]} registries: ${failed_registries[*]}"
        return 1
    fi
}

function show_credentials() {
    log_info "Showing admin credentials for existing registries..."
    
    echo ""
    printf "%-20s %-20s %-40s\n" "REGISTRY" "USERNAME" "PASSWORD"
    printf "%-20s %-20s %-40s\n" "--------" "--------" "--------"
    
    for scenario in "${SCENARIOS[@]}"; do
        if az acr show --name "$scenario" &> /dev/null; then
            local username
            local password
            username=$(az acr credential show --name "$scenario" --query username --output tsv 2>/dev/null || echo "N/A")
            password=$(az acr credential show --name "$scenario" --query passwords[0].value --output tsv 2>/dev/null || echo "N/A")
            
            printf "%-20s %-20s %-40s\n" "$scenario" "$username" "$password"
        else
            printf "%-20s %-20s %-40s\n" "$scenario" "NOT FOUND" "N/A"
        fi
    done
    
    echo ""
    log_info "Use these credentials in your config.env file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        --sku)
            SKU="$2"
            shift 2
            ;;
        --admin-enabled)
            ADMIN_ENABLED="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        --generate-config)
            generate_config
            exit 0
            ;;
        --cleanup)
            check_prerequisites
            cleanup_registries
            exit 0
            ;;
        --check-existing)
            check_prerequisites
            check_existing_registries
            exit 0
            ;;
        --create-missing-only)
            check_prerequisites
            create_missing_registries
            exit 0
            ;;
        --show-credentials)
            check_prerequisites
            show_credentials
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
log_info "Azure Container Registry Creation for Validation Scenarios"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Subscription: $SUBSCRIPTION"
log_info "Location: $LOCATION"
log_info "SKU: $SKU"
log_info "Admin Enabled: $ADMIN_ENABLED"

if [ "$DRY_RUN" == "true" ]; then
    log_info "DRY RUN MODE - No resources will be created"
fi

check_prerequisites
create_all_registries

log_info "Registry creation completed!"
log_info "Run '$0 --generate-config' to generate configuration entries"
