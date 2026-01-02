# Folder Structure and File Contents

This document describes the folder structure and contents of the `llmops-via-argocd/` directory.

## Overview

A complete GitOps-based LLMOps implementation using ArgoCD for deploying LLM models to Red Hat OpenShift AI, replacing the previous GitHub Actions push-based approach with a pull-based GitOps workflow.

## Folder Structure

```
llmops-via-argocd/
├── argocd-apps/                          # ArgoCD Application definitions
│   ├── dev-application.yaml              # Dev environment (auto-sync)
│   ├── staging-application.yaml          # Staging environment (manual sync)
│   └── production-application.yaml       # Production environment (manual sync)
│
├── argocd-rbac/                          # ArgoCD RBAC configuration
│   ├── apply-rbac-via-cr.sh              # Script to apply RBAC via ArgoCD CR
│   ├── verify-rbac.sh                    # Script to verify RBAC configuration
│   ├── diagnose-rbac-issue.sh            # Script to diagnose RBAC issues
│   └── README.md                         # RBAC setup documentation
│
├── argocd-setup-healthcheck/             # ArgoCD health check configuration
│   ├── apply-health-check-via-cr.sh      # Script to apply health checks
│   ├── verify-health-check.sh            # Script to verify health checks
│   └── README.md                         # Health check documentation
│
├── deploy_model/                         # Kustomize configurations
│   ├── base/                             # Base model configuration (shared)
│   │   ├── inferenceservice.yaml         # KServe InferenceService
│   │   ├── servingruntime.yaml           # vLLM runtime configuration
│   │   ├── oci-data-connection.yaml      # Model storage secret
│   │   └── kustomization.yaml            # Base kustomization
│   │
│   └── overlays/                         # Environment-specific configs
│       ├── dev/                          # Development environment
│       │   └── kustomization.yaml        # Dev patches (1 replica, 2 CPU, 6Gi)
│       ├── staging/                      # Staging environment
│       │   └── kustomization.yaml        # Staging patches (1-2 replicas, 3 CPU, 8Gi)
│       └── production/                   # Production environment
│           └── kustomization.yaml        # Prod patches (2-3 replicas, 4 CPU, 12Gi)
│
├── setup_scripts/                        # Automation scripts
│   ├── setup-argocd.sh                   # Setup namespaces and ArgoCD permissions
│   └── apply-argocd-apps.sh              # Apply ArgoCD Applications
│
├── README.md                             # Main documentation
├── step-by-step-guide.md                 # Detailed setup guide (1900+ lines)
├── NAMESPACE-GUIDE.md                    # Namespace organization guide
├── COMPARISON-GITHUBACTIONS-ARGOCD.md    # GitHub Actions vs ArgoCD comparison
├── vLLM_PARAMS_USAGE_SCENARIOS.md        # vLLM parameter testing scenarios
└── FOLDER-STRUCTURE.md                   # This file
```

## Key Components

### 1. ArgoCD Applications (argocd-apps/)

Three ArgoCD Application resources that define how ArgoCD manages each environment:

**dev-application.yaml:**
- Watches: `deploy_model/overlays/dev/`
- Target namespace: `llmops-dev`
- Sync policy: **Automated** (auto-sync + self-heal)
- Purpose: Rapid development and testing

**staging-application.yaml:**
- Watches: `deploy_model/overlays/staging/`
- Target namespace: `llmops-staging`
- Sync policy: **Manual** (requires approval)
- Purpose: Pre-production validation

**production-application.yaml:**
- Watches: `deploy_model/overlays/production/`
- Target namespace: `llmops-prod`
- Sync policy: **Manual** (requires approval)
- Purpose: Production workloads

### 2. ArgoCD RBAC Configuration (argocd-rbac/)

Scripts and documentation for configuring ArgoCD RBAC to enable OpenShift SSO access:

**apply-rbac-via-cr.sh:**
- Configures RBAC in ArgoCD CR (operator-managed approach)
- Automatically detects your username
- Grants admin access to your user
- Sets default policy to readonly for all authenticated users
- Defines custom roles: llmops-admin, llmops-developer, llmops-viewer

**verify-rbac.sh:**
- Verifies RBAC is correctly configured
- Checks ArgoCD CR and ConfigMap
- Validates user access

**diagnose-rbac-issue.sh:**
- Diagnoses RBAC issues
- Shows current configuration
- Checks user and group membership

### 3. ArgoCD Health Check Configuration (argocd-setup-healthcheck/)

Scripts and documentation for configuring custom health checks for KServe InferenceService:

**apply-health-check-via-cr.sh:**
- Configures health checks in ArgoCD CR (operator-managed approach)
- Adds custom health check for InferenceService
- Adds custom health check for ServingRuntime
- Waits for operator to propagate to ConfigMap
- Restarts ArgoCD server

**verify-health-check.sh:**
- Verifies health checks are correctly configured
- Checks ArgoCD CR and ConfigMap
- Shows application health status

### 4. Kustomize Configurations (deploy_model/)

**Base configuration** defines the core model deployment:
- InferenceService: Qwen 2.5 0.5B Instruct model
- ServingRuntime: vLLM inference engine
- Secret: OCI data connection for model storage

**Overlays** customize for each environment:
- Different resource allocations (CPU, memory)
- Different replica counts
- Different name prefixes (dev-, staging-, prod-)
- Different display names

### 5. Setup Scripts (setup_scripts/)

**setup-argocd.sh:**
- Verifies OpenShift GitOps Operator is installed
- Creates three namespaces: llmops-dev, llmops-staging, llmops-prod
- Grants ArgoCD service account admin permissions
- Retrieves ArgoCD URL and admin password

**apply-argocd-apps.sh:**
- Applies all three ArgoCD Application resources
- Verifies applications were created
- Shows ArgoCD access information

### 6. Documentation

**README.md** (main documentation):
- Overview of GitOps approach
- Architecture diagrams
- Quick start guide
- Usage examples
- Comparison with GitHub Actions
- Troubleshooting

**step-by-step-guide.md** (detailed guide):
- 13-step implementation guide
- Prerequisites check
- Operator installation
- Namespace setup
- Git repository configuration
- ArgoCD application deployment
- Health check configuration
- RBAC configuration
- Testing workflows
- Monitoring and troubleshooting
- Best practices

**NAMESPACE-GUIDE.md** (namespace organization):
- Explanation of namespace structure
- Operator vs ArgoCD vs target namespaces
- Common confusion points
- Verification commands

**COMPARISON-GITHUBACTIONS-ARGOCD.md** (detailed comparison):
- GitHub Actions vs ArgoCD feature comparison
- Workflow comparisons
- Use case scenarios
- Migration path
- Recommendations

**vLLM_PARAMS_USAGE_SCENARIOS.md** (vLLM parameter testing):
- 3 distinct vLLM configuration scenarios
- GPU memory utilization tuning
- Tool use / function calling configuration
- Max model length adjustment
- Complete testing commands with curl and jq
- Pod inspection commands
- Troubleshooting guide

## Key Features

### GitOps Principles

1. **Git as Source of Truth**
   - All configuration stored in Git
   - Cluster state derived from Git
   - No manual `oc apply` commands

2. **Declarative Configuration**
   - Kustomize overlays define desired state
   - ArgoCD ensures cluster matches Git

3. **Continuous Reconciliation**
   - ArgoCD polls Git every 3 minutes (configurable)
   - Detects and corrects drift
   - Self-healing for dev environment

4. **Automated Deployment**
   - Dev: Auto-syncs on Git changes
   - Staging/Prod: Manual approval required

### Operator-Managed Configurations

All ArgoCD configurations use the **operator-managed approach**:

1. **Health Checks** - Configured in ArgoCD CR (`spec.resourceHealthChecks`)
2. **RBAC** - Configured in ArgoCD CR (`spec.rbac`)
3. **Polling Interval** - Configured in ArgoCD CR (`spec.repo.env`)

The operator automatically propagates these to ConfigMaps, ensuring changes persist across reconciliation.

### Security Improvements

- No cluster credentials stored in GitHub
- ArgoCD runs inside OpenShift cluster
- Uses OpenShift's native RBAC
- Full audit trail in Git and ArgoCD
- OpenShift SSO integration for user access

### Operational Benefits

- **Drift Detection**: Alerts when cluster state differs from Git
- **Easy Rollback**: One-click rollback in ArgoCD UI
- **Rich Visualization**: Resource tree view in ArgoCD
- **Manual Approval Gates**: Control production deployments
- **Change Preview**: See diff before deploying
- **Health Monitoring**: Custom health checks for KServe resources

## How It Works

### Development Workflow

```
1. Developer makes changes to Kustomize overlay
2. Commits and pushes to Git
3. Creates Pull Request
4. After review, merges to main branch
5. ArgoCD detects change (within 3 minutes)
6. For dev: Auto-syncs immediately
   For staging/prod: Shows OutOfSync, waits for manual approval
7. Operator reviews changes in ArgoCD UI
8. Manually syncs staging/production
9. ArgoCD deploys and monitors health
10. Continuous reconciliation ensures cluster matches Git
```

### Sync Policies

**Dev Environment (Auto-Sync):**
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git
    selfHeal: true   # Auto-correct drift
```

**Staging/Production (Manual Sync):**
```yaml
syncPolicy:
  # No automated section = manual sync required
  syncOptions:
    - CreateNamespace=true
```

## Prerequisites

### Required Operators

1. **OpenShift GitOps Operator** (provides ArgoCD)
   - Installed via OperatorHub
   - Creates `openshift-gitops` namespace
   - Deploys ArgoCD Server

2. **OpenShift Pipelines Operator** (for Phase 2)
   - Installed via OperatorHub
   - Provides Tekton for CI validation

### Required Infrastructure

- OpenShift cluster with RHOAI and KServe
- GPU nodes with NVIDIA GPU operator
- Cluster admin access

## Setup Process

### High-Level Steps

1. **Install Operators**
   - OpenShift GitOps via OperatorHub
   - Wait for ArgoCD to be ready

2. **Run Setup Script**
   - Creates namespaces
   - Configures permissions
   - Provides ArgoCD credentials

3. **Configure Git Repository**
   - Update ArgoCD apps with repo URL
   - Push code to GitHub

4. **Deploy ArgoCD Applications**
   - Apply three Application resources
   - Verify in ArgoCD UI

5. **Configure Health Checks**
   - Run health check setup script
   - Verify applications show "Healthy"

6. **Configure RBAC (Optional)**
   - Run RBAC setup script
   - Enable OpenShift SSO access

7. **Initial Sync**
   - Sync dev environment
   - Optionally sync staging/production

8. **Test Workflow**
   - Make changes to overlays
   - Push to Git
   - Watch ArgoCD sync

### Estimated Setup Time

- Operator installation: 5-10 minutes
- Setup script: 2 minutes
- Git configuration: 5 minutes
- ArgoCD application deployment: 2 minutes
- Health check configuration: 2 minutes
- RBAC configuration: 2 minutes
- Initial sync: 3-5 minutes per environment

**Total: 25-35 minutes**

## Success Criteria

You'll know the implementation is successful when:

- ✅ All three ArgoCD Applications show "Synced" and "Healthy"
- ✅ Dev environment auto-syncs when you push changes
- ✅ Staging/Production show "OutOfSync" and require manual approval
- ✅ You can view all resources in ArgoCD UI
- ✅ You can login via OpenShift SSO
- ✅ You can rollback via ArgoCD UI
- ✅ Drift detection works (try manually changing a resource)
- ✅ All InferenceServices are accessible via routes

## Resources

### Documentation Files

- `README.md` - Main documentation
- `step-by-step-guide.md` - Detailed setup guide
- `NAMESPACE-GUIDE.md` - Namespace organization
- `COMPARISON-GITHUBACTIONS-ARGOCD.md` - Comparison with GitHub Actions
- `vLLM_PARAMS_USAGE_SCENARIOS.md` - vLLM parameter testing scenarios
- `FOLDER-STRUCTURE.md` - This file

### Setup Scripts

- `setup_scripts/setup-argocd.sh` - Automated setup
- `setup_scripts/apply-argocd-apps.sh` - Deploy applications
- `argocd-setup-healthcheck/apply-health-check-via-cr.sh` - Configure health checks
- `argocd-rbac/apply-rbac-via-cr.sh` - Configure RBAC

### External Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [Kustomize Documentation](https://kustomize.io/)
- [KServe Documentation](https://kserve.github.io/website/)

## Summary

This implementation provides a production-ready GitOps workflow for LLMOps on OpenShift AI, with:

- **True GitOps**: Git as single source of truth
- **Continuous Reconciliation**: ArgoCD ensures cluster matches Git
- **Automatic Drift Detection**: Alerts on manual changes
- **Manual Approval Gates**: Control production deployments
- **Rich Visualization**: ArgoCD dashboard for monitoring
- **Easy Rollback**: One-click revert to previous version
- **Better Security**: No cluster credentials outside cluster
- **Custom Health Checks**: Proper status for KServe resources
- **OpenShift SSO Integration**: User access via SSO

The implementation is simple to use (just push to Git), yet powerful enough for production workloads with multiple environments and approval workflows.

---

**Created:** 2025-12-29
**Last Updated:** 2025-12-30
**Lines of Documentation:** ~3500+
**Files Created:** 25+
**Ready for:** Production use on OpenShift AI 3.x with KServe

