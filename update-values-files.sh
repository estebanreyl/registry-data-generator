#!/bin/bash

# Script to update all values files to use generic repo paths
# Since each scenario will be in its own registry

SCENARIOS=(
    "acr-5l-50mb" "acr-5l-100mb" "acr-5l-300mb" "acr-5l-1gb" "acr-5l-2gb"
    "acr-20l-50mb" "acr-20l-100mb" "acr-20l-300mb" "acr-20l-1gb" "acr-20l-2gb"
    "acr-50l-50mb" "acr-50l-100mb" "acr-50l-300mb" "acr-50l-1gb" "acr-50l-2gb"
)

for scenario in "${SCENARIOS[@]}"; do
    values_file="registry-data-generator/values-${scenario}.yaml"
    if [ -f "$values_file" ]; then
        echo "Updating $values_file..."
        sed -i "s|repoPath: $scenario|repoPath: docker-auto|g" "$values_file"
        sed -i "s|repoPath: acr-.*|repoPath: docker-auto|g" "$values_file"
    fi
done

echo "Updated all values files to use generic repository paths."
