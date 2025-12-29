# Step-by-Step Guide: GitOps LLMOps with ArgoCD and OpenShift Pipelines

This guide walks you through setting up a production-ready LLMOps workflow using **ArgoCD for GitOps deployment** and **OpenShift Pipelines** (Tekton) for CI/CD automation on Red Hat OpenShift AI.

**What You'll Build:** A true GitOps workflow where ArgoCD continuously monitors your Git repository and automatically syncs model deployments to OpenShift, with full visibility and version tracking.

## Table of Contents

1. [Prerequisites Check](#step-1-prerequisites-check)
2. [Understand the GitOps Architecture](#step-2-understand-the-gitops-architecture)
3. [Install Required Operators](#step-3-install-required-operators)
4. [Set Up OpenShift Namespaces](#step-4-set-up-openshift-namespaces)
5. [Configure GitHub Repository](#step-5-configure-github-repository)
6. [Deploy ArgoCD Applications](#step-6-deploy-argocd-applications)
7. [Test GitOps Workflow - Dev Environment](#step-7-test-gitops-workflow---dev-environment)
8. [Test Manual Sync - Staging Environment](#step-8-test-manual-sync---staging-environment)
9. [Production Deployment Workflow](#step-9-production-deployment-workflow)
10. [Monitor with ArgoCD Dashboard](#step-10-monitor-with-argocd-dashboard)
11. [Troubleshooting](#troubleshooting)

---

## Step 1: Prerequisites Check

### 1.1 Verify OpenShift Cluster Access

```bash
# Login to your OpenShift cluster
oc login https://YOUR_CLUSTER_URL

# Verify you have admin or necessary permissions
oc whoami
oc auth can-i create namespace
```

**Expected output:** Should show your username and `yes` for namespace creation.

### 1.2 Check OpenShift AI Installation

```bash
# Verify OpenShift AI is installed
oc get operators | grep rhods-operator

# Check KServe installation
oc get pods -n redhat-ods-applications | grep kserve
```

All KServe pods should be in `Running` state.

### 1.3 Verify GPU Nodes

```bash
# List GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU availability
GPU_NODE=$(oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}')
oc describe node $GPU_NODE | grep nvidia.com/gpu
```

**Expected output:** Should show available GPUs.

### 1.4 Check Local Tools

```bash
# Verify oc CLI
oc version

# Verify git
git --version

# Optional: Verify kustomize (for local testing)
kustomize version
```

### 1.5 Understanding OpenShift GitOps Namespaces

**Important:** There are multiple namespaces involved in this setup. Understanding them prevents confusion:

| Namespace | Purpose | What's Inside | When to Use |
|-----------|---------|---------------|-------------|
| `openshift-gitops-operator` or `openshift-operators` | Operator installation | GitOps operator pod | Checking operator status |
| `openshift-gitops` | ArgoCD instance | ArgoCD server, Application CRs, secrets, routes | All ArgoCD operations |
| `llmops-dev` | Dev environment | Model deployments (InferenceService, etc.) | Dev workloads |
| `llmops-staging` | Staging environment | Model deployments | Staging workloads |
| `llmops-prod` | Production environment | Model deployments | Production workloads |

**Key Points:**
- ✅ ArgoCD Application resources go in `openshift-gitops` namespace
- ✅ All ArgoCD commands use `openshift-gitops` namespace
- ✅ Your model workloads are deployed to `llmops-*` namespaces
- ❌ Don't confuse operator namespace with ArgoCD namespace

**Quick Verification:**
```bash
# Check operator namespace (either location is fine)
oc get pods -n openshift-gitops-operator 2>/dev/null || \
oc get pods -n openshift-operators | grep gitops

# Check ArgoCD namespace (this is what you'll use)
oc get pods -n openshift-gitops

# Expected output in openshift-gitops:
# openshift-gitops-server-*
# openshift-gitops-repo-server-*
# openshift-gitops-application-controller-*
```

---

## Step 2: Understand the GitOps Architecture

### 2.1 Architecture Overview

```
┌─────────────┐      ┌──────────────┐      ┌────────────────────────┐
│  Developer  │─────▶│    GitHub    │◀─────│   ArgoCD (watches)     │
│             │      │  Repository  │      │   (in OpenShift)       │
└─────────────┘      └──────────────┘      └────────────┬───────────┘
                                                         │
                          ┌──────────────────────────────┴─────────────┐
                          │                                            │
                          ▼                                            ▼
                  ┌───────────────┐                          ┌─────────────────┐
                  │  OpenShift    │                          │   OpenShift     │
                  │  llmops-dev   │                          │ llmops-staging  │
                  │  (auto-sync)  │                          │ (manual-sync)   │
                  └───────────────┘                          └─────────────────┘
                                                                      │
                                                                      ▼
                                                          ┌─────────────────┐
                                                          │   OpenShift     │
                                                          │  llmops-prod    │
                                                          │ (manual-sync)   │
                                                          └─────────────────┘
```

### 2.2 Key Differences from GitHub Actions Approach

| Aspect | GitHub Actions (Old) | ArgoCD GitOps (New) |
|--------|---------------------|---------------------|
| **Deployment Model** | Push (GH Actions pushes to cluster) | Pull (ArgoCD pulls from Git) |
| **Where it runs** | GitHub infrastructure | Inside OpenShift cluster |
| **State tracking** | None | ArgoCD tracks desired vs actual state |
| **Drift detection** | None | ArgoCD detects and alerts on drift |
| **Rollback** | Manual git revert + re-run | ArgoCD UI rollback or git revert |
| **Visibility** | GitHub Actions logs | ArgoCD dashboard with real-time status |
| **Secrets** | GitHub Secrets | No cluster credentials in Git |
| **Security** | Token stored in GitHub | ArgoCD runs inside cluster (no external access) |

### 2.3 Key Components

**ArgoCD Applications:**
- `llmops-dev` - Auto-syncs on every Git push
- `llmops-staging` - Manual sync required
- `llmops-production` - Manual sync required

**Kustomize Overlays:**
- `deploy_model/base/` - Shared model configuration
- `deploy_model/overlays/dev/` - Development-specific settings
- `deploy_model/overlays/staging/` - Staging-specific settings
- `deploy_model/overlays/production/` - Production-specific settings

**OpenShift Resources:**
- `InferenceService` - KServe model deployment
- `ServingRuntime` - vLLM inference engine configuration
- `Secret` - Model storage credentials (OCI data connection)
- `Route` - External model endpoint

### 2.4 Environment Configurations

| Environment | CPU Limit | Memory Limit | Replicas | Sync Policy | Purpose |
|-------------|-----------|--------------|----------|-------------|---------|
| **Dev** | 2 cores | 6Gi | 1 (fixed) | Auto-sync | Development & testing |
| **Staging** | 3 cores | 8Gi | 1-2 (autoscaling) | Manual sync | Pre-production validation |
| **Production** | 4 cores | 12Gi | 2-3 (HA) | Manual sync | Production workloads |

---

## Step 3: Install Required Operators

### 3.1 Install OpenShift GitOps Operator

**Via OpenShift Console:**

1. Login to OpenShift Console
2. Navigate to **Operators** → **OperatorHub**
3. Search for **"Red Hat OpenShift GitOps"**
4. Click on the operator tile
5. Click **"Install"**
6. Keep default settings:
   - Installation Mode: All namespaces on the cluster
   - Installed Namespace: openshift-operators
   - Update approval: Automatic
7. Click **"Install"**
8. Wait for installation to complete (Status: "Succeeded")

**Via CLI:**

```bash
# Create subscription for OpenShift GitOps
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for operator to be ready
oc get csv -n openshift-operators | grep gitops
```

**Verify Installation:**

```bash
# Check operator is installed (in openshift-operators or openshift-gitops-operator namespace)
oc get subscription openshift-gitops-operator -n openshift-operators || \
oc get subscription openshift-gitops-operator -n openshift-gitops-operator

# Check openshift-gitops namespace was created (where ArgoCD runs)
oc get namespace openshift-gitops

# Check ArgoCD Server is running
oc get pods -n openshift-gitops
```

**Expected output:** All pods in `openshift-gitops` namespace should be `Running`.

**Important Namespace Distinction:**
- **Operator namespace**: `openshift-gitops-operator` or `openshift-operators` (where the GitOps operator pod runs)
- **ArgoCD namespace**: `openshift-gitops` (where ArgoCD components run - server, repo-server, application-controller)
- **Application namespace**: `openshift-gitops` (where ArgoCD Application CRs are created)
- **Target namespaces**: `llmops-dev`, `llmops-staging`, `llmops-prod` (where your models are deployed)

You will use `openshift-gitops` namespace for all ArgoCD operations, regardless of where the operator is installed.

### 3.2 Install OpenShift Pipelines Operator

**Via OpenShift Console:**

1. Navigate to **Operators** → **OperatorHub**
2. Search for **"Red Hat OpenShift Pipelines"**
3. Click on the operator tile
4. Click **"Install"**
5. Keep default settings
6. Click **"Install"**
7. Wait for installation to complete

**Via CLI:**

```bash
# Create subscription for OpenShift Pipelines
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for operator to be ready
oc get csv -n openshift-operators | grep pipelines
```

**Verify Installation:**

```bash
# Check operator is installed
oc get subscription openshift-pipelines-operator -n openshift-operators

# Check Tekton components
oc get pods -n openshift-pipelines
```

**Note:** For this initial implementation, we'll focus on ArgoCD for deployment. OpenShift Pipelines will be used in Phase 2 for CI validation.

---

## Step 4: Set Up OpenShift Namespaces

### 4.1 Automated Setup (Recommended)

```bash
# Navigate to the setup scripts directory
cd enable-llmops-argo-ocppipelines/setup_scripts

# Make script executable
chmod +x setup-argocd.sh

# Run the setup script
./setup-argocd.sh
```

**What this script does:**
- Verifies OpenShift GitOps Operator is installed
- Creates three namespaces: `llmops-dev`, `llmops-staging`, `llmops-prod`
- Grants ArgoCD service account admin permissions to manage these namespaces
- Retrieves ArgoCD Server URL and admin password

**Expected output:**
```
==========================================
Setup Complete!
==========================================

📋 Summary:
  - Namespaces created: llmops-dev, llmops-staging, llmops-prod
  - ArgoCD permissions configured

🌐 ArgoCD Access:
  URL:      https://openshift-gitops-server-openshift-gitops.apps.cluster...
  Username: admin
  Password: xxxxxxxxxx

📝 Next Steps:
  1. Update argocd-apps/*.yaml files with your Git repository URL
  2. Push this code to your Git repository
  3. Apply ArgoCD Applications
  4. Access ArgoCD UI to monitor deployments
```

**IMPORTANT:** Save the ArgoCD URL and password - you'll need them to access the ArgoCD dashboard.

### 4.2 Manual Setup (Alternative)

If you prefer manual setup:

```bash
# Create three namespaces
oc create namespace llmops-dev
oc create namespace llmops-staging
oc create namespace llmops-prod

# Grant ArgoCD permissions to manage these namespaces
ARGOCD_SA="openshift-gitops-argocd-application-controller"

for NS in llmops-dev llmops-staging llmops-prod; do
  oc create rolebinding argocd-admin \
    --clusterrole=admin \
    --serviceaccount=openshift-gitops:$ARGOCD_SA \
    -n $NS
done
```

### 4.3 Verify Namespace Setup

```bash
# List all three namespaces
oc get namespace | grep llmops

# Verify ArgoCD has permissions
for NS in llmops-dev llmops-staging llmops-prod; do
  echo "Checking $NS..."
  oc auth can-i create inferenceservices -n $NS \
    --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
done
```

All permission checks should return `yes`.

### 4.4 Access ArgoCD Dashboard

```bash
# Get ArgoCD route
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
echo "ArgoCD URL: https://$ARGOCD_ROUTE"

# Get admin password
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
```

**Open the ArgoCD UI in your browser:**
1. Navigate to the URL from above
2. Login with username `admin` and the password
3. You should see an empty dashboard (no applications yet)

---

## Step 5: Configure GitHub Repository

### 5.1 Create GitHub Repository

1. Go to https://github.com/new
2. **Repository name:** `llmops-gitops-demo` (or your preferred name)
3. **Visibility:** Choose **Public** (easier for ArgoCD to access)
4. **Do NOT initialize** with README, .gitignore, or license
5. Click **"Create repository"**

### 5.2 Initialize Git Repository Locally

```bash
# Navigate to your enable-llmops-argo-ocppipelines directory
cd /path/to/rhoai-env-jw/enable-llmops-argo-ocppipelines

# Initialize git (if not already done)
git init

# Create .gitignore
cat > .gitignore <<EOF
# Temporary files
*.swp
*.swo
*~

# OS files
.DS_Store
Thumbs.db

# Editor directories
.vscode/
.idea/

# Build artifacts
*.yaml.bak
kustomize-output/
EOF

# Stage all files
git add .

# Initial commit
git commit -m "Initial commit: GitOps LLMOps with ArgoCD and OpenShift Pipelines"
```

### 5.3 Update ArgoCD Applications with Your Git Repository URL

Before pushing to GitHub, update the ArgoCD Application manifests with your repository URL.

**You need to edit these 3 files:**
- `argocd-apps/dev-application.yaml`
- `argocd-apps/staging-application.yaml`
- `argocd-apps/production-application.yaml`

**Option A: Automated Update (Recommended)**

```bash
# Replace YOUR_USERNAME and YOUR_REPO with your actual values
YOUR_USERNAME="your-github-username"
YOUR_REPO="llmops-gitops-demo"

# Update all three application files
sed -i.bak "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|https://github.com/$YOUR_USERNAME/$YOUR_REPO.git|g" argocd-apps/*.yaml

# Verify the changes
grep "repoURL:" argocd-apps/*.yaml

# Expected output:
# argocd-apps/dev-application.yaml:    repoURL: https://github.com/your-github-username/llmops-gitops-demo.git
# argocd-apps/production-application.yaml:    repoURL: https://github.com/your-github-username/llmops-gitops-demo.git
# argocd-apps/staging-application.yaml:    repoURL: https://github.com/your-github-username/llmops-gitops-demo.git

# Commit the changes
git add argocd-apps/*.yaml
git commit -m "Update ArgoCD applications with correct Git repository URL"
```

**Option B: Manual Edit**

Edit each of the three files and find the `repoURL` line (around line 13-14):

**In `argocd-apps/dev-application.yaml`:**
```yaml
spec:
  # Source: Git repository with Kustomize overlays
  source:
    repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git  # ← Change this line
    targetRevision: main
    path: enable-llmops-argo-ocppipelines/deploy_model/overlays/dev
  
  # Destination: Target namespace in OpenShift
  destination:
    server: https://kubernetes.default.svc  # ← Keep this as-is (internal cluster address)
    namespace: llmops-dev
```

**In `argocd-apps/staging-application.yaml`:**
```yaml
spec:
  # Source: Git repository with Kustomize overlays
  source:
    repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git  # ← Change this line
    targetRevision: main
    path: enable-llmops-argo-ocppipelines/deploy_model/overlays/staging
  
  # Destination: Target namespace in OpenShift
  destination:
    server: https://kubernetes.default.svc  # ← Keep this as-is (internal cluster address)
    namespace: llmops-staging
```

**In `argocd-apps/production-application.yaml`:**
```yaml
spec:
  # Source: Git repository with Kustomize overlays
  source:
    repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git  # ← Change this line
    targetRevision: main
    path: enable-llmops-argo-ocppipelines/deploy_model/overlays/production
  
  # Destination: Target namespace in OpenShift
  destination:
    server: https://kubernetes.default.svc  # ← Keep this as-is (internal cluster address)
    namespace: llmops-prod
```

Replace `YOUR_USERNAME` with your GitHub username and `YOUR_REPO` with your repository name.

**Example:**
```yaml
repoURL: https://github.com/jsmith/llmops-gitops-demo.git
```

---

### 5.3.1 Understanding the Destination Field

**Important:** You typically do **NOT** need to change the `destination` section.

**What is `server: https://kubernetes.default.svc`?**

This is the **internal Kubernetes API server address**. Since ArgoCD is running **inside** your OpenShift cluster, it uses this internal DNS name to communicate with the cluster's API server. This is more efficient and secure than using the external cluster URL.

**When to keep it as-is:**
- ✅ Deploying to the **same cluster** where ArgoCD is running (your scenario)
- ✅ All three environments (dev, staging, prod) are in the **same OpenShift cluster**

**When to change it:**
- ❌ Only if deploying to a **different/remote cluster**

**Example: Deploying to a Remote Cluster**

If you wanted ArgoCD to deploy to a **different** OpenShift cluster (e.g., a separate production cluster), you would change it to:

```yaml
# Example: Deploying to a remote production cluster
destination:
  server: https://api.prod-cluster.example.com:6443  # External API server URL
  namespace: llmops-prod
```

**To add a remote cluster to ArgoCD:**
```bash
# Login to the remote cluster
oc login https://api.prod-cluster.example.com:6443 --token=REMOTE_CLUSTER_TOKEN

# Add the cluster to ArgoCD
argocd cluster add prod-cluster-context --name prod-cluster

# Update the Application manifest
# destination:
#   server: https://api.prod-cluster.example.com:6443
#   namespace: llmops-prod
```

**For this demo, keep all destinations as:**
```yaml
destination:
  server: https://kubernetes.default.svc  # Internal address - do not change
  namespace: llmops-dev  # (or llmops-staging, llmops-prod)
```

---

### 5.4 Push to GitHub

```bash
# Add GitHub remote
git remote add origin https://github.com/$YOUR_USERNAME/$YOUR_REPO.git

# Set main branch
git branch -M main

# Push to GitHub
git push -u origin main
```

**Alternative (SSH):**
```bash
git remote add origin git@github.com:$YOUR_USERNAME/$YOUR_REPO.git
git push -u origin main
```

### 5.5 Verify GitHub Repository

1. Go to your repository on GitHub: `https://github.com/$YOUR_USERNAME/$YOUR_REPO`
2. You should see:
   - `argocd-apps/` directory with 3 Application YAML files
   - `deploy_model/` directory with base and overlays
   - `setup_scripts/` directory
   - `step-by-step-guide.md` (this file)

---

## Step 6: Deploy ArgoCD Applications

Now that your code is in Git, create the ArgoCD Applications that will monitor and deploy your models.

**Important:** ArgoCD Application resources are created in the `openshift-gitops` namespace (where ArgoCD runs), NOT in the operator namespace or target namespaces. The Application manifests already have the correct namespace configured:

```yaml
metadata:
  name: llmops-dev
  namespace: openshift-gitops  # ← ArgoCD namespace (correct!)
spec:
  destination:
    namespace: llmops-dev        # ← Target namespace for deployments
```

### 6.1 Apply ArgoCD Applications (Automated)

```bash
# Navigate to setup scripts
cd enable-llmops-argo-ocppipelines/setup_scripts

# Make script executable
chmod +x apply-argocd-apps.sh

# Run the script
./apply-argocd-apps.sh
```

**Expected output:**
```
==========================================
Applying ArgoCD Applications
==========================================

✅ Logged in as: your-username

Applying dev application...
✅ Dev application created

Applying staging application...
✅ Staging application created

Applying production application...
✅ Production application created

==========================================
ArgoCD Applications Status
==========================================

NAME                SYNC STATUS   HEALTH STATUS
llmops-dev          OutOfSync     Missing
llmops-staging      OutOfSync     Missing
llmops-production   OutOfSync     Missing
```

**Note:** `OutOfSync` and `Missing` are expected at this point - the applications haven't synced yet.

### 6.2 Apply ArgoCD Applications (Manual)

```bash
# Apply all three applications
oc apply -f argocd-apps/dev-application.yaml
oc apply -f argocd-apps/staging-application.yaml
oc apply -f argocd-apps/production-application.yaml

# Verify applications were created
oc get applications -n openshift-gitops
```

### 6.3 View Applications in ArgoCD UI

1. Open ArgoCD UI (from Step 4.4)
2. You should now see three applications:
   - **llmops-dev** - Status: OutOfSync
   - **llmops-staging** - Status: OutOfSync
   - **llmops-production** - Status: OutOfSync

3. Click on **llmops-dev** to see details
   - You'll see the InferenceService, ServingRuntime, and Secret resources
   - Status shows they haven't been deployed yet

---

## Step 7: Test GitOps Workflow - Dev Environment

The dev environment is configured with **auto-sync**, so it will automatically deploy when you push changes to Git.

### 7.1 Trigger Initial Sync

Since this is the first deployment, ArgoCD detected the resources but hasn't synced yet. Let's trigger the initial sync:

**Via ArgoCD UI:**
1. Click on **llmops-dev** application
2. Click **"SYNC"** button at the top
3. Click **"SYNCHRONIZE"** to confirm
4. Watch the sync progress in real-time

**Via CLI:**
```bash
# Trigger sync for dev environment
oc patch application llmops-dev -n openshift-gitops \
  --type merge \
  --patch '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'

# Or use argocd CLI (if installed)
argocd app sync llmops-dev
```

### 7.2 Monitor Deployment Progress

**Via ArgoCD UI:**
- The application view shows a tree of resources
- Watch as each resource turns green (Synced and Healthy)
- InferenceService may take 3-5 minutes to become healthy

**Via CLI:**
```bash
# Watch ArgoCD application status
oc get application llmops-dev -n openshift-gitops -w

# Watch InferenceService in target namespace
oc get inferenceservice -n llmops-dev -w

# Check pods
oc get pods -n llmops-dev
```

### 7.3 Verify Deployment

```bash
# Check InferenceService status
oc get inferenceservice dev-qwen25-05b-instruct -n llmops-dev

# Check route
oc get route dev-qwen25-05b-instruct -n llmops-dev

# Get endpoint URL
ROUTE_URL=$(oc get route dev-qwen25-05b-instruct -n llmops-dev -o jsonpath='{.spec.host}')
echo "Model endpoint: https://$ROUTE_URL/v1/models"

# Test the endpoint
curl https://$ROUTE_URL/v1/models
```

**Expected status:**
```
NAME                      READY   URL
dev-qwen25-05b-instruct   True    https://dev-qwen25-05b-instruct-llmops-dev.apps...
```

### 7.4 Test Auto-Sync with a Change

Now let's test the auto-sync feature by making a change:

```bash
# Create a feature branch
git checkout -b feature/test-auto-sync

# Make a small change to dev overlay
vim deploy_model/overlays/dev/kustomization.yaml

# Change the display name (line 19):
# Before:
#   value: "qwen2.5-0.5b-dev"
# After:
#   value: "qwen2.5-0.5b-dev-v2"

# Commit and push
git add deploy_model/overlays/dev/kustomization.yaml
git commit -m "Dev: Update display name to test auto-sync"
git push -u origin feature/test-auto-sync
```

**Create and merge Pull Request:**
1. Go to GitHub and create a Pull Request
2. Merge the PR to main branch

**Watch ArgoCD Auto-Sync:**

Within 3 minutes (default polling interval), ArgoCD will:
1. Detect the change in Git
2. Automatically sync the new configuration
3. Update the InferenceService

**Monitor in ArgoCD UI:**
- Go to **llmops-dev** application
- You'll see "Syncing" status
- Resources will update automatically
- Status returns to "Synced" and "Healthy"

**Monitor via CLI:**
```bash
# Watch application status
oc get application llmops-dev -n openshift-gitops -w

# Watch InferenceService
oc describe inferenceservice dev-qwen25-05b-instruct -n llmops-dev | grep "display-name"
# Should show: qwen2.5-0.5b-dev-v2
```

**Success!** You've just experienced GitOps in action - no manual `oc apply`, no GitHub Actions, just Git as the source of truth.

### 7.5 Adjust ArgoCD Polling Interval (Optional)

By default, ArgoCD polls Git repositories every **3 minutes**. You can change this to sync faster or slower.

**Important:** In OpenShift GitOps, the `argocd-cm` ConfigMap is managed by the operator and will be overwritten if you edit it directly. You must configure settings through the **ArgoCD custom resource** instead.

**Change Global Polling Interval:**

```bash
# Edit the ArgoCD custom resource (not the ConfigMap)
oc edit argocd openshift-gitops -n openshift-gitops
```

Add or modify the `repo` section under `spec`:

```yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  # ... existing fields ...
  
  # Add this section to change polling interval
  repo:
    env:
      - name: ARGOCD_RECONCILIATION_TIMEOUT
        value: "60s"  # Change from default 180s (3 minutes) to 60s (1 minute)
```

Save the file. The operator will automatically update the ArgoCD ConfigMap and restart the necessary components.

**Verify the change:**

```bash
# Check if the setting was applied
oc get argocd openshift-gitops -n openshift-gitops -o yaml | grep -A 5 "repo:"

# Watch the controller restart (if needed)
oc get pods -n openshift-gitops -w
```

**Alternative: Use Webhooks for Instant Sync (Recommended)**

Instead of polling, configure GitHub webhooks for instant notifications:

```bash
# Get your ArgoCD webhook URL
ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
echo "Webhook URL: https://$ARGOCD_URL/api/webhook"
```

**Configure in GitHub:**
1. Go to your repository: `https://github.com/YOUR_USERNAME/YOUR_REPO`
2. Click **Settings** → **Webhooks** → **Add webhook**
3. **Payload URL**: `https://<argocd-url>/api/webhook`
4. **Content type**: `application/json`
5. **Events**: Select "Just the push event"
6. Click **Add webhook**

With webhooks, ArgoCD syncs **immediately** when you push to GitHub (no polling delay).

**Force Immediate Sync (Without Waiting):**

If you don't want to wait for the polling interval:

```bash
# Force ArgoCD to refresh and sync immediately
oc patch application.argoproj.io llmops-dev -n openshift-gitops --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Or use ArgoCD CLI
argocd app sync llmops-dev
```

---

## Step 8: Test Manual Sync - Staging Environment

Staging and production environments require **manual approval** before syncing.

### 8.1 Make Changes to Staging Overlay

```bash
# Create feature branch for staging
git checkout main
git pull
git checkout -b feature/deploy-to-staging

# Make a change to staging overlay
vim deploy_model/overlays/staging/kustomization.yaml

# Change CPU limit (line 30):
# Before:
#   value: "3"
# After:
#   value: "4"

# Commit and push
git add deploy_model/overlays/staging/kustomization.yaml
git commit -m "Staging: Increase CPU limit to 4 cores"
git push -u origin feature/deploy-to-staging
```

**Create and merge Pull Request on GitHub**

### 8.2 ArgoCD Detects Change but Doesn't Auto-Deploy

After merging to main:

**Via ArgoCD UI:**
1. Go to **llmops-staging** application
2. You'll see status: **OutOfSync**
3. The UI shows what changed (yellow indicator)
4. But it does NOT automatically sync

**Via CLI:**
```bash
# Check application status
oc get application llmops-staging -n openshift-gitops

# Should show: SYNC STATUS = OutOfSync
```

This is the key difference - **manual approval required**.

### 8.3 Review Changes in ArgoCD UI

1. Click on **llmops-staging** application
2. Click **"APP DIFF"** button to see what changed
3. Review the differences:
   - CPU limit changed from "3" to "4"
4. This gives you a chance to review before deploying

### 8.4 Manually Sync Staging

**Via ArgoCD UI:**
1. Click **"SYNC"** button
2. Review the resources that will be synced
3. Click **"SYNCHRONIZE"** to approve
4. Watch the deployment progress

**Via CLI:**
```bash
# Manually trigger sync
argocd app sync llmops-staging

# Or using oc
oc patch application llmops-staging -n openshift-gitops \
  --type merge \
  --patch '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'
```

### 8.5 Verify Staging Deployment

```bash
# Check InferenceService
oc get inferenceservice staging-qwen25-05b-instruct -n llmops-staging

# Verify CPU limit was updated
oc describe inferenceservice staging-qwen25-05b-instruct -n llmops-staging | grep -A 5 "Limits"
# Should show: cpu: 4

# Check route
oc get route staging-qwen25-05b-instruct -n llmops-staging
```

---

## Step 9: Production Deployment Workflow

Production follows the same manual sync pattern as staging, but with additional safeguards.

### 9.1 Progressive Rollout Pattern

**Recommended workflow:**
```
1. Develop & Test (Dev)
   ├─ Push changes to Git
   ├─ ArgoCD auto-syncs to dev
   └─ Validate in dev environment

2. Validate (Staging)
   ├─ Update staging overlay
   ├─ Push to Git
   ├─ ArgoCD detects change (OutOfSync)
   ├─ Review changes in ArgoCD UI
   ├─ Manually sync via ArgoCD
   └─ Run integration tests

3. Production Release
   ├─ Update production overlay
   ├─ Create Pull Request (require team review)
   ├─ After approval, merge to main
   ├─ ArgoCD detects change (OutOfSync)
   ├─ Review changes in ArgoCD UI
   ├─ Manually sync via ArgoCD
   └─ Monitor production deployment
```

### 9.2 Deploy to Production

```bash
# Create production branch
git checkout main
git pull
git checkout -b feature/production-release-v1

# Make changes to production overlay
vim deploy_model/overlays/production/kustomization.yaml

# Example: Update display name for new version
# Change line 19:
# Before:
#   value: "qwen2.5-0.5b-production"
# After:
#   value: "qwen2.5-0.5b-production-v1.0"

# Commit and push
git add deploy_model/overlays/production/kustomization.yaml
git commit -m "Production: Deploy v1.0 release"
git push -u origin feature/production-release-v1
```

**Create Pull Request on GitHub:**
1. Add detailed description of changes
2. Request review from team members
3. Add production deployment checklist
4. After approval, merge to main

### 9.3 Review Production Changes in ArgoCD

1. Open ArgoCD UI
2. Go to **llmops-production** application
3. Status shows: **OutOfSync**
4. Click **"APP DIFF"** to review all changes
5. Verify the changes are correct
6. Check that staging validation passed

### 9.4 Manually Sync Production

**Via ArgoCD UI:**
1. Click **"SYNC"** button
2. **IMPORTANT:** Review one more time
3. Click **"SYNCHRONIZE"**
4. Monitor deployment closely

**Via CLI:**
```bash
# Manually sync production
argocd app sync llmops-production

# Watch deployment
oc get inferenceservice -n llmops-prod -w
```

### 9.5 Verify Production Deployment

```bash
# Check InferenceService status
oc get inferenceservice prod-qwen25-05b-instruct -n llmops-prod

# Check all replicas are healthy
oc get pods -n llmops-prod

# Test endpoint
PROD_URL=$(oc get route prod-qwen25-05b-instruct -n llmops-prod -o jsonpath='{.spec.host}')
curl https://$PROD_URL/v1/models

# Monitor for 10-15 minutes
watch -n 10 'oc get inferenceservice -n llmops-prod'
```

### 9.6 Rollback Procedure (if needed)

If something goes wrong in production:

**Via ArgoCD UI:**
1. Go to **llmops-production** application
2. Click **"HISTORY AND ROLLBACK"**
3. Select the previous successful deployment
4. Click **"ROLLBACK"**
5. ArgoCD will revert to the previous Git commit

**Via Git:**
```bash
# Identify the last good commit
git log --oneline deploy_model/overlays/production/

# Create rollback branch
git checkout -b hotfix/rollback-production

# Revert to previous version
git revert <bad-commit-sha>

# Push and merge (emergency fast-track)
git push -u origin hotfix/rollback-production
# Merge PR immediately

# Manually sync in ArgoCD UI
```

---

## Step 10: Monitor with ArgoCD Dashboard

### 10.1 ArgoCD Dashboard Overview

**Access the dashboard:**
```bash
# Get ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

**Main Dashboard Features:**
- **Applications List:** Shows all three environments
- **Sync Status:** Synced, OutOfSync, Unknown
- **Health Status:** Healthy, Progressing, Degraded, Missing
- **Last Sync:** Timestamp of last successful sync

### 10.2 Application Details View

Click on any application to see:

**Resource Tree:**
- Visual representation of all Kubernetes resources
- Color-coded status (green = healthy, yellow = progressing, red = failed)
- Shows relationships between resources

**App Details:**
- Git repository and branch
- Target namespace
- Sync policy (auto vs manual)
- Last sync result

**Events:**
- Recent sync operations
- Errors and warnings
- Resource changes

### 10.3 Monitoring Sync Status

**Via ArgoCD UI:**
1. Main dashboard shows all applications at a glance
2. Green checkmark = Synced and Healthy
3. Yellow warning = OutOfSync (manual sync needed)
4. Red X = Sync failed or unhealthy

**Via CLI:**
```bash
# List all applications
oc get applications -n openshift-gitops

# Watch for changes
oc get applications -n openshift-gitops -w

# Get detailed status
oc describe application llmops-dev -n openshift-gitops
```

### 10.4 View Application Diff

Before syncing, always review what changed:

**Via ArgoCD UI:**
1. Click on application
2. Click **"APP DIFF"** button
3. See side-by-side comparison of Git vs Cluster state
4. Review all changes before approving

**Via CLI:**
```bash
# Show diff for staging
argocd app diff llmops-staging
```

### 10.5 View Sync History

**Via ArgoCD UI:**
1. Click on application
2. Click **"HISTORY AND ROLLBACK"** tab
3. See all previous sync operations
4. Each entry shows:
   - Timestamp
   - Git commit SHA
   - Sync status
   - Option to rollback

### 10.6 Monitor All Environments

**Dashboard view:**
```bash
# Get status of all environments
oc get applications -n openshift-gitops -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status,\
NAMESPACE:.spec.destination.namespace

# Example output:
# NAME                SYNC      HEALTH    NAMESPACE
# llmops-dev          Synced    Healthy   llmops-dev
# llmops-staging      OutOfSync Healthy   llmops-staging
# llmops-production   Synced    Healthy   llmops-prod
```

**Check InferenceServices across all environments:**
```bash
# View all InferenceServices
oc get inferenceservice --all-namespaces | grep llmops

# Check routes
oc get route --all-namespaces | grep llmops
```

### 10.7 Set Up Notifications (Optional)

ArgoCD can send notifications on sync events:

```bash
# Configure Slack notifications (example)
# Edit ArgoCD ConfigMap
oc edit configmap argocd-notifications-cm -n openshift-gitops

# Add Slack webhook URL and configure triggers
# See: https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/
```

---

## Troubleshooting

### Issue 1: ArgoCD Application Shows OutOfSync but No Changes in Git

**Problem:** Application status is OutOfSync even though Git hasn't changed.

**Cause:** Someone manually modified resources in the cluster (drift).

**Solution:**

```bash
# View the diff to see what changed
argocd app diff llmops-dev

# Option 1: Sync to restore Git state (recommended)
argocd app sync llmops-dev

# Option 2: If the cluster change was intentional, update Git
# Edit the overlay files to match cluster state
# Commit and push to Git
```

**Prevention:** Enable `selfHeal: true` in Application spec (already enabled for dev).

### Issue 2: ArgoCD Cannot Access Git Repository

**Problem:** Application shows "ComparisonError" - cannot fetch from Git.

**Cause:** 
- Repository is private and ArgoCD doesn't have access
- Repository URL is incorrect

**Solution for Private Repository:**

```bash
# Create a Git credential secret
oc create secret generic git-credentials \
  -n openshift-gitops \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN

# Label the secret so ArgoCD uses it
oc label secret git-credentials \
  -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository

# Or use SSH key
oc create secret generic git-ssh-key \
  -n openshift-gitops \
  --from-file=sshPrivateKey=/path/to/id_rsa

oc label secret git-ssh-key \
  -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository
```

**Solution for Incorrect URL:**

```bash
# Update the Application with correct URL
oc edit application llmops-dev -n openshift-gitops

# Or update the YAML file and reapply
vim argocd-apps/dev-application.yaml
oc apply -f argocd-apps/dev-application.yaml
```

### Issue 3: Application Synced but InferenceService Not Healthy

**Problem:** ArgoCD shows "Synced" but InferenceService is not ready.

**Solution:**

```bash
# Check InferenceService status
oc describe inferenceservice dev-qwen25-05b-instruct -n llmops-dev

# Check events
oc get events -n llmops-dev --sort-by='.lastTimestamp' | tail -20

# Check pods
oc get pods -n llmops-dev

# If pod is not starting, check logs
POD=$(oc get pods -n llmops-dev -o jsonpath='{.items[0].metadata.name}')
oc logs $POD -n llmops-dev

# Common issues:
# - Insufficient GPU resources
# - Image pull errors
# - Configuration errors
```

### Issue 4: Auto-Sync Not Working for Dev Environment

**Problem:** Pushed changes to Git but dev environment didn't auto-sync.

**Cause:** 
- ArgoCD polling interval (default 3 minutes)
- Sync policy not configured correctly

**Solution:**

```bash
# Check Application sync policy
oc get application llmops-dev -n openshift-gitops -o yaml | grep -A 10 syncPolicy

# Should show:
#   syncPolicy:
#     automated:
#       prune: true
#       selfHeal: true

# If not, update the Application
oc apply -f argocd-apps/dev-application.yaml

# Manually trigger sync to test
argocd app sync llmops-dev

# Check ArgoCD logs
oc logs -n openshift-gitops deployment/openshift-gitops-repo-server
```

### Issue 5: Sync Fails with "PermissionDenied" Error

**Problem:** ArgoCD cannot create resources in target namespace.

**Solution:**

```bash
# Verify ArgoCD has permissions
ARGOCD_SA="openshift-gitops-argocd-application-controller"

for NS in llmops-dev llmops-staging llmops-prod; do
  echo "Checking $NS..."
  oc auth can-i create inferenceservices -n $NS \
    --as=system:serviceaccount:openshift-gitops:$ARGOCD_SA
done

# If any return "no", recreate the RoleBinding
oc create rolebinding argocd-admin \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:$ARGOCD_SA \
  -n llmops-dev
```

### Issue 6: Kustomize Build Fails

**Problem:** ArgoCD shows "ComparisonError: kustomize build failed".

**Solution:**

```bash
# Test kustomize build locally
kustomize build deploy_model/overlays/dev/

# Common issues:
# - Incorrect indentation in YAML
# - Missing resources in base
# - Invalid patch syntax

# Validate YAML syntax
yamllint deploy_model/overlays/dev/kustomization.yaml

# Check that base files exist
ls -la deploy_model/base/

# Test with oc
oc kustomize deploy_model/overlays/dev/
```

### Issue 7: Cannot Access ArgoCD Dashboard

**Problem:** ArgoCD route returns 404 or connection refused.

**Solution:**

```bash
# Check ArgoCD Server is running
oc get pods -n openshift-gitops | grep server

# Check route exists
oc get route openshift-gitops-server -n openshift-gitops

# Check route is properly configured
oc describe route openshift-gitops-server -n openshift-gitops

# If route is missing, it may have been deleted
# Restart the operator to recreate it
oc delete pod -n openshift-operators -l name=openshift-gitops-operator
```

### Issue 8: Forgot ArgoCD Admin Password

**Solution:**

```bash
# Retrieve admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d
echo ""

# Or reset the password
oc delete secret openshift-gitops-cluster -n openshift-gitops
# Wait for ArgoCD to regenerate it
sleep 10
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d
```

### Issue 9: GPU Not Available

**Problem:** Pod is pending with "Insufficient nvidia.com/gpu".

**Solution:**

```bash
# Check GPU availability
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU allocatable resources
GPU_NODE=$(oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}')
oc describe node $GPU_NODE | grep nvidia.com/gpu

# If using time-slicing, update resource name
# Edit base inferenceservice.yaml
vim deploy_model/base/inferenceservice.yaml
# Change nvidia.com/gpu to nvidia.com/gpu.shared

# Commit and push
git add deploy_model/base/inferenceservice.yaml
git commit -m "Use GPU time-slicing resource"
git push

# ArgoCD will auto-sync (dev) or show OutOfSync (staging/prod)
```

### Issue 10: Want to Disable Auto-Sync for Dev

**Problem:** Need to test changes in dev before auto-deploying.

**Solution:**

```bash
# Edit dev application
vim argocd-apps/dev-application.yaml

# Remove or comment out the automated section:
# syncPolicy:
#   # automated:
#   #   prune: true
#   #   selfHeal: true
#   syncOptions:
#     - CreateNamespace=true

# Apply the change
oc apply -f argocd-apps/dev-application.yaml

# Now dev will require manual sync like staging/prod
```

---

## Best Practices

### 1. GitOps Workflow

✅ **Git is the single source of truth** - All changes go through Git

✅ **Use Pull Requests** for all environments (including dev)

✅ **Never use `oc apply` directly** - Let ArgoCD manage deployments

✅ **Review diffs before syncing** - Use ArgoCD UI to see what changed

✅ **Monitor sync status** - Check ArgoCD dashboard regularly

### 2. Progressive Rollout

✅ **Always test in dev first** - Auto-sync makes this easy

✅ **Validate in staging** before production - Manual sync provides control

✅ **Monitor each stage** before proceeding

❌ **Never skip environments** - Don't go directly from dev to prod

### 3. Change Management

✅ **Use descriptive commit messages** - They appear in ArgoCD history

✅ **Tag releases** - Makes rollback easier
```bash
git tag -a v1.0.0 -m "Production release v1.0.0"
git push origin v1.0.0
```

✅ **Document breaking changes** in PR descriptions

✅ **Keep sync history** - Don't delete old commits

### 4. Security

✅ **No cluster credentials in Git** - ArgoCD runs inside cluster

✅ **Use RBAC** - Limit who can sync production

✅ **Audit trail** - ArgoCD logs all sync operations

✅ **Review before sync** - Especially for production

### 5. Monitoring

✅ **Check ArgoCD dashboard daily** - Catch drift early

✅ **Set up notifications** - Get alerts on sync failures

✅ **Monitor InferenceService health** - Not just sync status

✅ **Test endpoints** after each deployment

### 6. Troubleshooting

✅ **Check ArgoCD UI first** - Most issues are visible there

✅ **Use APP DIFF** to understand changes

✅ **Check ArgoCD logs** for sync errors

✅ **Verify Git repository access** if comparison fails

---

## Comparison: GitHub Actions vs ArgoCD GitOps

### What We Had (GitHub Actions)

**Pros:**
- Simple to understand (push-based)
- Familiar CI/CD pattern
- Easy to set up initially

**Cons:**
- No state tracking (just applies and hopes)
- No drift detection
- Cluster credentials stored in GitHub
- No visibility after deployment
- Manual rollback process
- Runs outside cluster (security concern)

### What We Have Now (ArgoCD GitOps)

**Pros:**
- True GitOps (Git is source of truth)
- Continuous state reconciliation
- Automatic drift detection and correction
- No cluster credentials outside cluster
- Rich UI for monitoring and management
- Easy rollback via UI or Git
- Runs inside cluster (more secure)
- Audit trail of all changes
- Manual approval for production

**Cons:**
- Slightly more complex initial setup
- Requires understanding of GitOps concepts
- Need to learn ArgoCD UI

---

## Next Steps: Adding OpenShift Pipelines (Phase 2)

Once you're comfortable with ArgoCD, you can add OpenShift Pipelines for:

**Pre-Deployment Validation:**
- Kustomize build validation
- YAML linting
- Security scanning
- Custom tests

**Workflow:**
```
Developer → Git Push → Tekton Pipeline (validate) → Git Repo
                                                        |
                                        [ArgoCD watches and deploys]
```

**Implementation:**
- Create Tekton Pipeline for validation
- Trigger on Pull Request
- Block merge if validation fails
- ArgoCD deploys only after merge

This will be covered in a future guide.

---

## Summary Checklist

Use this checklist to verify your GitOps setup is complete:

### Operators
- ✅ OpenShift GitOps Operator installed
- ✅ OpenShift Pipelines Operator installed
- ✅ ArgoCD Server running in openshift-gitops namespace

### Namespaces
- ✅ Three namespaces created: llmops-dev, llmops-staging, llmops-prod
- ✅ ArgoCD has admin permissions in all three namespaces

### Git Repository
- ✅ GitHub repository created (public)
- ✅ Code pushed to GitHub
- ✅ ArgoCD Application manifests updated with correct repo URL

### ArgoCD Applications
- ✅ Three applications created in openshift-gitops namespace
- ✅ Dev configured with auto-sync
- ✅ Staging configured with manual sync
- ✅ Production configured with manual sync
- ✅ All applications showing in ArgoCD UI

### Initial Deployment
- ✅ Dev environment synced and healthy
- ✅ Staging environment synced and healthy (optional)
- ✅ Production environment synced and healthy (optional)
- ✅ All InferenceServices showing Ready=True
- ✅ External routes working

### GitOps Testing
- ✅ Tested auto-sync in dev environment
- ✅ Tested manual sync in staging environment
- ✅ Tested manual sync in production environment
- ✅ Verified drift detection
- ✅ Tested rollback procedure

### Monitoring
- ✅ Can access ArgoCD dashboard
- ✅ Can view application status
- ✅ Can view resource tree
- ✅ Can view sync history
- ✅ Can review diffs before syncing

---

## Reference

**Documentation:**
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [Kustomize Documentation](https://kustomize.io/)
- [OpenShift Pipelines Documentation](https://docs.openshift.com/container-platform/latest/cicd/pipelines/understanding-openshift-pipelines.html)
- [KServe Documentation](https://kserve.github.io/website/)

**Tools:**
- [oc CLI](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- [argocd CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/)

**Related Files:**
- [README.md](./README.md) - Project overview
- [setup-argocd.sh](./setup_scripts/setup-argocd.sh) - Automated setup script
- [apply-argocd-apps.sh](./setup_scripts/apply-argocd-apps.sh) - Apply ArgoCD applications

---

**Created:** 2025-12-29
**Last Updated:** 2025-12-29
**Target:** OpenShift 4.x with Red Hat OpenShift AI (RHOAI), KServe, and OpenShift GitOps
**Demo Model:** Qwen 2.5 0.5B Instruct
