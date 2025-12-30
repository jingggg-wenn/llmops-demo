# GitOps LLMOps with ArgoCD and OpenShift Pipelines

This repository demonstrates a production-ready LLMOps workflow using **ArgoCD for GitOps deployment** and **Kustomize overlays** to automatically deploy AI models to OpenShift with environment-specific configurations.

## Overview

This implementation showcases:
- **True GitOps** with ArgoCD continuously monitoring Git and syncing to cluster
- **Pull-based deployment** (ArgoCD pulls from Git, not push from CI/CD)
- **Environment-based deployments** using Kustomize overlays (dev, staging, production)
- **Automated drift detection** and self-healing
- **Manual approval gates** for staging and production
- **Rich visualization** via ArgoCD dashboard
- **Progressive rollout strategy** from dev → staging → production
- **No cluster credentials outside cluster** (more secure than GitHub Actions)

## Architecture

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

**Technology Stack:**
- **Model**: Qwen 2.5 0.5B Instruct (vLLM inference)
- **Platform**: Red Hat OpenShift AI with KServe
- **GitOps**: ArgoCD (OpenShift GitOps Operator)
- **CI/CD**: OpenShift Pipelines (Tekton) - Phase 2
- **Configuration Management**: Kustomize with overlays
- **Version Control**: Git as single source of truth

---

## Key Differences from GitHub Actions Approach

| Aspect | GitHub Actions (Old) | ArgoCD GitOps (New) |
|--------|---------------------|---------------------|
| **Deployment Model** | Push (GH Actions pushes to cluster) | Pull (ArgoCD pulls from Git) |
| **Where it runs** | GitHub infrastructure | Inside OpenShift cluster |
| **State tracking** | None (fire and forget) | Continuous reconciliation |
| **Drift detection** | None | Automatic detection and correction |
| **Rollback** | Manual git revert + re-run | ArgoCD UI rollback or git revert |
| **Visibility** | GitHub Actions logs | ArgoCD dashboard with real-time status |
| **Secrets** | GitHub Secrets (cluster token) | No cluster credentials in Git |
| **Security** | Token stored externally | ArgoCD runs inside cluster |
| **Approval gates** | Manual workflow dispatch | Built-in manual sync for prod |

---

## Repository Structure

```
.
├── argocd-apps/
│   ├── dev-application.yaml          # ArgoCD Application for dev (auto-sync)
│   ├── staging-application.yaml      # ArgoCD Application for staging (manual)
│   └── production-application.yaml   # ArgoCD Application for production (manual)
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
├── setup_scripts/                    # Setup automation
│   ├── setup-argocd.sh               # Automated ArgoCD setup
│   └── apply-argocd-apps.sh          # Apply ArgoCD applications
├── step-by-step-guide.md             # Detailed setup guide
└── README.md                         # This file
```

---

## Environment Configurations

This demo uses **Kustomize overlays** to manage three environments with different resource allocations:

| Environment | CPU Limit | Memory Limit | Replicas | Sync Policy | Purpose |
|-------------|-----------|--------------|----------|-------------|---------|
| **Dev** | 2 cores | 6Gi | 1 (fixed) | Auto-sync | Development & testing |
| **Staging** | 3 cores | 8Gi | 1-2 (autoscaling) | Manual sync | Pre-production validation |
| **Production** | 4 cores | 12Gi | 2-3 (autoscaling + HA) | Manual sync | Production workloads |

**Name Prefixes:**
- Dev: `dev-qwen25-05b-instruct`
- Staging: `staging-qwen25-05b-instruct`
- Production: `prod-qwen25-05b-instruct`

**Sync Policies:**
- **Dev**: Auto-sync enabled - ArgoCD automatically deploys when Git changes
- **Staging**: Manual sync required - Review changes before deploying
- **Production**: Manual sync required - Requires explicit approval

---

## Prerequisites

- OpenShift cluster with Red Hat OpenShift AI installed
- KServe enabled on the cluster
- GPU nodes available (with NVIDIA GPU operator)
- OpenShift GitOps Operator (ArgoCD)
- OpenShift Pipelines Operator (Tekton) - for Phase 2
- GitHub account
- `oc` CLI installed locally
- `kustomize` installed (optional, for local testing)

---

## Quick Start

### 1. Install Operators

Install via OpenShift Console → OperatorHub:
- **Red Hat OpenShift GitOps** (provides ArgoCD)
- **Red Hat OpenShift Pipelines** (provides Tekton)

Or via CLI:
```bash
# Install OpenShift GitOps
oc apply -f - <<EOF
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

# Wait for installation
oc get pods -n openshift-gitops
```

### 2. Run Setup Script

```bash
# Login to OpenShift
oc login https://YOUR_CLUSTER_URL

# Navigate to setup scripts
cd setup_scripts

# Run automated setup
chmod +x setup-argocd.sh
./setup-argocd.sh
```

This script:
- Creates namespaces: `llmops-dev`, `llmops-staging`, `llmops-prod`
- Configures ArgoCD permissions
- Provides ArgoCD URL and admin password

### 3. Update Git Repository URL

```bash
# Update ArgoCD applications with your Git repo
YOUR_USERNAME="your-github-username"
YOUR_REPO="your-repo-name"

sed -i.bak "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|https://github.com/$YOUR_USERNAME/$YOUR_REPO.git|g" argocd-apps/*.yaml
```

### 4. Push to GitHub

```bash
# Initialize git and push
git init
git add .
git commit -m "Initial commit: GitOps LLMOps with ArgoCD"
git remote add origin https://github.com/$YOUR_USERNAME/$YOUR_REPO.git
git branch -M main
git push -u origin main
```

### 5. Deploy ArgoCD Applications

```bash
# Apply all three applications
cd setup_scripts
chmod +x apply-argocd-apps.sh
./apply-argocd-apps.sh
```

### 6. Access ArgoCD Dashboard

```bash
# Get ArgoCD URL and password
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
```

Open the URL in your browser and login with username `admin` and the password.

### 7. Sync Applications

**Dev (auto-sync):**
- Just push changes to Git
- ArgoCD automatically syncs within 3 minutes

**Staging/Production (manual sync):**
1. Push changes to Git
2. ArgoCD detects changes (shows OutOfSync)
3. Review changes in ArgoCD UI
4. Click "SYNC" to deploy

---

## Usage

### GitOps Workflow

The workflow is simple: **Git is the source of truth**.

```
1. Make changes to Kustomize overlays
2. Commit and push to Git
3. ArgoCD detects changes
4. Dev: Auto-deploys
   Staging/Prod: Shows OutOfSync, requires manual approval
5. Review changes in ArgoCD UI
6. Manually sync staging/production
7. Monitor deployment in ArgoCD dashboard
```

### Deploy to Dev (Auto-Sync)

```bash
# Create feature branch
git checkout -b feature/dev-changes

# Edit dev overlay
vim deploy_model/overlays/dev/kustomization.yaml

# Make changes (e.g., increase CPU limit)

# Commit and push
git add deploy_model/overlays/dev/
git commit -m "Dev: Increase CPU to 3 cores"
git push -u origin feature/dev-changes

# Create and merge Pull Request on GitHub

# ArgoCD automatically syncs within 3 minutes
# Watch in ArgoCD UI or CLI:
oc get application llmops-dev -n openshift-gitops -w
```

### Deploy to Staging (Manual Sync)

```bash
# Create feature branch
git checkout -b feature/staging-changes

# Edit staging overlay
vim deploy_model/overlays/staging/kustomization.yaml

# Commit and push
git add deploy_model/overlays/staging/
git commit -m "Staging: Update configuration"
git push -u origin feature/staging-changes

# Create and merge Pull Request

# ArgoCD detects change but does NOT auto-deploy
# Go to ArgoCD UI:
# 1. Click on llmops-staging application
# 2. Review changes (APP DIFF button)
# 3. Click SYNC to deploy
# 4. Monitor deployment progress
```

### Deploy to Production (Manual Sync with Review)

```bash
# Create feature branch
git checkout -b feature/production-release

# Edit production overlay
vim deploy_model/overlays/production/kustomization.yaml

# Commit and push
git add deploy_model/overlays/production/
git commit -m "Production: Deploy v1.0"
git push -u origin feature/production-release

# Create Pull Request with detailed description
# Request review from team members
# After approval, merge to main

# In ArgoCD UI:
# 1. Click on llmops-production application
# 2. Status shows OutOfSync
# 3. Review changes carefully (APP DIFF)
# 4. Click SYNC to deploy
# 5. Monitor closely
```

---

## Monitoring with ArgoCD

### ArgoCD Dashboard Features

**Application List View:**
- See all three environments at a glance
- Sync status: Synced, OutOfSync, Unknown
- Health status: Healthy, Progressing, Degraded
- Last sync timestamp

**Application Details View:**
- Resource tree visualization
- Color-coded status (green = healthy, yellow = progressing, red = failed)
- Real-time updates

**App Diff:**
- Compare Git state vs Cluster state
- See exactly what changed
- Review before syncing

**History and Rollback:**
- View all previous sync operations
- See Git commit SHA for each deployment
- One-click rollback to previous version

### CLI Monitoring

```bash
# List all applications
oc get applications -n openshift-gitops

# Watch application status
oc get application llmops-dev -n openshift-gitops -w

# View application details
oc describe application llmops-dev -n openshift-gitops

# Check InferenceServices
oc get inferenceservice --all-namespaces | grep llmops

# Check routes
oc get route --all-namespaces | grep llmops
```

---

## Rollback Procedure

### Via ArgoCD UI (Recommended)

1. Go to application in ArgoCD UI
2. Click **"HISTORY AND ROLLBACK"** tab
3. Select previous successful deployment
4. Click **"ROLLBACK"**
5. ArgoCD reverts to previous Git commit

### Via Git

```bash
# Identify last good commit
git log --oneline deploy_model/overlays/production/

# Create rollback branch
git checkout -b hotfix/rollback-production

# Revert to previous version
git revert <bad-commit-sha>

# Push and merge
git push -u origin hotfix/rollback-production
# Merge PR immediately

# Manually sync in ArgoCD UI
```

---

## Drift Detection and Self-Healing

One of the key benefits of GitOps with ArgoCD:

**Scenario:** Someone manually edits a resource in the cluster

```bash
# Manually change CPU limit (not recommended!)
oc patch inferenceservice dev-qwen25-05b-instruct -n llmops-dev \
  --type merge \
  --patch '{"spec":{"predictor":{"model":{"resources":{"limits":{"cpu":"10"}}}}}}'
```

**What happens:**
1. ArgoCD detects drift (cluster state ≠ Git state)
2. Application shows **OutOfSync** in UI
3. For dev (with selfHeal: true), ArgoCD automatically reverts to Git state
4. For staging/prod, ArgoCD shows OutOfSync but waits for manual action

**This ensures Git is always the source of truth.**

---

## Advantages of This Approach

### Security

✅ **No cluster credentials outside cluster** - ArgoCD runs inside OpenShift
✅ **No tokens in GitHub Secrets** - More secure than GitHub Actions
✅ **RBAC integration** - Use OpenShift's native RBAC
✅ **Audit trail** - All changes tracked in Git and ArgoCD

### Reliability

✅ **Continuous reconciliation** - ArgoCD ensures cluster matches Git
✅ **Drift detection** - Alerts when cluster state diverges
✅ **Self-healing** - Automatically corrects drift (configurable)
✅ **State tracking** - Always know what's deployed where

### Visibility

✅ **Rich UI** - Visual representation of all resources
✅ **Real-time status** - See deployment progress live
✅ **Change history** - Full audit trail of deployments
✅ **Easy rollback** - One-click revert to previous version

### Developer Experience

✅ **Simple workflow** - Just push to Git
✅ **No manual oc apply** - ArgoCD handles deployment
✅ **Preview changes** - See diff before deploying
✅ **Approval gates** - Manual sync for production

---

## Troubleshooting

### Application Shows OutOfSync

**Check what changed:**
```bash
# Via CLI
argocd app diff llmops-dev

# Via UI: Click "APP DIFF" button
```

**Sync the application:**
```bash
# Via CLI
argocd app sync llmops-dev

# Via UI: Click "SYNC" button
```

### ArgoCD Cannot Access Git Repository

**For private repositories:**
```bash
# Create Git credentials secret
oc create secret generic git-credentials \
  -n openshift-gitops \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN

# Label the secret
oc label secret git-credentials \
  -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository
```

### InferenceService Not Healthy

```bash
# Check InferenceService status
oc describe inferenceservice dev-qwen25-05b-instruct -n llmops-dev

# Check pods
oc get pods -n llmops-dev

# Check logs
POD=$(oc get pods -n llmops-dev -o jsonpath='{.items[0].metadata.name}')
oc logs $POD -n llmops-dev
```

For more troubleshooting, see [step-by-step-guide.md](./step-by-step-guide.md#troubleshooting).

---

## What This GitOps Demo Showcases

✅ **True GitOps** - Git as single source of truth with continuous reconciliation

✅ **Pull-Based Deployment** - ArgoCD pulls from Git, more secure than push

✅ **Environment-Based Deployments** - Separate configs for dev/staging/prod

✅ **Automated Drift Detection** - Ensures cluster always matches Git

✅ **Manual Approval Gates** - Control production deployments

✅ **Rich Visualization** - ArgoCD dashboard for monitoring

✅ **Easy Rollback** - One-click revert to previous version

✅ **Progressive Delivery** - Safe rollout pattern from dev → staging → production

✅ **Configuration Management** - DRY principle with Kustomize base + overlays

✅ **Reproducibility** - All configurations tracked in Git

✅ **Security** - No cluster credentials outside cluster

---

## Next Steps: Phase 2 - OpenShift Pipelines

After you're comfortable with ArgoCD, add OpenShift Pipelines for pre-deployment validation:

**Pipeline Features:**
- Kustomize build validation
- YAML linting
- Security scanning
- Custom tests
- Block PR merge if validation fails

**Workflow:**
```
Developer → Git Push → Tekton Pipeline (validate) → Git Repo
                                                        |
                                        [ArgoCD watches and deploys]
```

This will be covered in a future update.

---

## Documentation

**Detailed Setup Guide:**
- [step-by-step-guide.md](./step-by-step-guide.md) - Complete walkthrough
- [NAMESPACE-GUIDE.md](./NAMESPACE-GUIDE.md) - Understanding OpenShift GitOps namespaces

**Setup Scripts:**
- [setup-argocd.sh](./setup_scripts/setup-argocd.sh) - Automated setup
- [apply-argocd-apps.sh](./setup_scripts/apply-argocd-apps.sh) - Deploy applications

**Additional Guides:**
- [QUICK-START.md](./QUICK-START.md) - Quick reference
- [COMPARISON-GITHUBACTIONS-ARGOCD.md](./COMPARISON-GITHUBACTIONS-ARGOCD.md) - Comparison with GitHub Actions
- [IMPLEMENTATION-SUMMARY.md](./IMPLEMENTATION-SUMMARY.md) - Implementation overview

**External Resources:**
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [Kustomize Documentation](https://kustomize.io/)
- [KServe Documentation](https://kserve.github.io/website/)

---

## Model Information

**Current Model**: Qwen 2.5 0.5B Instruct
- **Source**: `quay.io/redhat-ai-services/modelcar-catalog:qwen2.5-0.5b-instruct`
- **Size**: 0.5 billion parameters
- **Inference Engine**: vLLM
- **API**: OpenAI-compatible endpoints
- **GPU Required**: 1x NVIDIA GPU

---

## Contributing

This is a demonstration project for educational purposes. Feel free to adapt it for your own LLMOps workflows.

---

## License

This is a demonstration project for educational purposes.

---

**Created:** 2024-12-29
**Last Updated:** 2024-12-29
**Target:** OpenShift 4.x with Red Hat OpenShift AI (RHOAI), KServe, and OpenShift GitOps
**Demo Model:** Qwen 2.5 0.5B Instruct
**Repository:** rhoai-env-jw/llmops-via-argocd

