# LLMOps Demo - Automated Model Deployment to OpenShift

This repository demonstrates a production-ready LLMOps workflow using **Kustomize overlays** and **GitHub Actions** to automatically deploy AI models to OpenShift with environment-specific configurations.

## Overview

This demo showcases:
- **Environment-based deployments** using Kustomize overlays (dev, staging, production)
- **Automated CI/CD** for model deployments via GitHub Actions
- **GitOps best practices** for managing model lifecycle
- **Progressive rollout strategy** from dev → staging → production

When you push changes to model deployment files, GitHub Actions automatically:
1. Detects which environment changed
2. Connects to your OpenShift cluster
3. Applies the environment-specific configuration
4. Waits for the model to be ready
5. Reports deployment status

## Architecture

```
Developer → Git Push → GitHub Actions → OpenShift (Dev/Staging/Prod) → Model Deployed
```

**Technology Stack:**
- **Model**: Qwen 2.5 0.5B Instruct (vLLM inference)
- **Platform**: Red Hat OpenShift AI with KServe
- **Automation**: GitHub Actions
- **Configuration Management**: Kustomize with overlays
- **GitOps**: Infrastructure and models as code

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy-model.yml          # GitHub Actions workflow
├── deploy_model/
│   ├── base/                         # Base configuration (shared)
│   │   ├── inferenceservice.yaml     # Model definition
│   │   ├── servingruntime.yaml       # vLLM runtime config
│   │   ├── oci-data-connection.yaml  # Model source
│   │   └── kustomization.yaml
│   ├── overlays/                     # Environment-specific configs
│   │   ├── dev/                      # Development environment
│   │   │   └── kustomization.yaml
│   │   ├── staging/                  # Staging environment
│   │   │   └── kustomization.yaml
│   │   └── production/               # Production environment
│   │       └── kustomization.yaml
│   └── README.md                     # Overlay documentation
├── setup_scripts/                    # Setup automation
│   ├── setup-namespaces.sh           # Automated namespace setup
│   ├── SETUP-MULTI-NAMESPACE.md      # Detailed setup guide
│   └── README.md                     # Setup scripts documentation
└── README.md                         # This file
```

---

## Environment Configurations

This demo uses **Kustomize overlays** to manage three environments with different resource allocations:

| Environment | CPU Limit | Memory Limit | Replicas | Purpose |
|-------------|-----------|--------------|----------|---------|
| **Dev** | 1 core | 6Gi | 1 (fixed) | Development & testing |
| **Staging** | 2 cores | 8Gi | 1-2 (autoscaling) | Pre-production validation |
| **Production** | 4 cores | 12Gi | 2-3 (autoscaling + HA) | Production workloads |

**Name Prefixes:**
- Dev: `dev-qwen25-05b-instruct`
- Staging: `staging-qwen25-05b-instruct`
- Production: `prod-qwen25-05b-instruct`

---

## Prerequisites

- OpenShift cluster with Red Hat OpenShift AI installed
- KServe enabled on the cluster
- GPU nodes available (with NVIDIA GPU operator)
- GitHub account with Personal Access Token (with `workflow` scope)
- `oc` CLI installed locally
- `kustomize` installed (optional, for local testing)

---

## Setup Instructions

### Quick Setup (Recommended)

**Use the automated setup script:**

```bash
# Login to OpenShift
oc login https://YOUR_CLUSTER_URL

# Run the automated setup
./setup_scripts/setup-namespaces.sh
```

This script automatically creates all three namespaces (dev, staging, production) with proper permissions and generates credentials for GitHub Actions.

**For detailed setup instructions**, see [setup_scripts/SETUP-MULTI-NAMESPACE.md](setup_scripts/SETUP-MULTI-NAMESPACE.md)

---

### Manual Setup (Alternative)

If you prefer manual setup:

#### Create Namespaces
```bash
# Create three namespaces
oc create namespace llmops-dev
oc create namespace llmops-staging
oc create namespace llmops-prod

# Create service accounts and permissions
# (Run for each namespace: llmops-dev, llmops-staging, llmops-prod)
for NS in llmops-dev llmops-staging llmops-prod; do
  oc create serviceaccount github-deployer -n $NS
  
  oc create role model-deployer -n $NS \
    --verb=get,list,watch,create,update,patch,delete \
    --resource=inferenceservices,servingruntimes,secrets,services,routes
  
  oc create role model-deployer-core -n $NS \
    --verb=get,list,watch \
    --resource=pods,deployments,events
  
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

# Grant cross-namespace permissions to dev service account
for NS in llmops-dev llmops-staging llmops-prod; do
  oc create rolebinding llmops-cross-namespace -n $NS \
    --clusterrole=llmops-model-deployer \
    --serviceaccount=llmops-dev:github-deployer
done
```

#### Generate Service Account Token
```bash
# Generate long-lived token (1 year) from dev namespace
# This token has access to all three namespaces via cross-namespace permissions
oc create token github-deployer -n llmops-dev --duration=8760h
```

Save this token - you'll need it for GitHub Secrets.

#### Get OpenShift API Server URL
```bash
oc whoami --show-server
```

Example output: `https://api.cluster-xxxxx.opentlc.com:6443`

**Note:** The automated script ([setup_scripts/setup-namespaces.sh](setup_scripts/setup-namespaces.sh)) handles all of the above automatically.

---

### 2. GitHub Repository Setup

#### Create GitHub Repository
1. Go to https://github.com/new
2. Create a new repository (public or private)
3. Do not initialize with README, .gitignore, or license

#### Create Personal Access Token with Workflow Scope
1. Go to https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Select scopes:
   - ✅ `repo` (all)
   - ✅ `workflow`
4. Generate and copy the token

#### Push Code to GitHub
```bash
# Initialize git (if not already done)
git init
git add .
git commit -m "Initial commit: LLMOps demo with Kustomize overlays"

# Add GitHub remote
git remote add origin https://YOUR_TOKEN@github.com/YOUR_USERNAME/llmops-demo.git

# Push to GitHub
git branch -M main
git push -u origin main
```

---

### 3. Configure GitHub Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **"New repository secret"**
4. Add two secrets:

**Secret 1:**
- **Name**: `OPENSHIFT_TOKEN`
- **Value**: The token from `oc create token` command

**Secret 2:**
- **Name**: `OPENSHIFT_SERVER`
- **Value**: Your OpenShift API server URL (e.g., `https://api.cluster-xxxxx.opentlc.com:6443`)

---

## Usage

### Initial Manual Deployment

Deploy to dev environment first to test:

```bash
# Login to OpenShift
oc login --server=YOUR_SERVER_URL --token=YOUR_TOKEN

# Deploy dev environment
oc apply -k deploy_model/overlays/dev/

# Check deployment status
oc get inferenceservice -n llmops-dev

# Get the external route
oc get route -n llmops-dev
```

### Automated Deployments via GitHub Actions

The workflow automatically deploys based on which files are changed:

#### Deploy to Dev
```bash
# Edit dev overlay
vim deploy_model/overlays/dev/kustomization.yaml

# Commit and push
git add deploy_model/overlays/dev/
git commit -m "Update dev environment configuration"
git push
```

GitHub Actions will automatically deploy to the **dev** environment.

#### Deploy to Staging
```bash
# Edit staging overlay
vim deploy_model/overlays/staging/kustomization.yaml

# Commit and push
git add deploy_model/overlays/staging/
git commit -m "Promote changes to staging"
git push
```

GitHub Actions will automatically deploy to the **staging** environment.

#### Deploy to Production
```bash
# Edit production overlay
vim deploy_model/overlays/production/kustomization.yaml

# Commit and push
git add deploy_model/overlays/production/
git commit -m "Deploy to production"
git push
```

GitHub Actions will automatically deploy to the **production** environment.

### Manual Workflow Dispatch

You can also manually trigger deployments from GitHub UI:

1. Go to **Actions** tab in your repository
2. Select **"Deploy Model to OpenShift"** workflow
3. Click **"Run workflow"**
4. Choose environment: dev, staging, or production
5. Click **"Run workflow"**

---

## LLMOps Workflows

### Progressive Rollout Pattern

```
1. Develop & Test (Dev)
   ├─ Make changes to base/ or dev overlay
   ├─ Push changes
   └─ Auto-deploy to dev environment

2. Validate (Staging)
   ├─ Test passes in dev
   ├─ Update staging overlay
   └─ Auto-deploy to staging environment

3. Production Release
   ├─ Validate in staging
   ├─ Update production overlay
   └─ Auto-deploy to production environment
```

### Common LLMOps Scenarios

#### Scenario 1: Update All Environments (Model Version Change)
```bash
# Edit base configuration (applies to all environments)
vim deploy_model/base/inferenceservice.yaml

# Change storageUri to new model version
# Commit and push

git add deploy_model/base/
git commit -m "Upgrade model from 0.5B to 3B"
git push

# Then progressively update each environment's overlay
```

#### Scenario 2: Scale Production Only
```bash
# Edit production overlay
vim deploy_model/overlays/production/kustomization.yaml

# Increase replicas in the patches section
git add deploy_model/overlays/production/
git commit -m "Scale production to 5 replicas for Black Friday"
git push
```

#### Scenario 3: Test New Inference Settings in Dev
```bash
# Edit base servingruntime
vim deploy_model/base/servingruntime.yaml

# Add new vLLM arguments
# Test in dev first, then promote to staging/prod
```

---

## Workflow Details

The GitHub Action workflow (`.github/workflows/deploy-model.yml`) features:

**Triggers:**
- Push to `main` branch (changes in `deploy_model/` directory)
- Manual workflow dispatch with environment selection

**Smart Environment Detection:**
- Automatically detects which overlay was modified
- Routes deployment to the appropriate environment
- Waits for InferenceService to be ready
- Reports deployment status

**Workflow Steps:**
1. Checkout code
2. Install OpenShift CLI
3. Login to OpenShift cluster
4. Determine target environment (auto or manual)
5. Show what changed
6. Apply environment-specific configuration: `oc apply -k deploy_model/overlays/$ENV/`
7. Wait for InferenceService to be ready (with proper naming)
8. Display deployment status and events

---

## Model Information

**Current Model**: Qwen 2.5 0.5B Instruct
- **Source**: `quay.io/redhat-ai-services/modelcar-catalog:qwen2.5-0.5b-instruct`
- **Size**: 0.5 billion parameters
- **Inference Engine**: vLLM
- **API**: OpenAI-compatible endpoints
- **GPU Required**: 1x NVIDIA GPU

**Base Resources** (overridden by overlays):
- CPU: 1-2 cores
- Memory: 4-8 GiB
- GPU: 1

---

## Testing Locally

Preview what Kustomize will generate for each environment:

```bash
# Preview dev configuration
kustomize build deploy_model/overlays/dev/

# Preview staging configuration
kustomize build deploy_model/overlays/staging/

# Preview production configuration
kustomize build deploy_model/overlays/production/

# Compare dev vs production
diff <(kustomize build deploy_model/overlays/dev/) \
     <(kustomize build deploy_model/overlays/production/)
```

---

## Accessing the Deployed Model

After deployment, models are accessible via external routes with OAuth authentication:

```bash
# List all routes across environments
oc get route --all-namespaces | grep llmops

# Or list routes per environment
oc get route -n llmops-dev
oc get route -n llmops-staging
oc get route -n llmops-prod

# Example routes:
# - dev-qwen25-05b-instruct-llmops-dev.apps.cluster...
# - staging-qwen25-05b-instruct-llmops-staging.apps.cluster...
# - prod-qwen25-05b-instruct-llmops-prod.apps.cluster...

# Test the model endpoint
ROUTE_URL=$(oc get route dev-qwen25-05b-instruct -n llmops-dev -o jsonpath='{.spec.host}')
curl https://$ROUTE_URL/v1/models
```

---

## What This LLMOps Demo Showcases

✅ **Environment-Based Deployments** - Separate configs for dev/staging/prod using Kustomize overlays

✅ **GitOps for AI/ML** - Infrastructure and models as code with version control

✅ **Automated CI/CD** - Push code, trigger automatic deployment to correct environment

✅ **Progressive Delivery** - Safe rollout pattern from dev → staging → production

✅ **Configuration Management** - DRY principle with base + overlays (no duplication)

✅ **Reproducibility** - All configurations tracked in Git, auditable and repeatable

✅ **Resource Optimization** - Right-sized resources per environment (cost-effective)

✅ **Change Management** - Review and approve model changes via Pull Requests

✅ **Multi-Environment Management** - Manage multiple model instances with single codebase

---

## Advanced Topics

### Adding a New Environment

1. Create new overlay directory:
   ```bash
   mkdir -p deploy_model/overlays/qa
   ```

2. Create kustomization.yaml with environment-specific patches

3. Update GitHub Actions workflow to recognize the new environment

### Changing the Model

To deploy a completely different model:

1. Update `deploy_model/base/inferenceservice.yaml`:
   - Change `storageUri` to new model location
   - Update resource requirements
   - Modify display names

2. Update `deploy_model/base/servingruntime.yaml`:
   - Adjust vLLM arguments for the new model

3. Test in dev, validate in staging, deploy to production

---

## Troubleshooting

### Check Deployment Status
```bash
# View all inference services across environments
oc get inferenceservice --all-namespaces | grep llmops

# View specific environment
oc get inferenceservice -n llmops-dev
oc get inferenceservice -n llmops-staging
oc get inferenceservice -n llmops-prod

# Describe specific service
oc describe inferenceservice dev-qwen25-05b-instruct -n llmops-dev

# Check pods in specific environment
oc get pods -n llmops-dev

# View logs
oc logs <pod-name> -n llmops-dev
```

### GitHub Actions Failing
1. Check GitHub Secrets are set correctly
2. Verify service account has proper permissions
3. Check OpenShift token hasn't expired
4. Review workflow logs in Actions tab

---

## License

This is a demonstration project for educational purposes.
