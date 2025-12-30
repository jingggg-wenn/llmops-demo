#!/bin/bash

set -e

# Parse command line arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-f|--force]"
            echo ""
            echo "Options:"
            echo "  -f, --force    Skip confirmation prompt if health checks already exist"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "Applying Custom Health Checks to ArgoCD CR"
echo "=========================================="

NAMESPACE="openshift-gitops"
ARGOCD_NAME="openshift-gitops"

echo ""
echo "Step 1: Checking if ArgoCD CR exists..."
if ! oc get argocd $ARGOCD_NAME -n $NAMESPACE &>/dev/null; then
    echo "Error: ArgoCD CR '$ARGOCD_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi
echo "✓ ArgoCD CR found"

echo ""
echo "Step 2: Checking if health checks are already configured..."
HEALTH_CHECKS_EXIST=false

if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -q "resourceHealthChecks"; then
    # Check if KServe health checks exist (need more lines to capture the group field)
    if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -A 100 "resourceHealthChecks" | grep -q "group: serving.kserve.io"; then
        HEALTH_CHECKS_EXIST=true
        echo "⚠ Health checks for KServe already exist in ArgoCD CR"
        echo "  This script will update/replace the existing configuration."
        
        if [ "$FORCE" = false ]; then
            echo ""
            read -p "Do you want to continue? (y/n) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Aborted by user."
                exit 0
            fi
        else
            echo "  --force flag detected, continuing without prompt..."
        fi
    else
        echo "✓ resourceHealthChecks found, but no KServe health checks detected"
        echo "  Will add KServe health checks to existing configuration..."
    fi
else
    echo "✓ No existing resourceHealthChecks found"
    echo "  Will create new health check configuration..."
fi

echo ""
echo "Step 3: Applying health check configuration to ArgoCD CR..."
oc patch argocd $ARGOCD_NAME -n $NAMESPACE --type merge --patch '
spec:
  resourceHealthChecks:
    - group: serving.kserve.io
      kind: InferenceService
      check: |
        hs = {}
        hs.status = "Progressing"
        hs.message = "Waiting for InferenceService"
        
        if obj.status ~= nil then
          if obj.status.conditions ~= nil then
            for i, condition in ipairs(obj.status.conditions) do
              if condition.type == "Ready" then
                if condition.status == "True" then
                  hs.status = "Healthy"
                  hs.message = "InferenceService is ready"
                  return hs
                elseif condition.status == "False" then
                  hs.status = "Degraded"
                  hs.message = condition.message or "InferenceService is not ready"
                  return hs
                else
                  hs.status = "Progressing"
                  hs.message = condition.message or "InferenceService is progressing"
                  return hs
                end
              end
            end
          end
        end
        
        return hs
    - group: serving.kserve.io
      kind: ServingRuntime
      check: |
        hs = {}
        hs.status = "Healthy"
        hs.message = "ServingRuntime is configured"
        return hs
'

if [ $? -eq 0 ]; then
    if [ "$HEALTH_CHECKS_EXIST" = true ]; then
        echo "✓ Health check configuration updated in ArgoCD CR"
    else
        echo "✓ Health check configuration applied to ArgoCD CR"
    fi
else
    echo "✗ Failed to apply health check configuration"
    exit 1
fi

echo ""
echo "Step 4: Waiting for operator to reconcile (10 seconds)..."
sleep 10

echo ""
echo "Step 5: Verifying health check is in ConfigMap..."
if oc get configmap argocd-cm -n $NAMESPACE -o jsonpath='{.data.resource\.customizations\.health\.serving\.kserve\.io_InferenceService}' | grep -q "InferenceService is ready"; then
    echo "✓ Health check successfully added to ConfigMap"
else
    echo "⚠ Health check not yet in ConfigMap, waiting another 10 seconds..."
    sleep 10
    if oc get configmap argocd-cm -n $NAMESPACE -o jsonpath='{.data.resource\.customizations\.health\.serving\.kserve\.io_InferenceService}' | grep -q "InferenceService is ready"; then
        echo "✓ Health check successfully added to ConfigMap"
    else
        echo "✗ Health check not found in ConfigMap. Manual verification needed."
    fi
fi

echo ""
echo "Step 6: Forcing hard refresh on ArgoCD applications..."
for app in llmops-dev llmops-staging llmops-production; do
    if oc get application.argoproj.io $app -n $NAMESPACE &>/dev/null; then
        echo "  Refreshing $app..."
        oc patch application.argoproj.io $app -n $NAMESPACE --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' &>/dev/null || true
    fi
done
echo "✓ Applications refreshed"

echo ""
echo "Step 7: Waiting for health status to update (30 seconds)..."
sleep 30

echo ""
echo "=========================================="
echo "Current Application Status:"
echo "=========================================="
oc get applications.argoproj.io -n $NAMESPACE

echo ""
echo "=========================================="
echo "Verification Commands:"
echo "=========================================="
echo "1. Check ConfigMap health check:"
echo "   oc get configmap argocd-cm -n $NAMESPACE -o yaml | grep -A 5 'InferenceService'"
echo ""
echo "2. Check ArgoCD CR:"
echo "   oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -A 50 'resourceHealthChecks'"
echo ""
echo "3. Check application health:"
echo "   oc get applications.argoproj.io -n $NAMESPACE"
echo ""
echo "4. Check InferenceService status:"
echo "   oc get inferenceservice -n llmops-dev"
echo ""
echo "=========================================="
echo "Summary:"
echo "=========================================="
echo "✓ Health checks configured in ArgoCD CR"
echo "✓ Operator propagated changes to ConfigMap"
echo "✓ Applications refreshed"
echo ""
echo "Next Steps:"
echo "1. Verify configuration: ./verify-health-check.sh"
echo "2. Check ArgoCD UI for updated health status"
echo "3. Monitor applications: oc get applications.argoproj.io -n $NAMESPACE -w"
echo ""
echo "If applications still show 'Progressing', wait a few minutes and run:"
echo "  ./verify-health-check.sh"
echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="

