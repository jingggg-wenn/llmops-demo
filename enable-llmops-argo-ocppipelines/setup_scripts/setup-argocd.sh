#!/bin/bash

# Setup script for ArgoCD-based LLMOps
# This script:
# 1. Verifies OpenShift GitOps Operator is installed
# 2. Creates namespaces for dev, staging, and production
# 3. Configures ArgoCD Applications for each environment
# 4. Sets up necessary permissions

set -e

echo "=========================================="
echo "ArgoCD LLMOps Setup Script"
echo "=========================================="
echo ""

# Check if logged into OpenShift
echo "Checking OpenShift login..."
if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

CURRENT_USER=$(oc whoami)
echo "✅ Logged in as: $CURRENT_USER"
echo ""

# Check if OpenShift GitOps Operator is installed
echo "Checking for OpenShift GitOps Operator..."

# Check in both possible locations (4.20 uses openshift-gitops-operator namespace)
OPERATOR_FOUND=false

if oc get subscription openshift-gitops-operator -n openshift-operators &> /dev/null; then
    echo "✅ OpenShift GitOps Operator found in openshift-operators namespace"
    OPERATOR_FOUND=true
elif oc get subscription openshift-gitops-operator -n openshift-gitops-operator &> /dev/null; then
    echo "✅ OpenShift GitOps Operator found in openshift-gitops-operator namespace"
    OPERATOR_FOUND=true
fi

if [ "$OPERATOR_FOUND" = false ]; then
    echo "❌ Error: OpenShift GitOps Operator not found."
    echo ""
    echo "Please install it from OperatorHub:"
    echo "  1. Go to OpenShift Console → Operators → OperatorHub"
    echo "  2. Search for 'Red Hat OpenShift GitOps'"
    echo "  3. Click Install"
    echo "  4. Wait for installation to complete"
    echo "  5. Re-run this script"
    exit 1
fi
echo ""

# Wait for openshift-gitops namespace to be ready
echo "Waiting for openshift-gitops namespace..."
timeout=60
elapsed=0
while ! oc get namespace openshift-gitops &> /dev/null; do
    if [ $elapsed -ge $timeout ]; then
        echo "❌ Error: openshift-gitops namespace not found after ${timeout}s"
        exit 1
    fi
    echo "  Waiting for openshift-gitops namespace to be created..."
    sleep 5
    elapsed=$((elapsed + 5))
done
echo "✅ openshift-gitops namespace exists"
echo ""

# Check ArgoCD Server is running
echo "Checking ArgoCD Server status..."
if ! oc get deployment openshift-gitops-server -n openshift-gitops &> /dev/null; then
    echo "❌ Error: ArgoCD Server deployment not found"
    exit 1
fi

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD Server to be ready..."
oc wait --for=condition=available --timeout=300s \
    deployment/openshift-gitops-server -n openshift-gitops || {
    echo "❌ Error: ArgoCD Server did not become ready"
    exit 1
}
echo "✅ ArgoCD Server is ready"
echo ""

# Create namespaces
echo "Creating namespaces..."
for NS in llmops-dev llmops-staging llmops-prod; do
    if oc get namespace $NS &> /dev/null; then
        echo "  ℹ️  Namespace $NS already exists"
    else
        oc create namespace $NS
        echo "  ✅ Created namespace: $NS"
    fi
done
echo ""

# Grant ArgoCD permissions to manage the namespaces
echo "Configuring ArgoCD permissions..."
ARGOCD_SA="openshift-gitops-argocd-application-controller"

for NS in llmops-dev llmops-staging llmops-prod; do
    # Check if RoleBinding already exists
    if oc get rolebinding argocd-admin -n $NS &> /dev/null; then
        echo "  ℹ️  RoleBinding already exists in $NS"
    else
        oc create rolebinding argocd-admin \
            --clusterrole=admin \
            --serviceaccount=openshift-gitops:$ARGOCD_SA \
            -n $NS
        echo "  ✅ Granted ArgoCD admin access to $NS"
    fi
done
echo ""

# Get ArgoCD route
echo "Getting ArgoCD Server URL..."
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
echo "✅ ArgoCD Server URL: https://$ARGOCD_ROUTE"
echo ""

# Get ArgoCD admin password
echo "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)
echo "✅ ArgoCD admin password retrieved"
echo ""

# Summary
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Summary:"
echo "  - Namespaces created: llmops-dev, llmops-staging, llmops-prod"
echo "  - ArgoCD permissions configured"
echo ""
echo "🌐 ArgoCD Access:"
echo "  URL:      https://$ARGOCD_ROUTE"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo "📝 Next Steps:"
echo "  1. Update argocd-apps/*.yaml files with your Git repository URL"
echo "  2. Push this code to your Git repository"
echo "  3. Apply ArgoCD Applications:"
echo "     oc apply -f argocd-apps/dev-application.yaml"
echo "     oc apply -f argocd-apps/staging-application.yaml"
echo "     oc apply -f argocd-apps/production-application.yaml"
echo "  4. Access ArgoCD UI to monitor deployments"
echo ""
echo "🔗 For detailed instructions, see: step-by-step-guide.md"
echo ""

