#!/bin/bash

# Registry Credentials Generator Script
# This script generates admin passwords for all dogfood ACR registries
# and creates a complete configuration file

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

# Registry configurations
declare -A REGISTRY_CONFIGS=(
    ["acr5l50mb"]="5_layers_50MB"
    ["acr5l100mb"]="5_layers_100MB"
    ["acr5l300mb"]="5_layers_300MB"
    ["acr5l1gb"]="5_layers_1GB"
    ["acr5l2gb"]="5_layers_2GB"
    ["acr20l50mb"]="20_layers_50MB"
    ["acr20l100mb"]="20_layers_100MB"
    ["acr20l300mb"]="20_layers_300MB"
    ["acr20l1gb"]="20_layers_1GB"
    ["acr20l2gb"]="20_layers_2GB"
    ["acr50l50mb"]="50_layers_50MB"
    ["acr50l100mb"]="50_layers_100MB"
    ["acr50l300mb"]="50_layers_300MB"
    ["acr50l1gb"]="50_layers_1GB"
    ["acr50l2gb"]="50_layers_2GB"
)

# Configuration
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
AZURE_LOCATION="${AZURE_LOCATION:-centralus}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-conversion-validation-cluster}"
NAMESPACE="${NAMESPACE:-registry-data-generator}"
OUTPUT_FILE="${OUTPUT_FILE:-config.env}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_REGENERATE="${FORCE_REGENERATE:-false}"

function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Generate admin credentials for all dogfood ACR registries"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -g, --resource-group NAME  Azure resource group name"
    echo "  -s, --subscription ID      Azure subscription ID"
    echo "  -o, --output FILE          Output configuration file (default: config.env)"
    echo "  -d, --dry-run              Show what would be generated without creating"
    echo "  -f, --force                Force regenerate all passwords"
    echo "  --verify-only              Only verify existing credentials"
    echo "  --show-passwords           Display generated passwords (insecure)"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_SUBSCRIPTION_ID      Azure subscription ID"
    echo "  AZURE_RESOURCE_GROUP        Azure resource group name"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-rg -s my-sub-id"
    echo "  $0 --output my-config.env"
    echo "  $0 --verify-only"
    echo "  $0 --force --show-passwords"
}

function check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Skip Azure validation in dry-run mode
    if [ "$DRY_RUN" == "true" ]; then
        log_info "Dry-run mode: Skipping Azure authentication and resource validation"
        return 0
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first"
        exit 1
    fi
    
    # Check required parameters
    if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        log_error "Azure subscription ID not specified. Use -s or set AZURE_SUBSCRIPTION_ID"
        exit 1
    fi
    
    if [ -z "$AZURE_RESOURCE_GROUP" ]; then
        log_error "Resource group not specified. Use -g or set AZURE_RESOURCE_GROUP"
        exit 1
    fi
    
    # Set subscription
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    
    # Check if resource group exists
    if ! az group show --name "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$AZURE_RESOURCE_GROUP' not found"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

function enable_registry_admin() {
    local registry_name=$1
    
    log_info "Enabling admin access for registry: $registry_name"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would enable admin for registry: $registry_name"
        return 0
    fi
    
    # Check if registry exists
    if ! az acr show --name "$registry_name" --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        log_error "Registry '$registry_name' not found"
        return 1
    fi
    
    # Enable admin user
    if az acr update --name "$registry_name" --resource-group "$AZURE_RESOURCE_GROUP" --admin-enabled true --output none; then
        log_success "Admin enabled for registry: $registry_name"
        return 0
    else
        log_error "Failed to enable admin for registry: $registry_name"
        return 1
    fi
}

function get_registry_credentials() {
    local registry_name=$1
    
    if [ "$DRY_RUN" == "true" ]; then
        echo "DRY_RUN_USERNAME	DRY_RUN_PASSWORD"
        return 0
    fi
    
    # Get admin credentials - use registry name as username and get password separately
    local password
    password=$(az acr credential show --name "$registry_name" --resource-group "$AZURE_RESOURCE_GROUP" --query "[passwords[0].value]" --output tsv 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$password" ]; then
        # Debug output to stderr so it doesn't interfere with the return value
        log_info "Retrieved password for $registry_name: length ${#password} characters" >&2
        # Return tab-separated username and password
        echo -e "$registry_name\t$password"
        return 0
    else
        log_error "Failed to get password for registry: $registry_name (exit code: $exit_code)" >&2
        if [ -n "$password" ]; then
            log_error "Error output: $password" >&2
        fi
        return 1
    fi
}

function generate_config_file() {
    local config_file=$1
    local show_passwords=${2:-false}
    
    log_info "Generating configuration file: $config_file"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would generate config file: $config_file"
        return 0
    fi
    
    # Generate configuration file
    cat > "$config_file" << EOF
# Registry Data Generator Configuration
# Generated automatically - DO NOT EDIT MANUALLY
# Use ./generate-registry-credentials.sh to regenerate

# Azure Configuration
export AZURE_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
export AZURE_RESOURCE_GROUP="$AZURE_RESOURCE_GROUP"
export AZURE_LOCATION="$AZURE_LOCATION"

# AKS Cluster Configuration
export AKS_CLUSTER_NAME="$AKS_CLUSTER_NAME"
export AKS_NODE_COUNT="5"
export AKS_NODE_VM_SIZE="Standard_D4s_v3"
export AKS_NODE_DISK_SIZE="100"

# Kubernetes Configuration
export NAMESPACE="$NAMESPACE"

# Deployment Configuration
export PARALLEL_DEPLOYMENTS="3"
export DRY_RUN="false"

# Registry URIs and Credentials (Dogfood Environment)
# Each registry uses admin credentials for authentication
EOF
    
    # Add registry configurations
    local failed_registries=()
    
    for registry_name in "${!REGISTRY_CONFIGS[@]}"; do
        local description="${REGISTRY_CONFIGS[$registry_name]}"
        
        log_info "Processing registry: $registry_name ($description)"
        
        # Enable admin access
        if ! enable_registry_admin "$registry_name"; then
            failed_registries+=("$registry_name")
            continue
        fi
        
        # Get credentials
        local credentials
        credentials=$(get_registry_credentials "$registry_name")
        
        if [ $? -eq 0 ] && [ -n "$credentials" ]; then
            # Parse tab-separated values with improved handling
            local username password
            
            # Method 1: Use read with IFS to handle tab separation
            if IFS=$'\t' read -r username password <<< "$credentials"; then
                # Trim whitespace
                username=$(echo "$username" | xargs)
                password=$(echo "$password" | xargs)
                
                # Validate that we got both username and password
                if [ -z "$username" ] || [ -z "$password" ]; then
                    log_error "Invalid credentials format for registry: $registry_name"
                    log_error "Expected: username<tab>password, got: '$credentials'"
                    log_error "Parsed - Username: '$username', Password: '$password'"
                    failed_registries+=("$registry_name")
                    continue
                fi
            else
                log_error "Failed to parse credentials for registry: $registry_name"
                log_error "Raw credentials: '$credentials'"
                failed_registries+=("$registry_name")
                continue
            fi
            
            # Add to config file
            echo "" >> "$config_file"
            echo "# Registry: $registry_name ($description)" >> "$config_file"
            echo "export REGISTRY_$(echo $registry_name | tr '[:lower:]' '[:upper:]')=\"$registry_name.azurecr-test.io\"" >> "$config_file"
            echo "export REGISTRY_$(echo $registry_name | tr '[:lower:]' '[:upper:]')_USERNAME=\"$username\"" >> "$config_file"
            echo "export REGISTRY_$(echo $registry_name | tr '[:lower:]' '[:upper:]')_PASSWORD=\"$password\"" >> "$config_file"
            
            if [ "$show_passwords" == "true" ]; then
                log_info "Registry: $registry_name - Username: '$username' - Password: '$password'"
            else
                log_success "Generated credentials for registry: $registry_name (Username: $username)"
            fi
        else
            failed_registries+=("$registry_name")
        fi
    done
    
    # Add footer
    cat >> "$config_file" << 'EOF'

# Usage Instructions:
# 1. Update AZURE_SUBSCRIPTION_ID and AZURE_RESOURCE_GROUP above
# 2. Source this file: source config.env
# 3. Verify setup: ./verify-setup.sh
# 4. Create AKS cluster: ./create-aks-cluster.sh
# 5. Deploy scenarios: ./deploy-generation-scenarios.sh

# Security Note:
# This file contains sensitive credentials. Keep it secure and don't commit to version control.
EOF
    
    # Report results
    if [ ${#failed_registries[@]} -eq 0 ]; then
        log_success "Successfully generated credentials for all registries!"
        log_info "Configuration saved to: $config_file"
    else
        log_error "Failed to generate credentials for ${#failed_registries[@]} registries: ${failed_registries[*]}"
        return 1
    fi
}

function verify_credentials() {
    local config_file=$1
    
    log_info "Verifying existing credentials..."
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Source the config file
    source "$config_file"
    
    local failed_verifications=()
    
    for registry_name in "${!REGISTRY_CONFIGS[@]}"; do
        local registry_var="REGISTRY_$(echo $registry_name | tr '[:lower:]' '[:upper:]')"
        local username_var="${registry_var}_USERNAME"
        local password_var="${registry_var}_PASSWORD"
        
        local registry_uri="${!registry_var}"
        local username="${!username_var}"
        local password="${!password_var}"
        
        if [ -n "$registry_uri" ] && [ -n "$username" ] && [ -n "$password" ]; then
            log_info "Verifying registry: $registry_name"
            
            # Test docker login
            if echo "$password" | docker login "$registry_uri" --username "$username" --password-stdin &> /dev/null; then
                log_success "Credentials verified for registry: $registry_name"
                docker logout "$registry_uri" &> /dev/null
            else
                log_error "Failed to verify credentials for registry: $registry_name"
                failed_verifications+=("$registry_name")
            fi
        else
            log_warning "Missing credentials for registry: $registry_name"
            failed_verifications+=("$registry_name")
        fi
    done
    
    if [ ${#failed_verifications[@]} -eq 0 ]; then
        log_success "All credentials verified successfully!"
        return 0
    else
        log_error "Failed to verify ${#failed_verifications[@]} registries: ${failed_verifications[*]}"
        return 1
    fi
}

function show_credential_summary() {
    local config_file=$1
    
    log_info "Credential Summary"
    log_info "=================="
    
    echo ""
    echo "Configuration file: $config_file"
    echo "Registry count: ${#REGISTRY_CONFIGS[@]}"
    echo "Registry endpoint: .azurecr-test.io (dogfood)"
    echo "Authentication: Admin credentials"
    echo ""
    echo "Registries configured:"
    for registry_name in "${!REGISTRY_CONFIGS[@]}"; do
        local description="${REGISTRY_CONFIGS[$registry_name]}"
        echo "  - $registry_name ($description)"
    done
    echo ""
    echo "Next steps:"
    echo "1. Edit $config_file to set AZURE_SUBSCRIPTION_ID and AZURE_RESOURCE_GROUP"
    echo "2. Source the config: source $config_file"
    echo "3. Create AKS cluster: ./create-aks-cluster.sh"
    echo "4. Deploy scenarios: ./deploy-generation-scenarios.sh"
}

# Parse command line arguments
VERIFY_ONLY=false
SHOW_PASSWORDS=false

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
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -f|--force)
            FORCE_REGENERATE="true"
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --show-passwords)
            SHOW_PASSWORDS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
log_info "Registry Credentials Generator"
log_info "=============================="

if [ "$VERIFY_ONLY" == "true" ]; then
    verify_credentials "$OUTPUT_FILE"
    exit $?
fi

check_prerequisites

if [ "$DRY_RUN" == "true" ]; then
    log_info "DRY RUN MODE - No changes will be made"
fi

# Generate configuration file
generate_config_file "$OUTPUT_FILE" "$SHOW_PASSWORDS"

# Show summary
show_credential_summary "$OUTPUT_FILE"

log_success "Credential generation completed!"
log_warning "Remember to keep the configuration file secure - it contains sensitive credentials"
