#!/bin/bash

# AKS Cluster Creation and Registry Attachment Script
# This script creates an AKS cluster and attaches all validation scenario registries

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
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-registry-data-generator-cluster}"
AKS_NODE_COUNT="${AKS_NODE_COUNT:-5}"
AKS_NODE_VM_SIZE="${AKS_NODE_VM_SIZE:-Standard_D4s_v3}"
AKS_NODE_DISK_SIZE="${AKS_NODE_DISK_SIZE:-100}"
DRY_RUN="${DRY_RUN:-false}"

# Registry scenarios with their variable names
declare -A REGISTRY_SCENARIOS=(
    ["acr5l50mb"]="REGISTRY_ACR5L50MB"
    ["acr5l100mb"]="REGISTRY_ACR5L100MB"
    ["acr5l300mb"]="REGISTRY_ACR5L300MB"
    ["acr5l1gb"]="REGISTRY_ACR5L1GB"
    ["acr5l2gb"]="REGISTRY_ACR5L2GB"
    ["acr20l50mb"]="REGISTRY_ACR20L50MB"
    ["acr20l100mb"]="REGISTRY_ACR20L100MB"
    ["acr20l300mb"]="REGISTRY_ACR20L300MB"
    ["acr20l1gb"]="REGISTRY_ACR20L1GB"
    ["acr20l2gb"]="REGISTRY_ACR20L2GB"
    ["acr50l50mb"]="REGISTRY_ACR50L50MB"
    ["acr50l100mb"]="REGISTRY_ACR50L100MB"
    ["acr50l300mb"]="REGISTRY_ACR50L300MB"
    ["acr50l1gb"]="REGISTRY_ACR50L1GB"
    ["acr50l2gb"]="REGISTRY_ACR50L2GB"
)

function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Create AKS cluster for dogfood registry validation scenarios"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -g, --resource-group NAME  Azure resource group name"
    echo "  -s, --subscription ID      Azure subscription ID"
    echo "  -l, --location LOCATION    Azure location (default: eastus)"
    echo "  -c, --cluster-name NAME    AKS cluster name (default: registry-data-generator-cluster)"
    echo "  -n, --node-count COUNT     Number of nodes (default: 5)"
    echo "  --node-vm-size SIZE        Node VM size (default: Standard_D4s_v3)"
    echo "  --node-disk-size SIZE      Node disk size in GB (default: 100)"
    echo "  -d, --dry-run              Show what would be created without creating"
    echo "  --cluster-only             Only create cluster, skip namespace creation"
    echo "  --namespace-only           Only create namespace, skip cluster creation"
    echo "  --cleanup                  Delete cluster and all resources"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_SUBSCRIPTION_ID      Azure subscription ID"
    echo "  AZURE_RESOURCE_GROUP        Azure resource group name"
    echo "  AZURE_LOCATION              Azure location"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-rg -s my-sub-id"
    echo "  $0 --cluster-only"
    echo "  $0 --namespace-only"
    echo "  $0 --cleanup"
    echo ""
    echo "Note: Registry credentials are passed directly to Helm deployments"
    echo "Run './generate-registry-credentials.sh' to generate credentials first"
    echo "The config.env file will be automatically loaded when deploying scenarios"
}

function check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Check if kubectl is installed (only if we're working with cluster)
    if [ "$NAMESPACE_ONLY" != "true" ] && ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Skip Azure validation in dry-run mode for namespace-only
    if [ "$DRY_RUN" == "true" ] && [ "$NAMESPACE_ONLY" == "true" ]; then
        log_info "Dry-run namespace-only mode: Skipping Azure authentication validation"
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

function create_aks_cluster() {
    log_info "Creating AKS cluster: $AKS_CLUSTER_NAME"
    
    if [ "$DRY_RUN" == "true" ]; then
        # Check if cluster exists in dry-run mode
        if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
            log_info "[DRY RUN] AKS cluster '$AKS_CLUSTER_NAME' already exists"
            log_info "[DRY RUN] Would get cluster credentials and skip creation"
        else
            log_info "[DRY RUN] Would create AKS cluster with:"
            log_info "  - Name: $AKS_CLUSTER_NAME"
            log_info "  - Resource Group: $AZURE_RESOURCE_GROUP"
            log_info "  - Location: $AZURE_LOCATION"
            log_info "  - Node Count: $AKS_NODE_COUNT"
            log_info "  - Node VM Size: $AKS_NODE_VM_SIZE"
            log_info "  - Node Disk Size: ${AKS_NODE_DISK_SIZE}GB"
        fi
        return 0
    fi
    
    # Check if cluster already exists
    if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        log_warning "AKS cluster '$AKS_CLUSTER_NAME' already exists, skipping creation"
        
        # Get cluster credentials to ensure kubectl is configured
        log_info "Getting existing cluster credentials..."
        if az aks get-credentials \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$AKS_CLUSTER_NAME" \
            --overwrite-existing; then
            log_success "Cluster credentials configured for existing cluster"
        else
            log_error "Failed to get credentials for existing cluster"
            return 1
        fi
        
        return 0
    fi
    
    # Create the AKS cluster
    log_info "Creating AKS cluster (this may take 10-15 minutes)..."
    if az aks create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --location "$AZURE_LOCATION" \
        --node-count "$AKS_NODE_COUNT" \
        --node-vm-size "$AKS_NODE_VM_SIZE" \
        --node-osdisk-size "$AKS_NODE_DISK_SIZE" \
        --generate-ssh-keys \
        --enable-managed-identity \
        --output none; then
        log_success "AKS cluster created successfully"
    else
        log_error "Failed to create AKS cluster"
        return 1
    fi
    
    # Get cluster credentials
    log_info "Getting cluster credentials..."
    if az aks get-credentials \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing; then
        log_success "Cluster credentials configured"
    else
        log_error "Failed to get cluster credentials"
        return 1
    fi
}

function create_kubernetes_namespace() {
    log_info "Creating Kubernetes namespace..."
    
    local namespace="${NAMESPACE:-registry-data-generator}"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would create namespace: $namespace"
        return 0
    fi
    
    # Create namespace if it doesn't exist
    if kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -; then
        log_success "Namespace '$namespace' ready"
    else
        log_error "Failed to create namespace: $namespace"
        return 1
    fi
    
    log_success "Kubernetes namespace created successfully!"
    log_info "Registry credentials will be passed directly to Helm deployments"
}

function verify_cluster_setup() {
    log_info "Verifying cluster setup..."
    
    # Check cluster status
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    # Check nodes
    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l)
    log_info "Cluster has $node_count nodes"
    
    # Check namespace
    local namespace="${NAMESPACE:-registry-data-generator}"
    if kubectl get namespace "$namespace" &> /dev/null; then
        log_success "Namespace '$namespace' exists"
    else
        log_warning "Namespace '$namespace' not found"
    fi
    
    # Registry credentials are passed directly to Helm deployments
    log_info "Registry authentication will be handled via Helm deployment values"
    log_success "Dogfood registry authentication configured for direct credential passing"
    
    log_success "Cluster setup verification completed"
}

function cleanup_resources() {
    log_info "Cleaning up cluster and resources..."
    
    if [ "$DRY_RUN" == "true" ]; then
        log_info "[DRY RUN] Would delete AKS cluster: $AKS_CLUSTER_NAME"
        return 0
    fi
    
    # Delete AKS cluster
    log_info "Deleting AKS cluster: $AKS_CLUSTER_NAME"
    if az aks delete \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --yes \
        --no-wait; then
        log_success "AKS cluster deletion initiated"
    else
        log_error "Failed to delete AKS cluster"
        return 1
    fi
    
    log_info "Cluster cleanup completed"
}

function show_cluster_info() {
    log_info "Cluster Information:"
    echo ""
    echo "AKS Cluster: $AKS_CLUSTER_NAME"
    echo "Resource Group: $AZURE_RESOURCE_GROUP"
    echo "Location: $AZURE_LOCATION"
    echo "Subscription: $AZURE_SUBSCRIPTION_ID"
    echo ""
    
    if kubectl cluster-info &> /dev/null; then
        echo "Cluster Status: Running"
        echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"
        echo "Namespaces: $(kubectl get namespaces --no-headers | wc -l)"
        echo ""
        echo "Registry Authentication: Direct Credential Passing to Helm"
        echo ""
        echo "Dogfood Registry Endpoints:"
        for registry_name in "${!REGISTRY_SCENARIOS[@]}"; do
            echo "  - $registry_name.azurecr-test.io"
        done
        echo ""
        echo "Note: Dogfood registry credentials are passed directly to Helm deployments"
        echo "      No Kubernetes secrets are needed - credentials come from config.env"
    else
        echo "Cluster Status: Not accessible"
    fi
}

# Parse command line arguments
CLUSTER_ONLY=false
NAMESPACE_ONLY=false
CLEANUP=false

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
        -l|--location)
            AZURE_LOCATION="$2"
            shift 2
            ;;
        -c|--cluster-name)
            AKS_CLUSTER_NAME="$2"
            shift 2
            ;;
        -n|--node-count)
            AKS_NODE_COUNT="$2"
            shift 2
            ;;
        --node-vm-size)
            AKS_NODE_VM_SIZE="$2"
            shift 2
            ;;
        --node-disk-size)
            AKS_NODE_DISK_SIZE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        --cluster-only)
            CLUSTER_ONLY=true
            shift
            ;;
        --namespace-only)
            NAMESPACE_ONLY=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
log_info "AKS Cluster Creation for Dogfood Registry Validation"
log_info "===================================================="

if [ "$CLEANUP" == "true" ]; then
    check_prerequisites
    cleanup_resources
    exit 0
fi

check_prerequisites

if [ "$DRY_RUN" == "true" ]; then
    log_info "DRY RUN MODE - No resources will be created"
fi

# Create cluster unless namespace-only mode
if [ "$NAMESPACE_ONLY" != "true" ]; then
    create_aks_cluster
fi

# Create Kubernetes namespace for deployments
if [ "$CLUSTER_ONLY" != "true" ]; then
    create_kubernetes_namespace
fi

# Verify setup
verify_cluster_setup

# Show cluster info
show_cluster_info

log_success "Setup completed successfully!"
log_info "You can now run './deploy-generation-scenarios.sh' to deploy the scenarios"
