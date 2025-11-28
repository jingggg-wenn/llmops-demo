# Model Deployment with Kustomize Overlays

This directory contains the model deployment configurations using Kustomize overlays for environment-specific settings.

## Quick Reference

### Structure

```
deploy_model/
├── base/                         # Shared base configuration
│   ├── inferenceservice.yaml     # Model definition
│   ├── servingruntime.yaml       # vLLM runtime config
│   ├── oci-data-connection.yaml  # Model source
│   └── kustomization.yaml
└── overlays/                     # Environment-specific configs
    ├── dev/
    ├── staging/
    └── production/
```

### Deploy Commands

```bash
# Development
oc apply -k deploy_model/overlays/dev/

# Staging
oc apply -k deploy_model/overlays/staging/

# Production
oc apply -k deploy_model/overlays/production/
```

### Preview Without Deploying

```bash
# See what will be deployed
kustomize build deploy_model/overlays/dev/
kustomize build deploy_model/overlays/staging/
kustomize build deploy_model/overlays/production/
```

## Environment Comparison

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| CPU Limit | 1 core | 2 cores | 4 cores |
| Memory Limit | 6Gi | 8Gi | 12Gi |
| Min Replicas | 1 | 1 | 2 |
| Max Replicas | 1 | 2 | 3 |
| Name Prefix | `dev-` | `staging-` | `prod-` |

## Making Changes

### Change Applies to All Environments
Edit files in `base/` directory:
- `inferenceservice.yaml` - Model definition, default resources
- `servingruntime.yaml` - vLLM runtime settings
- `oci-data-connection.yaml` - Model source location

### Change Applies to Specific Environment
Edit `kustomization.yaml` in the overlay directory:
- `overlays/dev/kustomization.yaml`
- `overlays/staging/kustomization.yaml`
- `overlays/production/kustomization.yaml`

## Examples

### Example 1: Update Model Version (All Environments)

```bash
# Edit base configuration
vim base/inferenceservice.yaml

# Change storageUri to new model
storageUri: 'oci://quay.io/redhat-ai-services/modelcar-catalog:qwen2.5-3b-instruct'

# Commit and push - progressively deploy to each environment
```

### Example 2: Increase Production Resources Only

```bash
# Edit production overlay
vim overlays/production/kustomization.yaml

# Add or modify the patch:
patches:
  - target:
      kind: InferenceService
    patch: |-
      - op: replace
        path: /spec/predictor/model/resources/limits/cpu
        value: "8"  # Increased from 4
```

### Example 3: Add New vLLM Parameter (All Environments)

```bash
# Edit base runtime
vim base/servingruntime.yaml

# Add new argument in the args section:
args:
  - '--port=8080'
  - '--model=/mnt/models'
  - '--max-model-len'
  - '65536'  # Increased context window
  - '--tensor-parallel-size'
  - '2'      # NEW: Use 2 GPUs
```

## Testing Changes Locally

Before pushing to GitHub:

```bash
# Validate syntax
kustomize build overlays/dev/ > /dev/null && echo "Valid"

# See the diff
kustomize build overlays/dev/ > dev-output.yaml
# Review dev-output.yaml

# Test deploy to dev
oc apply -k overlays/dev/ --dry-run=client
```

## Progressive Rollout Workflow

```
1. Edit configuration
2. Test locally with kustomize build
3. Deploy to dev: push changes to overlays/dev/
4. Validate in dev environment
5. Deploy to staging: push changes to overlays/staging/
6. Run integration tests
7. Deploy to production: push changes to overlays/production/
8. Monitor production deployment
```

## More Information

See the main [README.md](../README.md) for:
- Complete setup instructions
- GitHub Actions integration
- Troubleshooting guide
- Architecture overview
