#!/usr/bin/env bash

set -euo pipefail

echo "Getting changes"
CHANGED_FILES=$(git diff --name-only origin/main...HEAD -- '*.yaml' '*.yml')

if [ -z "$CHANGED_FILES" ]; then
  echo "No changes"
  exit 0
fi

for file in $CHANGED_FILES; do
  if [ ! -f "$file" ]; then
    echo "Skipped deleted file: $file"  # Skip deleted files
    continue
  fi

  if grep -q 'kind: HelmRelease' "$file"; then
    echo "Detected HelmRelease"

    name=$(yq e '.metadata.name' "$file")
    chart=$(yq e '.spec.chart.spec.chart' "$file")
    version=$(yq e '.spec.chart.spec.version' "$file")
    repo=$(yq e '.spec.chart.spec.sourceRef.name' "$file")
    namespace=$(yq e '.spec.targetNamespace // "default"' "$file")
    values_file="$(dirname "$file")/values.yaml"

    if ! helm template "$release_name" "$chart" \
      --version "$version" \
      --namespace "$namespace" \
      ${values_file:+--values "$values_file"} > /tmp/rendered.yaml; then
      echo "helm template failed $file"
      exit 1
    fi

    kubeconform -strict -ignore-missing-schemas -summary -output text /tmp/rendered.yaml

  else
    echo "Checking raw k8 YAMLs"
    kubeconform -strict -ignore-missing-schemas -summary -output text "$file"
  fi
done
