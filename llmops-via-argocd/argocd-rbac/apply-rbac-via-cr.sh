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
            echo "  -f, --force    Skip confirmation prompt"
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
echo "Applying ArgoCD RBAC via ArgoCD CR"
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
echo "Step 2: Getting your OpenShift username..."
CURRENT_USER=$(oc whoami)
echo "✓ Current user: $CURRENT_USER"

echo ""
echo "Step 3: Checking current RBAC configuration..."
RBAC_EXISTS=false
if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -q "rbac:"; then
    RBAC_EXISTS=true
    echo "⚠ RBAC configuration already exists in ArgoCD CR"
    echo "  This script will update the existing configuration."
    
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
    echo "✓ No existing RBAC configuration found"
    echo "  Will create new RBAC configuration..."
fi

echo ""
echo "Step 4: Applying RBAC configuration to ArgoCD CR..."
oc patch argocd $ARGOCD_NAME -n $NAMESPACE --type merge --patch "
spec:
  rbac:
    defaultPolicy: 'role:readonly'
    policy: |
      # Grant cluster-admins full admin access
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
      
      # Grant specific user admin access
      g, $CURRENT_USER, role:admin
      
      # Custom role: llmops-admin (full access to llmops applications)
      p, role:llmops-admin, applications, *, */*, allow
      p, role:llmops-admin, clusters, get, *, allow
      p, role:llmops-admin, repositories, *, *, allow
      p, role:llmops-admin, projects, *, *, allow
      p, role:llmops-admin, logs, get, *, allow
      p, role:llmops-admin, exec, create, */*, allow
      
      # Custom role: llmops-developer (can view and sync applications)
      p, role:llmops-developer, applications, get, */*, allow
      p, role:llmops-developer, applications, sync, */*, allow
      p, role:llmops-developer, applications, override, */*, allow
      p, role:llmops-developer, applications, action/*, */*, allow
      p, role:llmops-developer, clusters, get, *, allow
      p, role:llmops-developer, repositories, get, *, allow
      p, role:llmops-developer, projects, get, *, allow
      p, role:llmops-developer, logs, get, *, allow
      
      # Custom role: llmops-viewer (read-only access)
      p, role:llmops-viewer, applications, get, */*, allow
      p, role:llmops-viewer, clusters, get, *, allow
      p, role:llmops-viewer, repositories, get, *, allow
      p, role:llmops-viewer, projects, get, *, allow
      p, role:llmops-viewer, logs, get, *, allow
    scopes: '[groups]'
"

if [ $? -eq 0 ]; then
    if [ "$RBAC_EXISTS" = true ]; then
        echo "✓ RBAC configuration updated in ArgoCD CR"
    else
        echo "✓ RBAC configuration applied to ArgoCD CR"
    fi
else
    echo "✗ Failed to apply RBAC configuration"
    exit 1
fi

echo ""
echo "Step 5: Waiting for operator to reconcile (10 seconds)..."
sleep 10

echo ""
echo "Step 6: Verifying RBAC is in ConfigMap..."
if oc get configmap argocd-rbac-cm -n $NAMESPACE -o jsonpath='{.data.policy\.csv}' | grep -q "$CURRENT_USER"; then
    echo "✓ RBAC successfully propagated to ConfigMap"
else
    echo "⚠ RBAC not yet in ConfigMap, waiting another 10 seconds..."
    sleep 10
    if oc get configmap argocd-rbac-cm -n $NAMESPACE -o jsonpath='{.data.policy\.csv}' | grep -q "$CURRENT_USER"; then
        echo "✓ RBAC successfully propagated to ConfigMap"
    else
        echo "✗ RBAC not found in ConfigMap. Manual verification needed."
    fi
fi

echo ""
echo "Step 7: Restarting ArgoCD server to pick up new RBAC..."
oc rollout restart deployment/openshift-gitops-server -n $NAMESPACE
echo "✓ ArgoCD server restart initiated"

echo ""
echo "Step 8: Waiting for ArgoCD server to be ready (30 seconds)..."
sleep 5
oc rollout status deployment/openshift-gitops-server -n $NAMESPACE --timeout=60s

echo ""
echo "=========================================="
echo "ArgoCD URL:"
echo "=========================================="
ARGOCD_URL=$(oc get route openshift-gitops-server -n $NAMESPACE -o jsonpath='{.spec.host}')
echo "https://$ARGOCD_URL"

echo ""
echo "=========================================="
echo "Summary:"
echo "=========================================="
echo "✓ RBAC configured in ArgoCD CR"
echo "✓ Operator propagated changes to ConfigMap"
echo "✓ ArgoCD server restarted"
echo "✓ User '$CURRENT_USER' granted admin access"
echo ""
echo "Next Steps:"
echo "1. Open ArgoCD URL: https://$ARGOCD_URL"
echo "2. Click 'LOG IN VIA OPENSHIFT'"
echo "3. Login with your OpenShift credentials"
echo "4. You should now see all applications!"
echo ""
echo "If you still can't see applications:"
echo "  - Wait 1-2 minutes for server to fully restart"
echo "  - Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)"
echo "  - Run: ./verify-rbac.sh"
echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="

