#!/usr/bin/env bash

set -euo pipefail

echo "Getting changes"
CHANGED_FILES=$(git diff --name-only origin/main...HEAD -- '*.yaml' '*.yml')
echo $CHANGED_FILES

if [ -z "$CHANGED_FILES" ]; then
  echo "No changes"
  exit 0
fi

echo "Adding helm repos"
yq eval 'select(.kind == "HelmRepository") | .metadata.name + " " + .spec.url' \
  infra/finure/common/helm-repositories.yaml | \
  sort -u | \
  grep -vE '^---$' | \
  while read -r name url; do
    helm repo add "$name" "$url"
  done

helm repo update

for file in $CHANGED_FILES; do
  if [ ! -f "$file" ]; then 
    echo "Skipped deleted file: $file" # Skip deleted files
    continue
  fi

  if grep -q 'kind: HelmRelease' "$file"; then
    echo "Detected HelmRelease"

    name=$(yq e '.metadata.name' "$file")
    chart_name=$(yq e '.spec.chart.spec.chart' "$file")
    repo_name=$(yq e '.spec.chart.spec.sourceRef.name' "$file")
    chart="$repo_name/$chart_name"
    version=$(yq e '.spec.chart.spec.version' "$file")
    namespace=$(yq e '.spec.targetNamespace // "default"' "$file")

    if [ "$(yq e '.spec.values // {}' "$file")" != "{}" ]; then
        yq e '.spec.values' "$file" > /tmp/values.yaml

        helm template "$name" "$chart" \
        --version "$version" \
        --namespace "$namespace" \
        --values /tmp/values.yaml > /tmp/rendered.yaml

    else
        helm template "$name" "$chart" \
        --version "$version" \
        --namespace "$namespace" > /tmp/rendered.yaml
    fi

    kubeconform -strict -ignore-missing-schemas -summary -output text /tmp/rendered.yaml

  else
    echo "Checking k8 YAMLs"
    if grep -q 'apiVersion:' "$file" && grep -q 'kind:' "$file"; then
      kubeconform -strict -ignore-missing-schemas -summary -output text "$file"
    else
      echo "Skipping non-Kubernetes YAML: $file"
    fi
  fi
done
