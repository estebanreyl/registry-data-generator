#!/bin/bash

# Registry Name Mapping for Azure Container Registry Validation Scenarios
# This shows the mapping between scenario names and valid ACR registry names

echo "Registry Name Mapping for Validation Scenarios"
echo "=============================================="
echo ""
echo "Azure Container Registry names cannot contain dashes, so we use the following mapping:"
echo ""
printf "%-20s %-25s %-35s\n" "SCENARIO" "ACR NAME" "FULL URI"
printf "%-20s %-25s %-35s\n" "--------" "--------" "--------"

declare -A SCENARIO_TO_REGISTRY=(
    ["acr-5l-50mb"]="acr5l50mb"
    ["acr-5l-100mb"]="acr5l100mb"
    ["acr-5l-300mb"]="acr5l300mb"
    ["acr-5l-1gb"]="acr5l1gb"
    ["acr-5l-2gb"]="acr5l2gb"
    ["acr-20l-50mb"]="acr20l50mb"
    ["acr-20l-100mb"]="acr20l100mb"
    ["acr-20l-300mb"]="acr20l300mb"
    ["acr-20l-1gb"]="acr20l1gb"
    ["acr-20l-2gb"]="acr20l2gb"
    ["acr-50l-50mb"]="acr50l50mb"
    ["acr-50l-100mb"]="acr50l100mb"
    ["acr-50l-300mb"]="acr50l300mb"
    ["acr-50l-1gb"]="acr50l1gb"
    ["acr-50l-2gb"]="acr50l2gb"
)

for scenario in "${!SCENARIO_TO_REGISTRY[@]}"; do
    registry_name="${SCENARIO_TO_REGISTRY[$scenario]}"
    full_uri="${registry_name}.azurecr-test.io"
    printf "%-20s %-25s %-35s\n" "$scenario" "$registry_name" "$full_uri"
done | sort

echo ""
echo "Notes:"
echo "- Registry names use only alphanumeric characters (no dashes)"
echo "- Using dogfood endpoint: .azurecr-test.io"
echo "- Each scenario deploys to its own dedicated registry"
echo ""
echo "Environment Variables:"
echo "- REGISTRY_ACR_5L_50MB=\"acr5l50mb.azurecr-test.io\""
echo "- REGISTRY_ACR_5L_100MB=\"acr5l100mb.azurecr-test.io\""
echo "- REGISTRY_ACR_5L_300MB=\"acr5l300mb.azurecr-test.io\""
echo "- ... and so on for all scenarios"
