# workbuddy-custom-model-sanitizer

Local patcher for WorkBuddy custom OpenAI-compatible models.

It fixes a WorkBuddy 4.22.x custom-model compatibility issue where WorkBuddy can send internal message fields to strict OpenAI-compatible providers such as Fireworks.

Typical error:

```text
400 Extra inputs are not permitted, field: 'messages[1].agent', value: 'cli'
```

Other possible rejected fields include:

```text
messageId, model, traceId, conversationRequestId, rawUsage, usage, reasoning, annotations
```

## What This Fixes

WorkBuddy keeps rich internal message objects for its own UI, traces, usage display, reasoning display, and agent bookkeeping. Those internal fields should not be sent to an OpenAI-compatible `/chat/completions` endpoint.

Some providers ignore unknown fields. Strict providers reject them.

This patch adds a final sanitizer before WorkBuddy sends custom-model requests. For custom models, it keeps the request body close to the OpenAI Chat Completions shape:

```json
{
  "role": "user",
  "content": "hello"
}
```

It preserves common standard fields when present:

```text
role, content, name, tool_calls, tool_call_id
```

It removes WorkBuddy-only metadata from outbound requests.

## Supported Target

Tested against:

```text
WorkBuddy 4.22.16 on macOS
```

Expected app layout:

```text
/Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy.js
```

## Usage

Quit WorkBuddy first, then run:

```bash
git clone https://github.com/YOUR_NAME/workbuddy-custom-model-sanitizer.git
cd workbuddy-custom-model-sanitizer
bash patch-workbuddy-custom-model-sanitizer.sh
```

If WorkBuddy is installed somewhere else:

```bash
WORKBUDDY_APP_PATH="/path/to/WorkBuddy.app" bash patch-workbuddy-custom-model-sanitizer.sh
```

For testing against a copied app bundle only, you can bypass the running-process guard:

```bash
WORKBUDDY_SKIP_RUNNING_CHECK=1 WORKBUDDY_APP_PATH="/tmp/WorkBuddy.app" bash patch-workbuddy-custom-model-sanitizer.sh
```

## Restore

The script creates a timestamped backup under:

```text
/Applications/WorkBuddy.app/Contents/Resources/workbuddy-custom-model-sanitizer-backups/
```

At the end of a successful run, it prints the exact restore command, for example:

```bash
cp '/Applications/WorkBuddy.app/Contents/Resources/workbuddy-custom-model-sanitizer-backups/codebuddy.js.20260526-120000.bak' '/Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy.js'
```

## Custom Model Config Note

WorkBuddy's local custom model config is usually:

```text
~/.workbuddy/models.json
```

In WorkBuddy 4.22.16, this file is an array, not an object:

```json
[
  {
    "id": "accounts/fireworks/routers/kimi-k2p6-turbo",
    "name": "Kimi K2P6 Turbo",
    "vendor": "Custom",
    "url": "https://api.fireworks.ai/inference/v1/chat/completions",
    "apiKey": "YOUR_API_KEY",
    "supportsToolCall": true,
    "supportsImages": false,
    "supportsReasoning": false,
    "useCustomProtocol": false
  }
]
```

Do not commit real API keys.

## Why Other Custom Models May Fail

This issue is not Fireworks-specific. Any strict OpenAI-compatible provider may reject WorkBuddy's internal message fields. More permissive gateways may appear to work because they ignore unknown fields.

The bug is most likely to appear after multi-turn conversations, assistant history, reasoning output, usage data, tool calls, or content block arrays enter the conversation history.

## Limitations

- This patch is local and may be overwritten by WorkBuddy updates.
- It focuses on text and normal tool-call compatibility.
- For custom providers that need image content blocks, a provider-specific sanitizer may be safer than flattening content arrays to text.
- This is not an official WorkBuddy patch.
