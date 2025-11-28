# LLMOps Demo - Automated Model Deployment to OpenShift

This repository demonstrates a simple LLMOps workflow using GitHub Actions to automatically deploy AI models to an OpenShift cluster running Red Hat OpenShift AI.

## Overview

When you push changes to model deployment files in this repository, GitHub Actions automatically:
1. Connects to your OpenShift cluster
2. Applies the updated model configuration
3. Waits for the model to be ready
4. Reports deployment status

## Architecture

```
Developer Push → GitHub → GitHub Actions → OpenShift Cluster → Model Deployed
```

- **Model**: Qwen 2.5 0.5B Instruct (vLLM inference)
- **Platform**: Red Hat OpenShift AI with KServe
- **Automation**: GitHub Actions
- **Deployment**: Kustomize

---

## Prerequisites

- OpenShift cluster with Red Hat OpenShift AI installed
- KServe enabled on the cluster
- GPU nodes available (with NVIDIA GPU operator)
- GitHub account
- `oc` CLI installed locally

---

## Setup Instructions

### 1. OpenShift Cluster Setup

#### Create Namespace
```bash
oc create namespace llmops-demo
```

#### Create Service Account for GitHub Actions
```bash
# Create service account
oc create serviceaccount github-deployer -n llmops-demo

# Create role with deployment permissions
oc create role model-deployer -n llmops-demo \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=inferenceservices,servingruntimes,secrets,services,routes

# Create role for monitoring resources
oc create role model-deployer-core -n llmops-demo \
  --verb=get,list,watch \
  --resource=pods,deployments,events

# Bind roles to service account
oc create rolebinding model-deployer-binding -n llmops-demo \
  --role=model-deployer \
  --serviceaccount=llmops-demo:github-deployer

oc create rolebinding model-deployer-core-binding -n llmops-demo \
  --role=model-deployer-core \
  --serviceaccount=llmops-demo:github-deployer
```

#### Generate Service Account Token
```bash
# Generate long-lived token (1 year)
oc create token github-deployer -n llmops-demo --duration=8760h
```

Save this token - you'll need it for GitHub Secrets.

#### Get OpenShift API Server URL
```bash
oc whoami --show-server
```

Example output: `https://api.cluster-xxxxx.opentlc.com:6443`

---

### 2. GitHub Repository Setup

#### Create GitHub Repository
1. Go to https://github.com/new
2. Create a new repository (public or private)
3. Do not initialize with README, .gitignore, or license

#### Clone and Push This Code
```bash
# Initialize git (if not already done)
git init
git add .
git commit -m "Initial commit: LLMOps demo setup"

# Add GitHub remote
git remote add origin https://github.com/YOUR_USERNAME/llmops-demo.git

# Push to GitHub
git branch -M main
git push -u origin main
```

**Note**: Your Personal Access Token must have `workflow` scope to push workflow files.

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

### Manual Initial Deployment

Deploy the model manually the first time:

```bash
# Login to OpenShift
oc login --server=YOUR_SERVER_URL --token=YOUR_TOKEN

# Deploy the model
oc apply -k deploy_model/

# Check deployment status
oc get inferenceservice -n llmops-demo

# Get the external route
oc get route -n llmops-demo
```

### Making Changes via LLMOps Workflow

After the initial deployment, any changes to model configuration will be automatically deployed:

1. **Edit model files** in `deploy_model/` directory:
   - `inferenceservice.yaml` - Model configuration, resources, scaling
   - `servingruntime.yaml` - Runtime settings (vLLM parameters)
   - `oci-data-connection.yaml` - Model source location

2. **Commit and push changes**:
   ```bash
   git add deploy_model/
   git commit -m "Update model configuration"
   git push
   ```

3. **Watch automation**:
   - Go to `https://github.com/YOUR_USERNAME/llmops-demo/actions`
   - View the workflow run in real-time
   - Check OpenShift console for updated deployment

### Example Changes

**Update CPU resources:**
```yaml
resources:
  limits:
    cpu: '4'  # Changed from 2
```

**Change model version:**
```yaml
storageUri: 'oci://quay.io/redhat-ai-services/modelcar-catalog:granite-3.0-2b-instruct'
```

**Scale replicas:**
```yaml
maxReplicas: 3
minReplicas: 2
```

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy-model.yml    # GitHub Actions workflow
├── deploy_model/               # Model deployment manifests
│   ├── inferenceservice.yaml   # Model definition
│   ├── kustomization.yaml      # Kustomize configuration
│   ├── oci-data-connection.yaml # Model source credentials
│   └── servingruntime.yaml     # vLLM runtime configuration
└── README.md                   # This file
```

---

## Workflow Details

The GitHub Action workflow (`.github/workflows/deploy-model.yml`) triggers on:
- Push to `main` branch
- Changes to files in `deploy_model/` directory
- Manual workflow dispatch

**Workflow Steps:**
1. Checkout code
2. Install OpenShift CLI
3. Login to OpenShift cluster
4. Show what changed
5. Apply model configuration: `oc apply -k deploy_model/`
6. Wait for InferenceService to be ready
7. Display deployment status

---

## Model Information

**Current Model**: Qwen 2.5 0.5B Instruct
- **Source**: `quay.io/redhat-ai-services/modelcar-catalog:qwen2.5-0.5b-instruct`
- **Size**: 0.5 billion parameters
- **Inference Engine**: vLLM
- **API**: OpenAI-compatible endpoints
- **GPU Required**: 1x NVIDIA GPU

**Resources:**
- CPU: 1-2 cores
- Memory: 4-8 GiB
- GPU: 1

---

## Accessing the Deployed Model

After deployment, the model is accessible via an external route with OAuth authentication:

```bash
# Get the route URL
oc get route -n llmops-demo

# Test the model (requires authentication)
curl https://YOUR_ROUTE_URL/v1/models
```

---

## What This Demonstrates

This LLMOps demo showcases:
- ✅ **GitOps for AI/ML** - Infrastructure and models as code
- ✅ **Automated Deployment** - Push code, get deployed model
- ✅ **Version Control** - Track all model configuration changes
- ✅ **CI/CD for Models** - Continuous deployment pipeline
- ✅ **Change Management** - Review and approve model changes via Git
- ✅ **Reproducibility** - All configurations in version control

---

## License

This is a demonstration project for educational purposes.

