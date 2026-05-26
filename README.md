# workbuddy-openai-compatible-adapter

Local patcher for WorkBuddy custom OpenAI-compatible models.

It fixes a WorkBuddy 4.22.x compatibility issue where the custom-model path can mix two protocols:

- WorkBuddy's internal conversation protocol, with UI/tracing/agent fields.
- The provider wire protocol expected by OpenAI-compatible `/chat/completions` APIs.

Strict providers such as Fireworks may reject the mixed request with errors like:

```text
400 Extra inputs are not permitted, field: 'messages[1].agent', value: 'cli'
```

Other rejected fields can include:

```text
messageId, model, traceId, conversationRequestId, rawUsage, usage, reasoning, annotations
```

## First Principles

The fix is not to make custom models "dumber". Image input and function tools are real OpenAI-compatible capabilities, and many providers support them.

The correct boundary is an adapter:

1. Before HTTP send, translate WorkBuddy's internal request into a strict OpenAI Chat Completions request.
2. During streaming response handling, translate OpenAI-style incremental tool calls back into WorkBuddy's internal tool-use events.
3. Keep narrow executor fallbacks as a final guard, not as the main design.

## What The Patch Does

Outbound request adapter:

- Keeps only wire-safe message fields: `role`, `content`, `name`, `tool_calls`, `tool_call_id`.
- Normalizes roles to OpenAI-compatible values.
- Preserves `image_url` content blocks when `supportsImages === true`.
- Flattens content arrays to text when the model is text-only.
- Preserves and normalizes OpenAI function tools when `supportsToolCall !== false`.
- Removes `tools` and `tool_choice` when `supportsToolCall === false`.
- Removes WorkBuddy-only metadata from outbound requests.

Inbound streaming adapter:

- Accumulates streamed `tool_calls` by `index`.
- Waits until a tool name is known before opening a WorkBuddy `tool_use` block.
- Derives a name only for WorkBuddy-style ids such as `functions.Bash:2`.
- Preserves accumulated argument deltas when the name arrives after earlier chunks.
- Stops every started tool block at `finish_reason: "tool_calls"`.

Executor fallback:

- If WorkBuddy still reaches execution with an empty tool name but an id like `functions.Name:n`, it derives `Name` as a final guard.

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
git clone https://github.com/ranrancc/workbuddy-custom-model-sanitizer.git
cd workbuddy-custom-model-sanitizer
bash patch-workbuddy-openai-compatible-adapter.sh
```

The old script name remains as a compatibility wrapper:

```bash
bash patch-workbuddy-custom-model-sanitizer.sh
```

If WorkBuddy is installed somewhere else:

```bash
WORKBUDDY_APP_PATH="/path/to/WorkBuddy.app" bash patch-workbuddy-openai-compatible-adapter.sh
```

For testing against a copied app bundle only, you can bypass the running-process guard:

```bash
WORKBUDDY_SKIP_RUNNING_CHECK=1 WORKBUDDY_APP_PATH="/tmp/WorkBuddy.app" bash patch-workbuddy-openai-compatible-adapter.sh
```

## Restore

The script creates a timestamped backup under:

```text
/Applications/WorkBuddy.app/Contents/Resources/workbuddy-openai-compatible-adapter-backups/
```

At the end of a successful run, it prints the exact restore command.

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

- This is a local patch and may be overwritten by WorkBuddy updates.
- It targets common OpenAI Chat Completions compatibility, not every provider-specific extension.
- Image support depends on the custom model config. Set `supportsImages` to `true` only when the provider/model accepts OpenAI-style `image_url` blocks.
- Tool support depends on the custom model config. Set `supportsToolCall` to `true` only when the provider/model accepts OpenAI-style function tools.
- Provider-specific fields outside the common OpenAI Chat Completions shape are intentionally dropped unless a documented provider-specific adapter is added.
- This is not an official WorkBuddy patch.
