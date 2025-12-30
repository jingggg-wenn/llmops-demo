# ArgoCD RBAC Configuration for OpenShift SSO

## Quick Start

Enable OpenShift SSO users to access ArgoCD and see all applications.

### Step 1: Run the Setup Script

```bash
cd llmops-via-argocd/argocd-rbac

# Make scripts executable
chmod +x apply-rbac-via-cr.sh verify-rbac.sh

# Apply RBAC configuration
./apply-rbac-via-cr.sh
```

### Step 2: Verify Configuration

```bash
# Verify RBAC is correctly applied
./verify-rbac.sh
```

### Step 3: Test SSO Login

1. Open the ArgoCD URL (shown in script output)
2. Click **"LOG IN VIA OPENSHIFT"** (not the admin login)
3. Login with your OpenShift credentials
4. You should now see all applications!

---

## What This Does

The setup script automatically:
1. Gets your current OpenShift username
2. Configures RBAC in the **ArgoCD Custom Resource (CR)**
3. Grants your user admin access
4. Sets default policy to `readonly` (all authenticated users can view)
5. Defines custom roles: `llmops-admin`, `llmops-developer`, `llmops-viewer`
6. Waits for ArgoCD operator to propagate changes to ConfigMap
7. Restarts ArgoCD server to apply changes

---

## Why This Approach Works

### The Problem with Direct ConfigMap Editing

The `argocd-rbac-cm` ConfigMap is **operator-managed**:
- It has an `ownerReference` to the ArgoCD CR
- Direct edits (via `oc apply` or `oc edit`) are overwritten by the operator
- Changes don't persist

### The Correct Approach

Configure RBAC in the **ArgoCD Custom Resource** under `spec.rbac`:

```
ArgoCD CR (spec.rbac)
    ↓
ArgoCD Operator watches CR
    ↓
Operator updates argocd-rbac-cm ConfigMap
    ↓
ArgoCD Server reads ConfigMap
    ↓
RBAC applied to users
```

This is the same pattern we use for health checks and other configurations.

---

## RBAC Roles Configured

### 1. Admin Access (Full Control)

**Who gets it:**
- Your OpenShift username (automatically detected)
- `system:cluster-admins` group
- `cluster-admins` group

**What they can do:**
- View all applications
- Create/delete applications
- Sync applications
- Manage ArgoCD settings
- Full access to all resources

### 2. Default Policy (Read-Only)

**Who gets it:**
- All authenticated OpenShift users (via SSO)

**What they can do:**
- View applications
- View application details
- View logs
- Cannot sync or modify

### 3. Custom Roles

**llmops-admin:**
- Full access to applications, repositories, projects
- Can sync and manage all resources

**llmops-developer:**
- View and sync applications
- View repositories and projects
- View logs
- Cannot delete or modify settings

**llmops-viewer:**
- Read-only access to applications
- View logs
- Cannot sync or modify

---

## Manual Configuration (Alternative to Script)

If you prefer to configure RBAC manually without using the script, follow these steps:

### Step 1: Get Your OpenShift Username

```bash
# Check your current username
oc whoami
```

### Step 2: Edit the ArgoCD Custom Resource

```bash
oc edit argocd openshift-gitops -n openshift-gitops
```

This will open the ArgoCD CR in your default editor (usually vi/vim).

### Step 3: Add or Update the RBAC Section

Find the `spec:` section and add the `rbac:` configuration. It should be at the same level as other sections like `repo:`, `server:`, `redis:`, etc.

**Add this configuration:**

```yaml
spec:
  # ... other existing fields like repo:, server:, etc. ...
  
  rbac:
    defaultPolicy: 'role:readonly'
    policy: |
      # Grant cluster-admins full admin access
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
      
      # Grant your specific user admin access
      # REPLACE 'admin' with your actual username from Step 1
      g, admin, role:admin
      
      # Custom role: llmops-admin (full access to llmops applications)
      p, role:llmops-admin, applications, *, */*, allow
      p, role:llmops-admin, clusters, get, *, allow
      p, role:llmops-admin, repositories, *, *, allow
      p, role:llmops-admin, projects, *, *, allow
      p, role:llmops-admin, logs, get, *, allow
      p, role:llmops-admin, exec, create, */*, allow
      
      # Custom role: llmops-developer (can view and sync applications)
      p, role:llmops-developer, applications, get, */*, allow
      p, role:llmops-developer, applications, sync, */*, allow
      p, role:llmops-developer, applications, override, */*, allow
      p, role:llmops-developer, applications, action/*, */*, allow
      p, role:llmops-developer, clusters, get, *, allow
      p, role:llmops-developer, repositories, get, *, allow
      p, role:llmops-developer, projects, get, *, allow
      p, role:llmops-developer, logs, get, *, allow
      
      # Custom role: llmops-viewer (read-only access)
      p, role:llmops-viewer, applications, get, */*, allow
      p, role:llmops-viewer, clusters, get, *, allow
      p, role:llmops-viewer, repositories, get, *, allow
      p, role:llmops-viewer, projects, get, *, allow
      p, role:llmops-viewer, logs, get, *, allow
    scopes: '[groups]'
```

**Important Notes:**
- Make sure to replace `admin` with your actual username (from Step 1)
- Keep the indentation exactly as shown (2 spaces per level)
- The `|` character after `policy:` indicates a multi-line string
- Don't remove any existing fields in the CR

### Step 4: Save and Exit

- In vi/vim: Press `Esc`, then type `:wq` and press `Enter`
- In nano: Press `Ctrl+X`, then `Y`, then `Enter`

### Step 5: Wait for Operator to Reconcile

```bash
# Wait 10-15 seconds for the operator to update the ConfigMap
sleep 15

# Verify the ConfigMap was updated
oc get configmap argocd-rbac-cm -n openshift-gitops -o jsonpath='{.data.policy\.csv}'
```

You should see your username in the output.

### Step 6: Restart ArgoCD Server

```bash
# Restart the ArgoCD server to pick up the new RBAC configuration
oc rollout restart deployment/openshift-gitops-server -n openshift-gitops

# Wait for the restart to complete
oc rollout status deployment/openshift-gitops-server -n openshift-gitops
```

### Step 7: Test SSO Login

```bash
# Get the ArgoCD URL
echo "ArgoCD URL: https://$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"
```

1. Open the ArgoCD URL in your browser
2. Click **"LOG IN VIA OPENSHIFT"** (not the admin login)
3. Login with your OpenShift credentials
4. You should now see all applications!

### Step 8: Verify (Optional)

```bash
# Verify your user is in the RBAC policy
oc get configmap argocd-rbac-cm -n openshift-gitops -o jsonpath='{.data.policy\.csv}' | grep $(oc whoami)

# Check application access
# Open ArgoCD UI and verify you can see llmops-dev, llmops-staging, llmops-production
```

---

## Customization

### Grant Admin Access to Additional Users

Edit the script or manually patch the ArgoCD CR:

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge --patch '
spec:
  rbac:
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
      g, your-username, role:admin
      g, another-user, role:admin
'
```

### Grant Role to OpenShift Groups

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge --patch '
spec:
  rbac:
    policy: |
      g, system:cluster-admins, role:admin
      g, my-devops-team, role:llmops-admin
      g, my-dev-team, role:llmops-developer
      g, my-qa-team, role:llmops-viewer
'
```

### Change Default Policy

To give no access by default (only explicitly granted users):

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge --patch '
spec:
  rbac:
    defaultPolicy: ""
'
```

---

## Troubleshooting

### Issue 1: Can't See Applications After SSO Login

**Solution:**

```bash
# Run verification script
./verify-rbac.sh

# Check if your user is in the policy
oc get configmap argocd-rbac-cm -n openshift-gitops -o jsonpath='{.data.policy\.csv}' | grep $(oc whoami)

# If not found, re-run the setup script
./apply-rbac-via-cr.sh --force
```

### Issue 2: Changes Not Taking Effect

**Solution:**

```bash
# Restart ArgoCD server
oc rollout restart deployment/openshift-gitops-server -n openshift-gitops

# Wait for it to be ready
oc rollout status deployment/openshift-gitops-server -n openshift-gitops

# Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)
```

### Issue 3: RBAC Configuration Gets Overwritten

**Problem:** You edited `argocd-rbac-cm` ConfigMap directly and it was overwritten.

**Solution:** This is expected. The ConfigMap is operator-managed. Always configure RBAC via the ArgoCD CR:

```bash
# Correct way
oc edit argocd openshift-gitops -n openshift-gitops
# Edit spec.rbac section

# Or use the script
./apply-rbac-via-cr.sh --force
```

### Issue 4: Want to Check Current RBAC Configuration

```bash
# Check ArgoCD CR
oc get argocd openshift-gitops -n openshift-gitops -o yaml | grep -A 50 "rbac:"

# Check ConfigMap (updated by operator)
oc get configmap argocd-rbac-cm -n openshift-gitops -o yaml

# Run diagnostic script
./diagnose-rbac-issue.sh
```

---

## Script Options

### apply-rbac-via-cr.sh

```bash
# Interactive mode (prompts for confirmation if RBAC exists)
./apply-rbac-via-cr.sh

# Force mode (skip confirmation, useful for reruns)
./apply-rbac-via-cr.sh --force

# Show help
./apply-rbac-via-cr.sh --help
```

### verify-rbac.sh

```bash
# Verify RBAC configuration
./verify-rbac.sh
```

### diagnose-rbac-issue.sh

```bash
# Diagnose RBAC issues
./diagnose-rbac-issue.sh
```

---

## Files in This Folder

- `apply-rbac-via-cr.sh` - Automated script to apply RBAC via ArgoCD CR
- `verify-rbac.sh` - Verify RBAC configuration is correct
- `diagnose-rbac-issue.sh` - Diagnose RBAC issues
- `README.md` - This file (complete documentation)

---

## Key Takeaways

1. **Always configure RBAC via ArgoCD CR** (`spec.rbac`), not the ConfigMap directly
2. **The operator manages the ConfigMap** - direct edits will be overwritten
3. **Use the scripts** for easy, repeatable configuration
4. **Restart ArgoCD server** after RBAC changes
5. **Hard refresh browser** after server restart

---

**Created:** 2025-12-30
**Purpose:** Enable OpenShift SSO users to access ArgoCD
**Method:** ArgoCD CR configuration (operator-managed)
