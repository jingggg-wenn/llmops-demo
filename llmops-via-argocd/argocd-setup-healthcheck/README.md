# ArgoCD Custom Health Check for InferenceService

## Table of Contents

1. [Problem](#problem)
2. [Solution](#solution)
3. [Why We Use the ArgoCD CR (Not ConfigMap Directly)](#why-we-use-the-argocd-cr-not-configmap-directly)
4. [Quick Fix (Recommended Method)](#quick-fix-recommended-method)
5. [Verify the Changes](#verify-the-changes)
6. [How It Works](#how-it-works)
7. [Manual Configuration (Alternative)](#manual-configuration-alternative)
8. [Troubleshooting](#troubleshooting)
9. [Why This Matters](#why-this-matters)
10. [Additional Custom Resources](#additional-custom-resources)
11. [Summary](#summary)

---

## Problem

ArgoCD shows InferenceService as "Progressing" even when it's fully ready (`READY: True`).

This happens because ArgoCD doesn't have built-in health checks for KServe's InferenceService custom resource. By default, ArgoCD looks at all status conditions, including `Stopped: False`, which causes it to report the resource as "Progressing" indefinitely.

## Solution

Configure ArgoCD to properly assess InferenceService health by adding a custom health check to the **ArgoCD Custom Resource (CR)**, which will automatically propagate to the `argocd-cm` ConfigMap.

---

## Why We Use the ArgoCD CR (Not ConfigMap Directly)

The `argocd-cm` ConfigMap in OpenShift GitOps is **managed by the ArgoCD operator**. This means:

1. The ConfigMap has an `ownerReference` pointing to the ArgoCD custom resource
2. The operator continuously reconciles the ConfigMap back to its desired state
3. Direct edits to the ConfigMap (via `oc apply`, `oc patch`, or `oc edit`) will be overwritten by the operator
4. The **correct and persistent way** is to configure health checks in the ArgoCD CR under `spec.resourceHealthChecks`

### How It Works

```
ArgoCD CR (spec.resourceHealthChecks)
    ↓
ArgoCD Operator watches CR
    ↓
Operator updates argocd-cm ConfigMap
    ↓
Application Controller reads ConfigMap
    ↓
Health checks applied to applications
```

### Why Direct ConfigMap Edits Fail

When you try to edit the ConfigMap directly:

```bash
# This will be overwritten by the operator
oc edit configmap argocd-cm -n openshift-gitops
```

The operator sees the ConfigMap has drifted from the ArgoCD CR spec and reconciles it back, removing your changes.

**The correct approach:** Modify the ArgoCD CR, and let the operator update the ConfigMap for you.

---

## Quick Fix (Recommended Method)

### Use the Automated Script

The easiest and safest method:

```bash
cd llmops-via-argocd/argocd-custom-healthcheck

# Make the scripts executable
chmod +x apply-health-check-via-cr.sh verify-health-check.sh

# Run the setup script
./apply-health-check-via-cr.sh

# Verify the configuration (optional, but recommended)
./verify-health-check.sh
```

**Script Options:**

The setup script supports the following options:
- `-f, --force` - Skip confirmation prompt if health checks already exist (useful for automation)
- `-h, --help` - Show help message

**Example with force flag (for reruns or automation):**
```bash
./apply-health-check-via-cr.sh --force
```

**What the setup script does:**
1. Check if ArgoCD CR exists
2. Check if health checks are already configured (prompts for confirmation if they exist)
3. Patch the ArgoCD CR with `spec.resourceHealthChecks`
4. Wait for the operator to reconcile and update the ConfigMap
5. Verify the health check is in the ConfigMap
6. Force refresh all ArgoCD applications
7. Wait for health status to update
8. Display the current application status

**Graceful Reruns:**

The script is designed to handle reruns gracefully:
- If health checks already exist, it will prompt for confirmation before updating
- Use `--force` flag to skip the confirmation prompt (useful for automation)
- The script uses `oc patch` with merge strategy, so it won't break existing configurations
- All steps include verification and error handling

After running, you should see:

```
==========================================
Current Application Status:
==========================================
NAME                SYNC STATUS   HEALTH STATUS
llmops-dev          Synced        Healthy
llmops-staging      Synced        Healthy
llmops-production   OutOfSync     Missing
```

---

## Verify the Changes

### Automated Verification (Recommended)

Run the verification script to check all components:

```bash
# Run the verification script
./verify-health-check.sh
```

This script will:
1. Check if health checks are in the ArgoCD CR
2. Verify the ConfigMap was updated by the operator
3. Show current application health status
4. Display InferenceService status across all environments

**Expected output:**
```
==========================================
Verifying ArgoCD Health Check Configuration
==========================================

Step 1: Checking if health check is in ArgoCD CR...
✓ resourceHealthChecks found in ArgoCD CR
✓ InferenceService health check found in ArgoCD CR

Step 2: Checking if health check propagated to ConfigMap...
✓ Health check successfully propagated to ConfigMap

Step 3: Checking ArgoCD application health status...

NAME                SYNC STATUS   HEALTH STATUS
llmops-dev          Synced        Healthy
llmops-staging      Synced        Healthy
llmops-production   OutOfSync     Missing

Step 4: Checking InferenceService status...

Namespace: llmops-dev
NAME                      URL                                                     READY
dev-qwen25-05b-instruct   https://dev-qwen25-05b-instruct-llmops-dev.apps...     True

==========================================
Verification Complete
==========================================
```

### Manual Verification

If you prefer to verify manually:

### Step 1: Verify in ArgoCD UI

1. Wait 1-2 minutes for the operator to reconcile
2. Refresh the ArgoCD UI (hard refresh: Cmd+Shift+R or Ctrl+Shift+R)
3. Navigate to the `llmops-dev` application
4. The health status should now show "Healthy" (green) instead of "Progressing" (yellow)

### Step 2: Verify via CLI

```bash
# Check application health status
oc get applications.argoproj.io -n openshift-gitops

# Check specific application
oc get application.argoproj.io llmops-dev -n openshift-gitops -o jsonpath='{.status.health.status}'
echo ""

# Should output: Healthy
```

### Step 3: Verify Health Check is in ArgoCD CR

```bash
# Check the ArgoCD CR
oc get argocd openshift-gitops -n openshift-gitops -o yaml | grep -A 50 "resourceHealthChecks"
```

You should see:

```yaml
spec:
  resourceHealthChecks:
  - check: |
      hs = {}
      hs.status = "Progressing"
      hs.message = "Waiting for InferenceService"
      
      if obj.status ~= nil then
        if obj.status.conditions ~= nil then
          for i, condition in ipairs(obj.status.conditions) do
            if condition.type == "Ready" then
              if condition.status == "True" then
                hs.status = "Healthy"
                hs.message = "InferenceService is ready"
                return hs
              ...
```

### Step 4: Verify ConfigMap was Updated by Operator

```bash
# Check if the health check was propagated to ConfigMap
oc get configmap argocd-cm -n openshift-gitops -o yaml | grep -A 5 "InferenceService"

# You should see the Lua health check script in the data field
```

---

## How It Works

The custom health check tells ArgoCD to:

1. Look at `obj.status.conditions` in the InferenceService
2. Find the condition with `type == "Ready"`
3. Check the `status` field:
   - `"True"` → Report as "Healthy"
   - `"False"` → Report as "Degraded"
   - `"Unknown"` → Report as "Progressing"

This matches how KServe reports InferenceService readiness, and ignores other conditions like `Stopped: False` that don't indicate actual health issues.

---

## Manual Configuration (Alternative)

If you prefer to configure manually instead of using the script:

### Step 1: Edit the ArgoCD CR

```bash
oc edit argocd openshift-gitops -n openshift-gitops
```

### Step 2: Add the Health Checks

Add this under `spec:` (at the same level as `repo:`, `server:`, etc.):

```yaml
spec:
  resourceHealthChecks:
    - group: serving.kserve.io
      kind: InferenceService
      check: |
        hs = {}
        hs.status = "Progressing"
        hs.message = "Waiting for InferenceService"
        
        if obj.status ~= nil then
          if obj.status.conditions ~= nil then
            for i, condition in ipairs(obj.status.conditions) do
              if condition.type == "Ready" then
                if condition.status == "True" then
                  hs.status = "Healthy"
                  hs.message = "InferenceService is ready"
                  return hs
                elseif condition.status == "False" then
                  hs.status = "Degraded"
                  hs.message = condition.message or "InferenceService is not ready"
                  return hs
                else
                  hs.status = "Progressing"
                  hs.message = condition.message or "InferenceService is progressing"
                  return hs
                end
              end
            end
          end
        end
        
        return hs
    - group: serving.kserve.io
      kind: ServingRuntime
      check: |
        hs = {}
        hs.status = "Healthy"
        hs.message = "ServingRuntime is configured"
        return hs
```

Save and exit (`:wq` in vim).

### Step 3: Wait for Operator to Reconcile

```bash
# Wait 10-15 seconds for operator to update ConfigMap
sleep 15

# Verify ConfigMap was updated
oc get configmap argocd-cm -n openshift-gitops -o yaml | grep -A 5 "InferenceService"
```

### Step 4: Force Application Refresh

```bash
# Force ArgoCD to re-evaluate health
oc patch application.argoproj.io llmops-dev -n openshift-gitops --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
oc patch application.argoproj.io llmops-staging -n openshift-gitops --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Wait and check
sleep 30
oc get applications.argoproj.io -n openshift-gitops
```

---

## Troubleshooting

### Issue 1: Still Shows "Progressing" After Applying

**Solution:**

```bash
# 1. Verify the health check is in the ArgoCD CR
oc get argocd openshift-gitops -n openshift-gitops -o yaml | grep -A 10 "resourceHealthChecks"

# 2. Verify it propagated to ConfigMap
oc get configmap argocd-cm -n openshift-gitops -o jsonpath='{.data.resource\.customizations\.health\.serving\.kserve\.io_InferenceService}' | head -10

# 3. Force hard refresh
oc patch application.argoproj.io llmops-dev -n openshift-gitops --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 4. Wait and check
sleep 30
oc get applications.argoproj.io -n openshift-gitops

# 5. Hard refresh ArgoCD UI in browser (Cmd+Shift+R or Ctrl+Shift+R)
```

### Issue 2: Health Check Not in ConfigMap

**Problem:** The health check is in the ArgoCD CR but not in the ConfigMap.

**Solution:**

```bash
# Check operator logs for reconciliation errors
oc logs -n openshift-gitops deployment/openshift-gitops-operator -f

# Check if operator is running
oc get pods -n openshift-gitops-operator

# Force operator to reconcile
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":"'$(date +%Y-%m-%dT%H:%M:%S%z)'"}}}'

# Wait and verify
sleep 15
oc get configmap argocd-cm -n openshift-gitops -o yaml | grep -A 5 "InferenceService"
```

### Issue 3: ConfigMap Changes Keep Getting Overwritten

**Problem:** You edited the ConfigMap directly and changes are being reverted.

**Solution:** This is expected behavior. The operator manages the ConfigMap based on the ArgoCD CR.

**Fix:** Use the ArgoCD CR method (as documented above) instead of editing the ConfigMap directly.

### Issue 4: Health Check Script Has Errors

**Check application controller logs:**

```bash
oc logs -n openshift-gitops deployment/cluster --tail=100 | grep -i "health\|lua\|error"
```

Look for Lua script parsing errors. Common issues:
- Incorrect indentation in the Lua script
- Missing `return hs` statement
- Syntax errors in the Lua code

### Issue 5: Operator Not Reconciling

**Check operator status:**

```bash
# Check operator deployment
oc get deployment -n openshift-gitops-operator

# Check operator logs
oc logs -n openshift-gitops-operator deployment/openshift-gitops-operator --tail=50

# Check ArgoCD CR status
oc get argocd openshift-gitops -n openshift-gitops -o yaml | grep -A 20 "status:"
```

---

## Why This Matters

**Without custom health check:**
- ArgoCD shows "Progressing" forever
- You can't tell if the deployment actually succeeded
- Hard to use ArgoCD sync waves or health-based automation
- Manual verification required for every deployment

**With custom health check:**
- Accurate health status (Healthy/Degraded/Progressing)
- Clear visibility in ArgoCD UI
- Can use ArgoCD features that depend on health status
- Better monitoring and alerting
- Automated sync decisions based on health

---

## Additional Custom Resources

If you're using other KServe resources, you can add health checks for them in the same way.

### ClusterServingRuntime

Add to `spec.resourceHealthChecks` in the ArgoCD CR:

```yaml
- group: serving.kserve.io
  kind: ClusterServingRuntime
  check: |
    hs = {}
    hs.status = "Healthy"
    hs.message = "ClusterServingRuntime is configured"
    return hs
```

### TrainedModel

```yaml
- group: serving.kserve.io
  kind: TrainedModel
  check: |
    hs = {}
    hs.status = "Progressing"
    hs.message = "Waiting for TrainedModel"
    
    if obj.status ~= nil and obj.status.conditions ~= nil then
      for i, condition in ipairs(obj.status.conditions) do
        if condition.type == "Ready" and condition.status == "True" then
          hs.status = "Healthy"
          hs.message = "TrainedModel is ready"
          return hs
        end
      end
    end
    
    return hs
```

---

## Summary

### Quick Steps (Recommended)

```bash
cd llmops-via-argocd/argocd-custom-healthcheck

# Make scripts executable
chmod +x apply-health-check-via-cr.sh verify-health-check.sh

# Apply health checks
./apply-health-check-via-cr.sh

# Verify configuration
./verify-health-check.sh
```

### What Happens

1. Script patches the ArgoCD CR with `spec.resourceHealthChecks`
2. ArgoCD operator detects the change and reconciles
3. Operator updates the `argocd-cm` ConfigMap with the health checks
4. Application controller picks up the new health checks
5. ArgoCD re-evaluates InferenceService health status
6. UI updates to show "Healthy" instead of "Progressing"

### Key Takeaways

- **Always use the ArgoCD CR** for custom health checks, not the ConfigMap directly
- The operator manages the ConfigMap based on the CR spec
- Direct ConfigMap edits will be overwritten by the operator
- This is the correct, operator-approved, and persistent method
- The script automates the entire process for you

### Result

- ArgoCD correctly shows InferenceService as "Healthy" when `READY: True`
- Better visibility and monitoring in ArgoCD UI
- Can use ArgoCD features that depend on health status
- Proper status for staging/production sync decisions
- Changes persist across operator reconciliation

---

**Created:** 2025-12-30
**Purpose:** Configure ArgoCD to properly assess KServe InferenceService health
**Applies to:** OpenShift GitOps / ArgoCD with KServe
**Method:** ArgoCD CR configuration (operator-managed)
