# vLLM Parameter Usage Scenarios

This document provides 3 distinct vLLM configuration scenarios. Each scenario can be applied to any environment (dev, staging, or production) by adding the patches to the appropriate overlay's `kustomization.yaml`.

## Base Configuration Reference

The base ServingRuntime (`deploy_model/base/servingruntime.yaml`) starts with:

```yaml
args:
  - '--port=8080'                          # Index 0
  - '--model=/mnt/models'                  # Index 1
  - '--served-model-name={{.Name}}'        # Index 2
  - '--max-model-len'                      # Index 3
  - '32768'                                # Index 4
```

---

## Scenario 1: Change GPU Memory Utilization

**What it does:** Controls the percentage of GPU memory that vLLM can use. Higher values allow more concurrent requests but increase risk of OOM errors.

### Patch to Apply

Add this to your overlay's `kustomization.yaml` (e.g., `deploy_model/overlays/staging/kustomization.yaml`):

```yaml
patches:
  # ... existing patches ...
  
  # Patch ServingRuntime to change GPU memory utilization
  - target:
      kind: ServingRuntime
      name: qwen25-05b-instruct
    patch: |-
      - op: add
        path: /spec/containers/0/args/-
        value: "--gpu-memory-utilization"
      - op: add
        path: /spec/containers/0/args/-
        value: "0.9"
```

**Values to try:**
- `0.7` - Conservative (70% GPU memory)
- `0.85` - Moderate (85% GPU memory)
- `0.9` - Aggressive (90% GPU memory)
- `0.95` - Maximum (95% GPU memory)

### How to Test

```bash
# 1. Get the route URL
ROUTE=$(oc get route <env>-qwen25-05b-instruct -n llmops-<env> -o jsonpath='{.spec.host}')

# 2. Check model info (should show it's running)
curl https://$ROUTE/v1/models | jq '.'

# 3. Send a test request (formatted output with jq)
curl https://$ROUTE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<env>-qwen25-05b-instruct",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "max_tokens": 100
  }' | jq '.'

# 4. Check GPU memory usage in the pod
POD=$(oc get pod -n llmops-<env> -l component=predictor -o jsonpath='{.items[0].metadata.name}')

# Run interactive terminal 
oc exec -it -n llmops-<env> $POD -c kserve-container -- /bin/bash
nvidia-smi
nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# Example output: 
# memory.used [MiB], memory.total [MiB]
# 20966 MiB, 23034 MiB
# Calculate: 20966 / 23034 = 0.91 (91% utilization)

# 5. Enter interactive shell for more exploration (optional)
oc exec -it -n llmops-<env> $POD -c kserve-container -- /bin/bash

# Once inside, you can run:
# - nvidia-smi
# - nvidia-smi -l 1  (continuous monitoring, updates every 1 second)
# - ps aux | grep python
# - exit (to leave the shell)
```

**Expected behavior:**
- Higher GPU utilization = more memory available for concurrent requests
- Monitor for OOM errors: `oc logs -n llmops-<env> $POD | grep -i "out of memory"`

---

## Scenario 2: Enable Tool Use (Function Calling)

**What it does:** Enables the model to use function calling / tool use capabilities, allowing it to call external functions.

### Patch to Apply

Add this to your overlay's `kustomization.yaml`:

```yaml
patches:
  # ... existing patches ...
  
  # Patch ServingRuntime to enable tool use
  - target:
      kind: ServingRuntime
      name: qwen25-05b-instruct
    patch: |-
      - op: add
        path: /spec/containers/0/args/-
        value: "--enable-auto-tool-choice"
      - op: add
        path: /spec/containers/0/args/-
        value: "--tool-call-parser"
      - op: add
        path: /spec/containers/0/args/-
        value: "hermes"
```

**Parameters:**
- `--enable-auto-tool-choice` - Model automatically decides when to use tools
- `--tool-call-parser hermes` - Use Hermes format (compatible with Qwen models)

### How to Test

```bash
# 1. Get the route URL
ROUTE=$(oc get route <env>-qwen25-05b-instruct -n llmops-<env> -o jsonpath='{.spec.host}')

# 2. Create a JSON file with the tool definition
# NOTE: Replace <env> with your environment (dev, staging, or production)
cat > tool_request.json <<'EOF'
{
  "model": "<env>-qwen25-05b-instruct",
  "messages": [
    {"role": "user", "content": "What is the weather in San Francisco?"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get the current weather in a location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "The city and state, e.g. San Francisco, CA"
            }
          },
          "required": ["location"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
EOF

# After creating the file, edit it to replace <env> with your actual environment:
# - For dev: "model": "dev-qwen25-05b-instruct"
# - For staging: "model": "staging-qwen25-05b-instruct"
# - For production: "model": "production-qwen25-05b-instruct"

# 3. Send the request (formatted output with jq)
curl https://$ROUTE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @tool_request.json | jq '.'
```

**Expected Response (Tool Call):**

```json
{
  "id": "chatcmpl-3ed13766299c47b68b58b0d7035e8840",
  "object": "chat.completion",
  "created": 1767366032,
  "model": "<env>-qwen25-05b-instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "chatcmpl-tool-53ce711208e34c04879f8b634f8600b7",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"location\": \"San Francisco\"}"
            }
          }
        ]
      },
      "finish_reason": "tool_calls"
    }
  ],
  "usage": {
    "prompt_tokens": 189,
    "total_tokens": 210,
    "completion_tokens": 21
  }
}
```

**What This Response Means:**

✅ **Tool use is working!** The model:
1. Recognized it has a `get_weather` function available
2. Determined it needs to call this function to answer the question
3. Extracted the location argument: `"San Francisco"`
4. Returned a tool call instead of text (`"content": null`)
5. Set `"finish_reason": "tool_calls"` to indicate it's waiting for function execution

**This is correct behavior!** In a real application, you would:
1. Execute the actual `get_weather("San Francisco")` function
2. Get the result (e.g., `{"temperature": 65, "condition": "sunny"}`)
3. Send the result back to the model in a follow-up request
4. The model would then generate a natural language response using that data

**Test without tools (baseline):**

```bash
# Compare: same question without tool definition
curl https://$ROUTE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<env>-qwen25-05b-instruct","messages":[{"role":"user","content":"What is the weather in San Francisco?"}]}' | jq '.'

# Expected: Model responds with text like "I cannot check real-time weather data..."
# (because it has no tool to call)
```

---

## Scenario 3: Change Max Model Length

**What it does:** Sets the maximum context length (input + output tokens) the model can handle. Longer context allows for longer conversations but uses more memory.

### Patch to Apply

Add this to your overlay's `kustomization.yaml`:

```yaml
patches:
  # ... existing patches ...
  
  # Patch ServingRuntime to change max model length
  - target:
      kind: ServingRuntime
      name: qwen25-05b-instruct
    patch: |-
      - op: replace
        path: /spec/containers/0/args/4
        value: "16384"
```

**Values to try:**
- `4096` - Short context (4K tokens)
- `8192` - Medium context (8K tokens)
- `16384` - Long context (16K tokens)
- `32768` - Maximum context (32K tokens)

**Note:** Higher values use more GPU memory. Consider adding `--enable-chunked-prefill` for contexts > 8K:

```yaml
patches:
  # ... existing patches ...
  
  # Patch ServingRuntime for long context
  - target:
      kind: ServingRuntime
      name: qwen25-05b-instruct
    patch: |-
      - op: replace
        path: /spec/containers/0/args/4
        value: "32768"
      - op: add
        path: /spec/containers/0/args/-
        value: "--enable-chunked-prefill"
```

### How to Test

```bash
# 1. Get the route URL
ROUTE=$(oc get route <env>-qwen25-05b-instruct -n llmops-<env> -o jsonpath='{.spec.host}')

# 2. Test with short context (should work with any max-model-len)
curl https://$ROUTE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<env>-qwen25-05b-instruct",
    "messages": [
      {"role": "user", "content": "Write a short poem about AI"}
    ],
    "max_tokens": 100
  }' | jq '.'

# 3. Test with long context (generate a long prompt)
# Create a file with a long text (e.g., 10K tokens worth of text)
cat > long_prompt.txt <<EOF
Summarize the following long document:
[Paste a very long article here - several pages worth]
EOF

# Send long context request
curl https://$ROUTE/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"<env>-qwen25-05b-instruct\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"$(cat long_prompt.txt | tr '\n' ' ')\"}
    ],
    \"max_tokens\": 500
  }"

# 4. Check if request succeeds or fails with context length error
# If max-model-len is too small, you'll see:
# "error": "maximum context length exceeded"

# 5. Verify the setting in the pod
POD=$(oc get pod -n llmops-<env> -l component=predictor -o jsonpath='{.items[0].metadata.name}')
oc logs -n llmops-<env> $POD | grep "max_model_len"

# Should show: "max_model_len=16384" (or whatever you set)
```

**Expected behavior:**
- Requests with total tokens (input + output) under max-model-len succeed
- Requests exceeding max-model-len fail with context length error
- Longer max-model-len uses more GPU memory


---

## How to Apply These Patches

### Step 1: Choose Your Environment and Scenario

Decide which environment (dev, staging, or production) and which scenario you want to apply.

### Step 2: Edit the Kustomization File

Open the appropriate overlay file:
```bash
# For staging
vim deploy_model/overlays/staging/kustomization.yaml

# For production
vim deploy_model/overlays/production/kustomization.yaml

# For dev
vim deploy_model/overlays/dev/kustomization.yaml
```

### Step 3: Add the Patch

Copy the patch from the scenario above and add it to the `patches:` section:

```yaml
patches:
  # Existing InferenceService patches
  - target:
      kind: InferenceService
      name: qwen25-05b-instruct
    patch: |-
      # ... existing InferenceService patches ...
  
  # NEW: Add ServingRuntime patch from scenario
  - target:
      kind: ServingRuntime
      name: qwen25-05b-instruct
    patch: |-
      # Paste the patch from scenario here
```

### Step 4: Test Locally (Optional)

```bash
# Build and verify the patch
kustomize build deploy_model/overlays/staging/ | grep -A 50 "kind: ServingRuntime"

# Check that your new args appear in the output
```

### Step 5: Commit and Push

```bash
git add deploy_model/overlays/
git commit -m "Add vLLM parameter: <scenario-name> for <environment>"
git push
```

### Step 6: Sync in ArgoCD

- Go to ArgoCD UI
- Click on the application (e.g., `llmops-staging`)
- Click **SYNC**
- Wait for deployment to complete

### Step 7: Verify Deployment

```bash
# Check ServingRuntime was updated
oc get servingruntime <env>-qwen25-05b-instruct -n llmops-<env> -o yaml | grep -A 30 args:

# Check pod is running with new args
POD=$(oc get pod -n llmops-<env> -l component=predictor -o jsonpath='{.items[0].metadata.name}')
oc get pod -n llmops-<env> $POD -o yaml | grep -A 30 args:

# Check logs for confirmation
oc logs -n llmops-<env> $POD | head -50
```

### Step 8: Test with curl

Use the test commands from the scenario above.

---

## Combining Multiple Scenarios

You can combine multiple scenarios in a single patch:

```yaml
patches:
  - target:
      kind: ServingRuntime
      name: qwen25-05b-instruct
    patch: |-
      # Scenario 1: GPU utilization
      - op: add
        path: /spec/containers/0/args/-
        value: "--gpu-memory-utilization"
      - op: add
        path: /spec/containers/0/args/-
        value: "0.9"
      
      # Scenario 2: Tool use
      - op: add
        path: /spec/containers/0/args/-
        value: "--enable-auto-tool-choice"
      - op: add
        path: /spec/containers/0/args/-
        value: "--tool-call-parser"
      - op: add
        path: /spec/containers/0/args/-
        value: "hermes"
      
      # Scenario 3: Max model length
      - op: replace
        path: /spec/containers/0/args/4
        value: "16384"
```

---

## Troubleshooting

### Patch Doesn't Apply

```bash
# Check for syntax errors
kustomize build deploy_model/overlays/staging/

# Common issues:
# - Missing quotes around values
# - Wrong indentation
# - Wrong path (check arg index)
```

### Pod Fails to Start

```bash
# Check pod status
oc get pods -n llmops-<env>

# Check events
oc get events -n llmops-<env> --sort-by='.lastTimestamp' | tail -20

# Check logs
oc logs -n llmops-<env> <pod-name>

# Common issues:
# - Invalid vLLM argument
# - Out of memory (reduce GPU utilization or max-model-len)
# - Draft model not found (check speculative-model path)
```

### Changes Not Taking Effect

```bash
# Verify the ServingRuntime was updated
oc get servingruntime <env>-qwen25-05b-instruct -n llmops-<env> -o yaml

# Check if pod picked up new args
oc get pod -n llmops-<env> -l component=predictor -o yaml | grep -A 50 args:

# Force pod restart if needed
oc delete pod -n llmops-<env> -l component=predictor
```

---

## Quick Reference

| Scenario | Key Parameter | Typical Values | Impact |
|----------|---------------|----------------|--------|
| GPU Utilization | `--gpu-memory-utilization` | 0.7, 0.85, 0.9, 0.95 | Throughput, OOM risk |
| Tool Use | `--enable-auto-tool-choice` | enabled/disabled | Function calling |
| Max Model Length | `--max-model-len` | 4K, 8K, 16K, 32K | Context size, memory |

---

## Pod Inspection Commands

Useful commands for checking your deployment and verifying changes:

### Get Pod Name
```bash
# Get the predictor pod name
POD=$(oc get pod -n llmops-<env> -l component=predictor -o jsonpath='{.items[0].metadata.name}')
echo $POD
```

### Check GPU Usage
```bash
# Full GPU stats
oc exec -n llmops-<env> $POD -c kserve-container -- nvidia-smi

# Just memory usage (cleaner output)
oc exec -n llmops-<env> $POD -c kserve-container -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# Continuous monitoring (updates every 1 second)
oc exec -n llmops-<env> $POD -c kserve-container -- nvidia-smi -l 1
```

### Interactive Shell Access
```bash
# Enter the pod's shell
oc exec -it -n llmops-<env> $POD -c kserve-container -- /bin/bash

# Once inside, useful commands:
# - nvidia-smi                    # Check GPU
# - ps aux | grep python          # See running processes
# - env | grep -i cuda            # Check CUDA environment
# - cat /proc/meminfo             # Check system memory
# - df -h                         # Check disk usage
# - exit                          # Leave the shell
```

### Check vLLM Arguments
```bash
# See all args passed to vLLM
oc get pod -n llmops-<env> $POD -o yaml | grep -A 50 "args:"

# Or check the ServingRuntime directly
oc get servingruntime <env>-qwen25-05b-instruct -n llmops-<env> -o yaml | grep -A 30 "args:"
```

### Check Logs
```bash
# View recent logs
oc logs -n llmops-<env> $POD -c kserve-container | tail -50

# Follow logs in real-time
oc logs -n llmops-<env> $POD -c kserve-container -f

# Search for specific settings
oc logs -n llmops-<env> $POD -c kserve-container | grep -i "gpu_memory_utilization"
oc logs -n llmops-<env> $POD -c kserve-container | grep -i "max_model_len"
oc logs -n llmops-<env> $POD -c kserve-container | grep -i "speculative"
oc logs -n llmops-<env> $POD -c kserve-container | grep -i "tool"
```

### Check Pod Status
```bash
# Pod status
oc get pod -n llmops-<env> $POD

# Detailed pod info
oc describe pod -n llmops-<env> $POD

# Check events
oc get events -n llmops-<env> --sort-by='.lastTimestamp' | tail -20
```

### List All Containers in Pod
```bash
# See what containers are in the pod
oc get pod -n llmops-<env> $POD -o jsonpath='{.spec.containers[*].name}'

# Typical output: kserve-container modelcar
```

### Quick Verification After Changes
```bash
# One-liner to verify GPU utilization
POD=$(oc get pod -n llmops-<env> -l component=predictor -o jsonpath='{.items[0].metadata.name}') && \
oc exec -n llmops-<env> $POD -c kserve-container -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# One-liner to check vLLM args
POD=$(oc get pod -n llmops-<env> -l component=predictor -o jsonpath='{.items[0].metadata.name}') && \
oc logs -n llmops-<env> $POD -c kserve-container | grep -E "gpu_memory_utilization|max_model_len|speculative|tool" | head -10
```

---

**Happy experimenting!**
