# Conversion Service Validation Workflow

## Overview

The `conversionservice-validation.sh` script provides a complete, automated workflow for testing the conversion service with registry streaming validation scenarios. It orchestrates all the individual scripts and ensures they work together seamlessly.

## Complete Workflow

The script automates the entire validation process:

1. **Create ACR Registries** - Creates 15 dogfood registries for different validation scenarios
2. **Generate Credentials** - Extracts admin credentials for all registries
3. **Setup AKS Cluster** - Creates cluster, configures kubectl, and creates Kubernetes secrets
4. **Deploy Scenarios** - Deploys validation scenarios using Helm charts

## Quick Start

### Full Validation Workflow
```bash
# Set up environment variables
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_RESOURCE_GROUP="your-resource-group"

# Run complete validation workflow
./conversionservice-validation.sh -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"
```

### Check Current Status
```bash
./conversionservice-validation.sh --status
```

### Dry Run (Preview Changes)
```bash
./conversionservice-validation.sh --dry-run -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"
```

### Clean Up All Resources
```bash
./conversionservice-validation.sh --cleanup -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"
```

## Advanced Usage

### Skip Specific Steps
```bash
# Skip registry creation (if registries already exist)
./conversionservice-validation.sh --skip-registries -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"

# Skip credential generation (if config.env already exists)
./conversionservice-validation.sh --skip-credentials -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"

# Only set up cluster and deploy scenarios
./conversionservice-validation.sh --skip-registries --skip-credentials -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"
```

### Custom Configuration
```bash
# Use custom cluster name and location
./conversionservice-validation.sh \
  -g "$AZURE_RESOURCE_GROUP" \
  -s "$AZURE_SUBSCRIPTION_ID" \
  -l "westus2" \
  -c "my-validation-cluster" \
  -n "my-validation-namespace"
```

## Key Features

### 🎯 **Complete Automation**
- End-to-end workflow in a single command
- Automatic dependency checking and prerequisite validation
- Intelligent error handling and recovery guidance

### 🔍 **Status Monitoring**
- Real-time status of all components
- Detailed health checks for registries, cluster, secrets, and deployments
- Clear next steps and troubleshooting guidance

### 🛡️ **Safety Features**
- Dry-run mode to preview all changes
- Skip options for partial workflows
- Comprehensive cleanup functionality
- Prerequisite validation before execution

### 📊 **Comprehensive Logging**
- Color-coded output for easy reading
- Step-by-step progress tracking
- Execution time reporting
- Detailed error messages with resolution steps

## Workflow Details

### Step 1: Create ACR Registries
Creates 15 Azure Container Registries in dogfood environment:
- 5-layer scenarios: `acr5l50mb`, `acr5l100mb`, `acr5l300mb`, `acr5l1gb`, `acr5l2gb`
- 20-layer scenarios: `acr20l50mb`, `acr20l100mb`, `acr20l300mb`, `acr20l1gb`, `acr20l2gb`  
- 50-layer scenarios: `acr50l50mb`, `acr50l100mb`, `acr50l300mb`, `acr50l1gb`, `acr50l2gb`

### Step 2: Generate Credentials
Extracts admin credentials for all registries and creates `config.env` file with:
- Registry endpoints (`.azurecr-test.io`)
- Admin usernames (registry names)
- Admin passwords (from Azure CLI)

### Step 3: Setup AKS Cluster
- Creates AKS cluster in production environment
- Configures kubectl context
- Creates namespace for validation scenarios
- Creates Kubernetes docker-registry secrets for cross-cloud authentication

### Step 4: Deploy Scenarios
- Uses Helm charts from `registry-data-generator/` directory
- Deploys all 15 validation scenarios
- Each scenario generates specific layer/size combinations
- Monitors deployment status and provides feedback

## Integration with Existing Scripts

The validation script integrates seamlessly with existing scripts:

### ✅ **create-acr-registries.sh**
- Automatically called with correct parameters
- Handles both creation and cleanup scenarios
- Supports dry-run mode

### ✅ **generate-registry-credentials.sh** 
- Automatically generates and loads `config.env`
- Handles credential validation and error reporting
- Supports dry-run mode

### ✅ **create-aks-cluster.sh**
- Updated to automatically load `config.env`
- Creates Kubernetes secrets for cross-cloud authentication
- Handles cluster creation and credential configuration

### ✅ **deploy-generation-scenarios.sh**
- Uses credentials from `config.env`
- Deploys all scenarios using Helm charts
- Provides status monitoring and logging

## Monitoring and Troubleshooting

### Monitor Deployments
```bash
# Watch deployment status
kubectl get deployments -n registry-data-generator -w

# View logs from all scenarios
kubectl logs -n registry-data-generator -l app=registry-data-generator --follow

# Check individual scenario
kubectl describe deployment acr-5l-50mb -n registry-data-generator
```

### Common Issues and Solutions

**Issue**: "Registry secrets not found"
```bash
# Solution: Regenerate credentials
./conversionservice-validation.sh --skip-registries --skip-cluster -g "$AZURE_RESOURCE_GROUP" -s "$AZURE_SUBSCRIPTION_ID"
```

**Issue**: "Cluster not accessible"
```bash
# Solution: Reconfigure kubectl
az aks get-credentials --resource-group "$AZURE_RESOURCE_GROUP" --name "conversion-validation-cluster" --overwrite-existing
```

**Issue**: "Deployments failing"
```bash
# Solution: Check registry authentication
kubectl get secrets -n registry-data-generator
kubectl describe secret regcred-acr5l50mb -n registry-data-generator
```

## Best Practices

### 🎯 **Development Workflow**
1. Start with `--dry-run` to preview changes
2. Use `--status` to monitor progress
3. Use skip options for iterative development
4. Clean up resources when testing is complete

### 🔐 **Security**
- The `config.env` file contains sensitive credentials
- Never commit `config.env` to version control
- Use cleanup option to remove resources when done

### ⚡ **Performance**
- The full workflow takes 15-25 minutes
- Use skip options to avoid recreating existing resources
- Monitor resource quotas in your subscription

## Output Example

```
[STEP] Step 1: Creating ACR registries...
[INFO] Executing: ./create-acr-registries.sh -g my-rg -s my-sub-id -l centralus
[SUCCESS] Registry creation completed

[STEP] Step 2: Generating registry credentials...
[INFO] Executing: ./generate-registry-credentials.sh -g my-rg -s my-sub-id
[SUCCESS] Credential generation completed

[STEP] Step 3: Setting up AKS cluster and Kubernetes secrets...
[INFO] Executing: ./create-aks-cluster.sh -g my-rg -s my-sub-id -l centralus -c conversion-validation-cluster
[SUCCESS] Cluster setup completed

[STEP] Step 4: Deploying validation scenarios...
[INFO] Executing: ./deploy-generation-scenarios.sh
[SUCCESS] Scenario deployment completed

[SUCCESS] 🎉 Conversion Service Validation Workflow Completed!
[INFO] Total execution time: 1456 seconds
```

## Next Steps After Completion

1. **Monitor Progress**: Watch deployments and check logs
2. **Validate Results**: Check that test data is being generated in registries
3. **Test Conversion Service**: Use the generated data to test your conversion service
4. **Clean Up**: Use `--cleanup` option when testing is complete

This comprehensive validation script provides everything you need for thorough conversion service testing with minimal manual intervention.
