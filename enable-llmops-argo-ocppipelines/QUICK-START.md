# Quick Start Guide - GitOps LLMOps with ArgoCD

This is a condensed version for quick setup. For detailed explanations, see [step-by-step-guide.md](./step-by-step-guide.md).

## Prerequisites

- OpenShift cluster with RHOAI and KServe
- Cluster admin access
- `oc` CLI installed

## 5-Minute Setup

### 1. Install Operators

```bash
# Login to OpenShift
oc login https://YOUR_CLUSTER_URL

# Install OpenShift GitOps (via Console or CLI)
# Console: Operators → OperatorHub → Search "OpenShift GitOps" → Install

# Wait for ArgoCD to be ready
oc get pods -n openshift-gitops
```

### 2. Run Setup Script

```bash
cd enable-llmops-argo-ocppipelines/setup_scripts
chmod +x setup-argocd.sh
./setup-argocd.sh
```

**Save the ArgoCD URL and password from the output.**

### 3. Update Git Repository URL

```bash
# Replace with your GitHub username and repo name
YOUR_USERNAME="your-github-username"
YOUR_REPO="your-repo-name"

cd ..
sed -i.bak "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|https://github.com/$YOUR_USERNAME/$YOUR_REPO.git|g" argocd-apps/*.yaml

git add argocd-apps/*.yaml
git commit -m "Update ArgoCD apps with correct Git repo URL"
```

### 4. Push to GitHub

```bash
git init
git add .
git commit -m "Initial commit: GitOps LLMOps"
git remote add origin https://github.com/$YOUR_USERNAME/$YOUR_REPO.git
git branch -M main
git push -u origin main
```

### 5. Deploy ArgoCD Applications

```bash
cd setup_scripts
chmod +x apply-argocd-apps.sh
./apply-argocd-apps.sh
```

### 6. Access ArgoCD Dashboard

```bash
# Get URL and password
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
```

Open the URL, login with `admin` and the password.

### 7. Sync Dev Environment

In ArgoCD UI:
1. Click on **llmops-dev** application
2. Click **SYNC** button
3. Click **SYNCHRONIZE**
4. Watch deployment progress

After 3-5 minutes, the model will be deployed and healthy.

---

## Usage

### Make Changes to Dev (Auto-Sync)

```bash
git checkout -b feature/my-changes
vim deploy_model/overlays/dev/kustomization.yaml
# Make changes
git add deploy_model/overlays/dev/
git commit -m "Dev: My changes"
git push -u origin feature/my-changes
# Create and merge PR on GitHub
# ArgoCD auto-syncs within 3 minutes
```

### Make Changes to Staging/Production (Manual Sync)

```bash
git checkout -b feature/staging-changes
vim deploy_model/overlays/staging/kustomization.yaml
# Make changes
git add deploy_model/overlays/staging/
git commit -m "Staging: My changes"
git push -u origin feature/staging-changes
# Create and merge PR on GitHub
# Go to ArgoCD UI → llmops-staging → Review changes → Click SYNC
```

---

## Key Commands

```bash
# View all applications
oc get applications -n openshift-gitops

# Watch application status
oc get application llmops-dev -n openshift-gitops -w

# Check InferenceServices
oc get inferenceservice --all-namespaces | grep llmops

# Check routes
oc get route --all-namespaces | grep llmops

# Get ArgoCD password
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
```

---

## Troubleshooting

**Application shows OutOfSync:**
- Go to ArgoCD UI → Click application → Click SYNC

**Cannot access ArgoCD UI:**
```bash
oc get pods -n openshift-gitops
oc get route openshift-gitops-server -n openshift-gitops
```

**InferenceService not healthy:**
```bash
oc describe inferenceservice dev-qwen25-05b-instruct -n llmops-dev
oc get pods -n llmops-dev
```

---

## What's Different from GitHub Actions?

| GitHub Actions | ArgoCD GitOps |
|----------------|---------------|
| Push to cluster | Pull from Git |
| No state tracking | Continuous reconciliation |
| Credentials in GitHub | Credentials in cluster |
| GitHub Actions logs | ArgoCD dashboard |
| Manual rollback | One-click rollback |

---

## Next Steps

- Read [step-by-step-guide.md](./step-by-step-guide.md) for detailed explanations
- Explore ArgoCD UI features
- Test rollback procedure
- Add OpenShift Pipelines for validation (Phase 2)

---

**For detailed documentation, see [README.md](./README.md) and [step-by-step-guide.md](./step-by-step-guide.md)**

