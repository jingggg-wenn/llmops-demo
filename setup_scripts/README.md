# Setup Scripts

This directory contains automated setup scripts for the LLMOps multi-namespace demo.

## Files

### `setup-namespaces.sh`
Automated setup script that creates and configures all three namespaces.

**What it does:**
- Creates three OpenShift namespaces: `llmops-dev`, `llmops-staging`, `llmops-prod`
- Creates service accounts in each namespace
- Sets up roles and permissions
- Configures cross-namespace access for the GitHub deployer service account
- Generates a long-lived token for GitHub Actions
- Displays the OpenShift server URL

**Usage:**
```bash
# Make sure you're logged into OpenShift first
oc login https://YOUR_CLUSTER_URL

# Run the script
./setup_scripts/setup-namespaces.sh
```

**Output:**
- `OPENSHIFT_TOKEN` - Save this for GitHub Secrets
- `OPENSHIFT_SERVER` - Save this for GitHub Secrets

### `SETUP-MULTI-NAMESPACE.md`
Comprehensive guide for multi-namespace setup and deployment.

**Contents:**
- Quick setup instructions
- Manual setup steps (alternative to using the script)
- Deployment commands for all three environments
- GitHub Actions integration details
- Demo scenarios and workflows
- Troubleshooting tips
- Resource requirements

**Read this for:**
- Understanding the multi-namespace architecture
- Manual setup instructions
- Deployment verification steps
- Progressive rollout patterns
- Troubleshooting guidance

## Quick Start

1. **Run the setup script:**
   ```bash
   ./setup_scripts/setup-namespaces.sh
   ```

2. **Save the credentials** displayed by the script to GitHub Secrets

3. **Deploy models:**
   ```bash
   oc apply -k deploy_model/overlays/dev/
   oc apply -k deploy_model/overlays/staging/
   oc apply -k deploy_model/overlays/production/
   ```

4. **Verify deployments:**
   ```bash
   oc get inferenceservice --all-namespaces | grep llmops
   ```

## See Also

- [Main README](../README.md) - Overall project documentation
- [Deploy Model README](../deploy_model/README.md) - Kustomize overlays usage
- [SETUP-MULTI-NAMESPACE.md](./SETUP-MULTI-NAMESPACE.md) - Detailed multi-namespace guide

