# OpenShift GitOps Namespace Guide

This document clarifies the different namespaces used in the GitOps LLMOps implementation and what goes where.

## Namespace Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ OpenShift Cluster                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ openshift-gitops-operator (or openshift-operators)      │   │
│  │ Purpose: Operator Installation                          │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ Pods:                                                    │   │
│  │   - gitops-operator-controller-manager-*                │   │
│  │                                                          │   │
│  │ What it does:                                            │   │
│  │   - Manages ArgoCD installation                         │   │
│  │   - Creates openshift-gitops namespace                  │   │
│  │   - Deploys ArgoCD components                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ openshift-gitops                                        │   │
│  │ Purpose: ArgoCD Instance (YOU WORK HERE!)               │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ Pods:                                                    │   │
│  │   - openshift-gitops-server-*                           │   │
│  │   - openshift-gitops-repo-server-*                      │   │
│  │   - openshift-gitops-application-controller-*           │   │
│  │   - openshift-gitops-redis-*                            │   │
│  │                                                          │   │
│  │ Resources:                                               │   │
│  │   - Applications: llmops-dev, llmops-staging, etc.      │   │
│  │   - Secrets: openshift-gitops-cluster (admin password)  │   │
│  │   - Routes: openshift-gitops-server (ArgoCD UI)         │   │
│  │   - ConfigMaps: argocd-cm, argocd-rbac-cm               │   │
│  │                                                          │   │
│  │ What it does:                                            │   │
│  │   - Runs ArgoCD server (UI and API)                     │   │
│  │   - Stores Application definitions                      │   │
│  │   - Watches Git repositories                            │   │
│  │   - Syncs to target namespaces                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ llmops-dev                                              │   │
│  │ Purpose: Development Environment (TARGET)               │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ Resources:                                               │   │
│  │   - InferenceService: dev-qwen25-05b-instruct           │   │
│  │   - ServingRuntime: dev-qwen25-05b-instruct             │   │
│  │   - Secret: dev-qwen25-05b-instruct                     │   │
│  │   - Pods: Model inference pods                          │   │
│  │   - Routes: Model endpoints                             │   │
│  │                                                          │   │
│  │ Managed by: ArgoCD Application "llmops-dev"             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ llmops-staging                                          │   │
│  │ Purpose: Staging Environment (TARGET)                   │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ Resources: (same structure as dev)                      │   │
│  │ Managed by: ArgoCD Application "llmops-staging"         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ llmops-prod                                             │   │
│  │ Purpose: Production Environment (TARGET)                │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ Resources: (same structure as dev)                      │   │
│  │ Managed by: ArgoCD Application "llmops-production"      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Namespace Usage Guide

### When to Use Each Namespace

| Task | Namespace | Command Example |
|------|-----------|-----------------|
| Check operator status | `openshift-gitops-operator` or `openshift-operators` | `oc get pods -n openshift-gitops-operator` |
| Access ArgoCD UI | `openshift-gitops` | `oc get route -n openshift-gitops` |
| Get ArgoCD password | `openshift-gitops` | `oc get secret openshift-gitops-cluster -n openshift-gitops` |
| Create Application | `openshift-gitops` | `oc apply -f dev-application.yaml` |
| List Applications | `openshift-gitops` | `oc get applications -n openshift-gitops` |
| Check model deployment | `llmops-dev` | `oc get inferenceservice -n llmops-dev` |
| View model logs | `llmops-dev` | `oc logs <pod> -n llmops-dev` |
| Check model route | `llmops-dev` | `oc get route -n llmops-dev` |

---

## ArgoCD Application Manifest Breakdown

Here's how the namespaces are used in an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: llmops-dev
  namespace: openshift-gitops          # ← Where this Application CR is created
  labels:
    environment: dev
    app: llmops
spec:
  project: default
  
  source:
    repoURL: https://github.com/user/repo.git
    targetRevision: main
    path: deploy_model/overlays/dev    # ← Path in Git repo
  
  destination:
    server: https://kubernetes.default.svc  # ← Internal cluster address
    namespace: llmops-dev                   # ← Where resources are deployed
```

**Key Points:**
- `metadata.namespace`: Where the Application resource itself lives (`openshift-gitops`)
- `spec.destination.namespace`: Where your workloads are deployed (`llmops-dev`)

---

## Common Commands by Namespace

### Operator Namespace Commands

```bash
# Check if operator is installed
oc get subscription openshift-gitops-operator -n openshift-operators || \
oc get subscription openshift-gitops-operator -n openshift-gitops-operator

# View operator logs
oc logs -n openshift-gitops-operator deployment/gitops-operator-controller-manager
```

### ArgoCD Namespace Commands

```bash
# Get ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get ArgoCD admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d

# List all Applications
oc get applications -n openshift-gitops

# View Application details
oc describe application llmops-dev -n openshift-gitops

# Apply Application manifest
oc apply -f argocd-apps/dev-application.yaml

# Check ArgoCD pods
oc get pods -n openshift-gitops

# View ArgoCD server logs
oc logs -n openshift-gitops deployment/openshift-gitops-server
```

### Target Namespace Commands

```bash
# Check InferenceServices
oc get inferenceservice -n llmops-dev
oc get inferenceservice -n llmops-staging
oc get inferenceservice -n llmops-prod

# Check all InferenceServices
oc get inferenceservice --all-namespaces | grep llmops

# View pods in dev environment
oc get pods -n llmops-dev

# Check routes
oc get route -n llmops-dev

# View logs
POD=$(oc get pods -n llmops-dev -o jsonpath='{.items[0].metadata.name}')
oc logs $POD -n llmops-dev

# Describe InferenceService
oc describe inferenceservice dev-qwen25-05b-instruct -n llmops-dev
```

---

## Troubleshooting by Namespace

### Issue: Can't find ArgoCD

**Wrong:**
```bash
oc get pods -n openshift-gitops-operator  # This is the operator, not ArgoCD
```

**Correct:**
```bash
oc get pods -n openshift-gitops  # ArgoCD components are here
```

### Issue: Application not found

**Wrong:**
```bash
oc get application llmops-dev -n llmops-dev  # Applications are not in target namespace
```

**Correct:**
```bash
oc get application llmops-dev -n openshift-gitops  # Applications are in ArgoCD namespace
```

### Issue: Can't find InferenceService

**Wrong:**
```bash
oc get inferenceservice -n openshift-gitops  # Workloads are not in ArgoCD namespace
```

**Correct:**
```bash
oc get inferenceservice -n llmops-dev  # Workloads are in target namespace
```

---

## Quick Reference

### Most Common Commands

```bash
# Access ArgoCD UI
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get ArgoCD password
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d

# List Applications
oc get applications -n openshift-gitops

# Check dev deployment
oc get inferenceservice -n llmops-dev

# Check all environments
oc get inferenceservice --all-namespaces | grep llmops
```

### Namespace Cheat Sheet

```bash
# Set default namespace for convenience
oc project openshift-gitops  # For ArgoCD operations

# Or for checking deployments
oc project llmops-dev
```

---

## Summary

**Remember:**
- 🔧 **Operator namespace**: Where the operator runs (don't interact with this directly)
- 🎯 **ArgoCD namespace** (`openshift-gitops`): Where you manage Applications
- 📦 **Target namespaces** (`llmops-*`): Where your models are deployed

**Golden Rule:** 
- Use `openshift-gitops` for all ArgoCD operations
- Use `llmops-dev/staging/prod` for checking your deployed models

---

**Created:** 2025-12-29
**Purpose:** Clarify namespace usage in GitOps LLMOps implementation

