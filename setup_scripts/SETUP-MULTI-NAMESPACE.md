# Multi-Namespace Setup Guide

This demo uses **three separate namespaces** to simulate real-world environment isolation:

- `llmops-dev` - Development environment
- `llmops-staging` - Staging environment  
- `llmops-prod` - Production environment

## Quick Setup

### 1. Run the Setup Script

```bash
# Make sure you're logged into OpenShift
oc login https://YOUR_CLUSTER_URL

# Run the automated setup script
./setup_scripts/setup-namespaces.sh
```

This script will:
- ✅ Create three namespaces
- ✅ Create service accounts in each namespace
- ✅ Set up roles and permissions
- ✅ Configure cross-namespace access
- ✅ Generate a service account token for GitHub Actions
- ✅ Display your OpenShift server URL

### 2. Save the Credentials

The script outputs two values - save these for GitHub Secrets:

1. **OPENSHIFT_TOKEN** - A long token starting with `eyJ...`
2. **OPENSHIFT_SERVER** - Your cluster API URL

### 3. Manual Setup (if you prefer)

If you want to set up manually instead of using the script:

```bash
# Create namespaces
oc create namespace llmops-dev
oc create namespace llmops-staging
oc create namespace llmops-prod

# For each namespace, create service account and permissions
for NS in llmops-dev llmops-staging llmops-prod; do
  # Service account
  oc create serviceaccount github-deployer -n $NS
  
  # Roles
  oc create role model-deployer -n $NS \
    --verb=get,list,watch,create,update,patch,delete \
    --resource=inferenceservices,servingruntimes,secrets,services,routes
  
  oc create role model-deployer-core -n $NS \
    --verb=get,list,watch \
    --resource=pods,deployments,events
  
  # Role bindings
  oc create rolebinding model-deployer-binding -n $NS \
    --role=model-deployer \
    --serviceaccount=$NS:github-deployer
  
  oc create rolebinding model-deployer-core-binding -n $NS \
    --role=model-deployer-core \
    --serviceaccount=$NS:github-deployer
done

# Create ClusterRole for cross-namespace access
oc create clusterrole llmops-model-deployer \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=inferenceservices,servingruntimes,secrets,services,routes,pods,deployments,events

# Grant cross-namespace permissions
for NS in llmops-dev llmops-staging llmops-prod; do
  oc create rolebinding llmops-cross-namespace -n $NS \
    --clusterrole=llmops-model-deployer \
    --serviceaccount=llmops-dev:github-deployer
done

# Generate token (use dev namespace service account)
oc create token github-deployer -n llmops-dev --duration=8760h

# Get server URL
oc whoami --show-server
```

## Deployment

### Deploy All Three Environments

```bash
# Deploy dev
oc apply -k deploy_model/overlays/dev/

# Deploy staging
oc apply -k deploy_model/overlays/staging/

# Deploy production
oc apply -k deploy_model/overlays/production/
```

### Verify Deployments

```bash
# Check dev
oc get inferenceservice -n llmops-dev
oc get pods -n llmops-dev

# Check staging
oc get inferenceservice -n llmops-staging
oc get pods -n llmops-staging

# Check production
oc get inferenceservice -n llmops-prod
oc get pods -n llmops-prod

# View all at once
oc get inferenceservice --all-namespaces | grep llmops
```

### Get External Routes

```bash
# Get all routes
oc get route -n llmops-dev
oc get route -n llmops-staging
oc get route -n llmops-prod

# Or all at once
oc get route --all-namespaces | grep llmops
```

## GitHub Actions Integration

The GitHub Action workflow automatically detects which environment to deploy based on the changed files:

- **Change `deploy_model/overlays/dev/`** → Deploys to `llmops-dev` namespace
- **Change `deploy_model/overlays/staging/`** → Deploys to `llmops-staging` namespace
- **Change `deploy_model/overlays/production/`** → Deploys to `llmops-prod` namespace

## Demo Flow

### Scenario 1: Progressive Rollout

```bash
# 1. Make change to dev
vim deploy_model/overlays/dev/kustomization.yaml
git add deploy_model/overlays/dev/
git commit -m "Test CPU increase in dev"
git push
# → GitHub Action deploys to llmops-dev

# 2. After validation, promote to staging
cp deploy_model/overlays/dev/kustomization.yaml deploy_model/overlays/staging/
git add deploy_model/overlays/staging/
git commit -m "Promote changes to staging"
git push
# → GitHub Action deploys to llmops-staging

# 3. After testing, deploy to production
cp deploy_model/overlays/staging/kustomization.yaml deploy_model/overlays/production/
git add deploy_model/overlays/production/
git commit -m "Deploy to production"
git push
# → GitHub Action deploys to llmops-prod
```

### Scenario 2: Environment-Specific Change

```bash
# Scale only production
vim deploy_model/overlays/production/kustomization.yaml
# Increase replicas or resources

git add deploy_model/overlays/production/
git commit -m "Scale production for high traffic"
git push
# → Only llmops-prod is updated
```

## Resource Requirements

To run all three environments simultaneously:

- **Total CPUs**: 7 cores (1 + 2 + 4)
- **Total Memory**: 26Gi (6 + 8 + 12)
- **Total GPUs**: 3

If resources are limited, you can:
1. Deploy only dev initially
2. Deploy to staging/prod as needed
3. Use `oc delete -k deploy_model/overlays/dev/` to free resources

## Cleanup

```bash
# Delete specific environment
oc delete -k deploy_model/overlays/dev/
oc delete -k deploy_model/overlays/staging/
oc delete -k deploy_model/overlays/production/

# Or delete entire namespaces
oc delete namespace llmops-dev
oc delete namespace llmops-staging
oc delete namespace llmops-prod
```

## Troubleshooting

### Service Account Token Issues

If the token doesn't have access to all namespaces, you can generate separate tokens:

```bash
# Generate token for each namespace
DEV_TOKEN=$(oc create token github-deployer -n llmops-dev --duration=8760h)
STAGING_TOKEN=$(oc create token github-deployer -n llmops-staging --duration=8760h)
PROD_TOKEN=$(oc create token github-deployer -n llmops-prod --duration=8760h)
```

However, for this demo, one token from the dev namespace should work for all three.

### Check Permissions

```bash
# Verify service account can access resources
oc auth can-i create inferenceservices -n llmops-dev --as=system:serviceaccount:llmops-dev:github-deployer
oc auth can-i create inferenceservices -n llmops-staging --as=system:serviceaccount:llmops-dev:github-deployer
oc auth can-i create inferenceservices -n llmops-prod --as=system:serviceaccount:llmops-dev:github-deployer
```

## Benefits of Multi-Namespace Setup

✅ **Isolation** - Environments are completely separated

✅ **Realistic** - Mirrors real-world multi-environment setups

✅ **Resource Control** - Different quotas per namespace (optional)

✅ **Access Control** - Fine-grained RBAC per environment

✅ **Clear Separation** - Easy to see which environment you're in

✅ **Production Safety** - Accidental changes to dev won't affect prod

