#!/bin/bash

# Script to apply ArgoCD Applications
# This creates the ArgoCD Application resources that will manage the deployments

set -e

echo "=========================================="
echo "Applying ArgoCD Applications"
echo "=========================================="
echo ""

# Check if logged into OpenShift
if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

echo "✅ Logged in as: $(oc whoami)"
echo ""

# Check if openshift-gitops namespace exists
if ! oc get namespace openshift-gitops &> /dev/null; then
    echo "❌ Error: openshift-gitops namespace not found."
    echo "Please run setup-argocd.sh first."
    exit 1
fi

# Navigate to script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ARGOCD_APPS_DIR="$SCRIPT_DIR/../argocd-apps"

# Check if ArgoCD app files exist
if [ ! -d "$ARGOCD_APPS_DIR" ]; then
    echo "❌ Error: argocd-apps directory not found at $ARGOCD_APPS_DIR"
    exit 1
fi

# Apply dev application
echo "Applying dev application..."
if [ -f "$ARGOCD_APPS_DIR/dev-application.yaml" ]; then
    if oc get application.argoproj.io llmops-dev -n openshift-gitops &> /dev/null; then
        echo "  ℹ️  Application 'llmops-dev' already exists, updating..."
        oc apply -f "$ARGOCD_APPS_DIR/dev-application.yaml"
        echo "  ✅ Dev application updated"
    else
        oc apply -f "$ARGOCD_APPS_DIR/dev-application.yaml"
        echo "  ✅ Dev application created"
    fi
else
    echo "❌ Error: dev-application.yaml not found"
    exit 1
fi
echo ""

# Apply staging application
echo "Applying staging application..."
if [ -f "$ARGOCD_APPS_DIR/staging-application.yaml" ]; then
    if oc get application.argoproj.io llmops-staging -n openshift-gitops &> /dev/null; then
        echo "  ℹ️  Application 'llmops-staging' already exists, updating..."
        oc apply -f "$ARGOCD_APPS_DIR/staging-application.yaml"
        echo "  ✅ Staging application updated"
    else
        oc apply -f "$ARGOCD_APPS_DIR/staging-application.yaml"
        echo "  ✅ Staging application created"
    fi
else
    echo "❌ Error: staging-application.yaml not found"
    exit 1
fi
echo ""

# Apply production application
echo "Applying production application..."
if [ -f "$ARGOCD_APPS_DIR/production-application.yaml" ]; then
    if oc get application.argoproj.io llmops-production -n openshift-gitops &> /dev/null; then
        echo "  ℹ️  Application 'llmops-production' already exists, updating..."
        oc apply -f "$ARGOCD_APPS_DIR/production-application.yaml"
        echo "  ✅ Production application updated"
    else
        oc apply -f "$ARGOCD_APPS_DIR/production-application.yaml"
        echo "  ✅ Production application created"
    fi
else
    echo "❌ Error: production-application.yaml not found"
    exit 1
fi
echo ""

# Show created applications
echo "=========================================="
echo "ArgoCD Applications Status"
echo "=========================================="
echo ""
oc get applications.argoproj.io -n openshift-gitops
echo ""

# Get ArgoCD route
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')

echo "=========================================="
echo "Success!"
echo "=========================================="
echo ""
echo "✅ All ArgoCD Applications have been created"
echo ""
echo "🌐 View in ArgoCD UI:"
echo "   https://$ARGOCD_ROUTE"
echo ""
echo "📊 Monitor sync status:"
echo "   oc get applications.argoproj.io -n openshift-gitops -w"
echo ""
echo "🔄 Dev environment will auto-sync when you push changes to Git"
echo "🔄 Staging and Production require manual sync via ArgoCD UI or CLI"
echo ""

