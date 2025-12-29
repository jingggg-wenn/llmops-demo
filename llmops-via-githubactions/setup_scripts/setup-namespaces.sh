#!/bin/bash
#
# Setup script for multi-namespace LLMOps demo
# Creates three namespaces (dev, staging, production) with service accounts
#

set -e

echo "=========================================="
echo "Setting up LLMOps Multi-Namespace Demo"
echo "=========================================="
echo ""

# Define namespaces
NAMESPACES=("llmops-dev" "llmops-staging" "llmops-prod")

# Create namespaces and service accounts
for NS in "${NAMESPACES[@]}"; do
  echo "Setting up namespace: $NS"
  
  # Create namespace
  if oc get namespace $NS &>/dev/null; then
    echo "  ✓ Namespace $NS already exists"
  else
    oc create namespace $NS
    echo "  ✓ Created namespace $NS"
  fi
  
  # Create service account
  if oc get serviceaccount github-deployer -n $NS &>/dev/null; then
    echo "  ✓ Service account github-deployer already exists in $NS"
  else
    oc create serviceaccount github-deployer -n $NS
    echo "  ✓ Created service account github-deployer in $NS"
  fi
  
  # Create role with deployment permissions
  if oc get role model-deployer -n $NS &>/dev/null; then
    echo "  ✓ Role model-deployer already exists in $NS"
  else
    oc create role model-deployer -n $NS \
      --verb=get,list,watch,create,update,patch,delete \
      --resource=inferenceservices,servingruntimes,secrets,services,routes
    echo "  ✓ Created role model-deployer in $NS"
  fi
  
  # Create role for monitoring
  if oc get role model-deployer-core -n $NS &>/dev/null; then
    echo "  ✓ Role model-deployer-core already exists in $NS"
  else
    oc create role model-deployer-core -n $NS \
      --verb=get,list,watch \
      --resource=pods,deployments,events
    echo "  ✓ Created role model-deployer-core in $NS"
  fi
  
  # Bind roles to service account
  if oc get rolebinding model-deployer-binding -n $NS &>/dev/null; then
    echo "  ✓ RoleBinding model-deployer-binding already exists in $NS"
  else
    oc create rolebinding model-deployer-binding -n $NS \
      --role=model-deployer \
      --serviceaccount=$NS:github-deployer
    echo "  ✓ Created rolebinding model-deployer-binding in $NS"
  fi
  
  if oc get rolebinding model-deployer-core-binding -n $NS &>/dev/null; then
    echo "  ✓ RoleBinding model-deployer-core-binding already exists in $NS"
  else
    oc create rolebinding model-deployer-core-binding -n $NS \
      --role=model-deployer-core \
      --serviceaccount=$NS:github-deployer
    echo "  ✓ Created rolebinding model-deployer-core-binding in $NS"
  fi
  
  echo ""
done

echo "=========================================="
echo "Setting up Cross-Namespace Permissions"
echo "=========================================="
echo ""
echo "Creating ClusterRole and RoleBindings for cross-namespace access..."

# Create ClusterRole for model deployment
if oc get clusterrole llmops-model-deployer &>/dev/null; then
  echo "  ✓ ClusterRole llmops-model-deployer already exists"
else
  oc create clusterrole llmops-model-deployer \
    --verb=get,list,watch,create,update,patch,delete \
    --resource=inferenceservices,servingruntimes,secrets,services,routes,pods,deployments,events
  echo "  ✓ Created ClusterRole llmops-model-deployer"
fi

# Bind the ClusterRole to the service account in each namespace
for NS in "${NAMESPACES[@]}"; do
  if oc get rolebinding llmops-cross-namespace -n $NS &>/dev/null; then
    echo "  ✓ RoleBinding already exists in $NS"
  else
    oc create rolebinding llmops-cross-namespace \
      -n $NS \
      --clusterrole=llmops-model-deployer \
      --serviceaccount=llmops-dev:github-deployer
    echo "  ✓ Created RoleBinding in $NS for llmops-dev:github-deployer"
  fi
done

echo ""
echo "Verifying permissions..."
for NS in "${NAMESPACES[@]}"; do
  CAN_DEPLOY=$(oc auth can-i create inferenceservices -n $NS --as=system:serviceaccount:llmops-dev:github-deployer)
  echo "  Can deploy to $NS: $CAN_DEPLOY"
done

echo ""
echo "=========================================="
echo "Generating Service Account Token"
echo "=========================================="
echo ""
echo "Using ONE token from llmops-dev with access to all namespaces:"
echo ""

# Generate token from dev namespace (it now has permissions for all three namespaces)
TOKEN=$(oc create token github-deployer -n llmops-dev --duration=8760h)

echo "OPENSHIFT_TOKEN (save this for GitHub Secrets):"
echo "------------------------------------------------"
echo "$TOKEN"
echo ""

echo "=========================================="
echo "OpenShift API Server URL"
echo "=========================================="
echo ""
SERVER=$(oc whoami --show-server)
echo "OPENSHIFT_SERVER (save this for GitHub Secrets):"
echo "------------------------------------------------"
echo "$SERVER"
echo ""

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Add OPENSHIFT_TOKEN to GitHub Secrets"
echo "2. Add OPENSHIFT_SERVER to GitHub Secrets"
echo "3. Deploy to each environment:"
echo "   - oc apply -k deploy_model/overlays/dev/"
echo "   - oc apply -k deploy_model/overlays/staging/"
echo "   - oc apply -k deploy_model/overlays/production/"
echo ""
echo "Verify deployments:"
echo "   - oc get inferenceservice -n llmops-dev"
echo "   - oc get inferenceservice -n llmops-staging"
echo "   - oc get inferenceservice -n llmops-prod"
echo ""

