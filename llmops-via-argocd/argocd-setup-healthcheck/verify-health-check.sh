#!/bin/bash

set -e

echo "=========================================="
echo "Verifying ArgoCD Health Check Configuration"
echo "=========================================="

NAMESPACE="openshift-gitops"
ARGOCD_NAME="openshift-gitops"

echo ""
echo "Step 1: Checking if health check is in ArgoCD CR..."
if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -q "resourceHealthChecks"; then
    echo "✓ resourceHealthChecks found in ArgoCD CR"
    
    if oc get argocd $ARGOCD_NAME -n $NAMESPACE -o yaml | grep -A 20 "resourceHealthChecks" | grep -q "InferenceService"; then
        echo "✓ InferenceService health check found in ArgoCD CR"
    else
        echo "✗ InferenceService health check NOT found in ArgoCD CR"
        exit 1
    fi
else
    echo "✗ resourceHealthChecks NOT found in ArgoCD CR"
    echo ""
    echo "Run the following to apply health checks:"
    echo "  ./apply-health-check-via-cr.sh"
    exit 1
fi

echo ""
echo "Step 2: Checking if health check propagated to ConfigMap..."
if oc get configmap argocd-cm -n $NAMESPACE -o jsonpath='{.data.resource\.customizations\.health\.serving\.kserve\.io_InferenceService}' | grep -q "InferenceService is ready"; then
    echo "✓ Health check successfully propagated to ConfigMap"
else
    echo "⚠ Health check not yet in ConfigMap"
    echo "  The operator may still be reconciling. Wait 10 seconds and try again."
    exit 1
fi

echo ""
echo "Step 3: Checking ArgoCD application health status..."
echo ""
oc get applications.argoproj.io -n $NAMESPACE

echo ""
echo "Step 4: Checking InferenceService status..."
for ns in llmops-dev llmops-staging llmops-prod; do
    if oc get namespace $ns &>/dev/null; then
        echo ""
        echo "Namespace: $ns"
        oc get inferenceservice -n $ns 2>/dev/null || echo "  No InferenceServices found"
    fi
done

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "Expected Results:"
echo "  - ArgoCD CR has resourceHealthChecks"
echo "  - ConfigMap has health check in data field"
echo "  - Applications show 'Healthy' status when InferenceService READY: True"
echo ""
echo "If applications still show 'Progressing', try:"
echo "  oc patch application.argoproj.io llmops-dev -n $NAMESPACE --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}'"
echo "  sleep 30"
echo "  oc get applications.argoproj.io -n $NAMESPACE"
echo ""
