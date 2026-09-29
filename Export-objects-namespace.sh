#
# Exports every object (of every resource type) in a given Kubernetes
# namespace to individual YAML files, organized by resource type.
#
# Usage:
#   ./export-namespace.sh <namespace> [output-dir]
#
# Example:
#   ./export-namespace.sh my-app
#   ./export-namespace.sh my-app ./backups/my-app-2026-06-16
#
# Requires: kubectl, configured and pointed at the right cluster/context.

set -euo pipefail

NAMESPACE="${1:?Usage: $0 <namespace> [output-dir]}"
OUTDIR="${2:-./k8s-export-${NAMESPACE}}"

mkdir -p "$OUTDIR"

echo "Exporting all objects in namespace '${NAMESPACE}' to '${OUTDIR}'..."
echo

# Get every namespaced resource type the API server exposes that supports 'list'.
# This covers built-ins (pods, deployments, services, configmaps, secrets, etc.)
# AND any CRDs installed in the cluster.
RESOURCE_TYPES=$(kubectl api-resources --namespaced=true --verbs=list -o name 2>/dev/null)

TOTAL=0

for resource in $RESOURCE_TYPES; do
  # List object names of this type in the namespace. Skip resource types
  # that error out (e.g. due to RBAC restrictions) instead of aborting.
  names=$(kubectl get "$resource" -n "$NAMESPACE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null) || continue

  [ -z "$names" ] && continue

  mkdir -p "$OUTDIR/$resource"

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    echo "  -> ${resource}/${name}"
    kubectl get "$resource" "$name" -n "$NAMESPACE" -o yaml \
      > "$OUTDIR/$resource/${name}.yaml" 2>/dev/null
    TOTAL=$((TOTAL + 1))
  done <<< "$names"
done

echo
echo "Done. Exported ${TOTAL} object(s) under: ${OUTDIR}"
echo
echo "Note: this includes Secrets in plaintext-decoded-base64 form (as kubectl"
echo "stores them) — handle the output directory accordingly if it contains any."
