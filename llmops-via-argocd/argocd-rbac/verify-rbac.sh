#!/bin/bash

set -e

echo "=========================================="
echo "Verifying ArgoCD RBAC Configuration"
echo "=========================================="

NAMESPACE="openshift-gitops"
ARGOCD_NAME="openshift-gitops"
CURRENT_USER=$(oc whoami)

echo ""
echo "Step 1: Checking if RBAC is in ArgoCD CR..."
if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -q "rbac:"; then
    echo "✓ RBAC configuration found in ArgoCD CR"
    
    if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -A 50 "rbac:" | grep -q "$CURRENT_USER"; then
        echo "✓ User '$CURRENT_USER' found in RBAC policy"
    else
        echo "✗ User '$CURRENT_USER' NOT found in RBAC policy"
        exit 1
    fi
else
    echo "✗ RBAC configuration NOT found in ArgoCD CR"
    echo ""
    echo "Run the following to apply RBAC:"
    echo "  ./apply-rbac-via-cr.sh"
    exit 1
fi

echo ""
echo "Step 2: Checking if RBAC propagated to ConfigMap..."
if oc get configmap argocd-rbac-cm -n $NAMESPACE -o jsonpath='{.data.policy\.csv}' | grep -q "$CURRENT_USER"; then
    echo "✓ RBAC successfully propagated to ConfigMap"
else
    echo "⚠ RBAC not yet in ConfigMap"
    echo "  The operator may still be reconciling. Wait 10 seconds and try again."
    exit 1
fi

echo ""
echo "Step 3: Checking ArgoCD server status..."
if oc get deployment openshift-gitops-server -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -q "True"; then
    echo "✓ ArgoCD server is running"
else
    echo "✗ ArgoCD server is not ready"
    exit 1
fi

echo ""
echo "Step 4: Current RBAC Policy in ConfigMap..."
echo "---"
oc get configmap argocd-rbac-cm -n $NAMESPACE -o jsonpath='{.data.policy\.csv}'
echo ""
echo "---"

echo ""
echo "Step 5: Default Policy..."
DEFAULT_POLICY=$(oc get configmap argocd-rbac-cm -n $NAMESPACE -o jsonpath='{.data.policy\.default}')
if [ -z "$DEFAULT_POLICY" ]; then
    echo "⚠ Default policy is empty (no default access)"
else
    echo "✓ Default policy: $DEFAULT_POLICY"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "Current User: $CURRENT_USER"
echo "ArgoCD URL: https://$(oc get route openshift-gitops-server -n $NAMESPACE -o jsonpath='{.spec.host}')"
echo ""
echo "Expected Results:"
echo "  - User '$CURRENT_USER' has admin access"
echo "  - All authenticated users have readonly access (default)"
echo "  - Custom roles defined: llmops-admin, llmops-developer, llmops-viewer"
echo ""
echo "To test:"
echo "1. Open ArgoCD URL in browser"
echo "2. Click 'LOG IN VIA OPENSHIFT'"
echo "3. Login with OpenShift credentials"
echo "4. You should see all applications"
echo ""

