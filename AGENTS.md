# Agent Instructions

This repository documents and patches a WorkBuddy custom-model compatibility bug.

## Goal

Help OpenClaw, Claude Code, Codex, or another local coding agent understand and reproduce the fix for strict OpenAI-compatible custom model providers.

## Problem Summary

WorkBuddy 4.22.x can send internal message fields to custom OpenAI-compatible `/chat/completions` providers.

Example provider error:

```text
400 Extra inputs are not permitted, field: 'messages[1].agent', value: 'cli'
```

Rejected fields may include:

```text
agent, messageId, model, traceId, conversationRequestId, rawUsage, usage, reasoning, annotations
```

These are WorkBuddy internal fields. They should remain in WorkBuddy's local state and traces, but they should not be sent to third-party model APIs.

## Patch Name

Use this name consistently:

```text
workbuddy-custom-model-sanitizer
```

## Files Of Interest

Default WorkBuddy CLI bundle:

```text
/Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy.js
```

Default local custom model config:

```text
~/.workbuddy/models.json
```

In WorkBuddy 4.22.16, `models.json` is an array. Do not rewrite it as `{ "models": [...] }`, because that can break the WorkBuddy model picker UI.

## Intended Fix

Patch WorkBuddy's custom-model request path so outbound requests are sanitized before HTTP send.

For custom models:

- Keep: `role`, `content`, `name`, `tool_calls`, `tool_call_id`
- Normalize roles to OpenAI-compatible values
- Preserve OpenAI-style `image_url` blocks when `supportsImages === true`
- Convert content arrays to text for text-only custom models
- Preserve and normalize OpenAI-style function tools when `supportsToolCall !== false`
- Strip `tools` and `tool_choice` when `supportsToolCall === false`
- Patch WorkBuddy's streaming OpenAI-to-tool-use adapter so a chunk with id `functions.Name:n` and an initially missing `function.name` uses `Name` as a fallback.
- Convert unpaired tool results to user-visible text
- Remove WorkBuddy-only metadata
- Preserve tool calls when present
- Leave WorkBuddy's local conversation storage alone

The key idea is to sanitize at the outbound HTTP adapter layer, not only earlier in the request pipeline. Earlier plugins can be bypassed or followed by later transformations.

Prefer capability-aware strictness:

- Be strict about WorkBuddy private fields.
- Be permissive about standard OpenAI capabilities the model declares, especially image input and function tools.
- Drop provider-specific or unknown fields unless a documented provider-specific adapter is being added.

## Verification

After patching:

```bash
node --check /Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy.js
```

Then fully quit and restart WorkBuddy.

If debugging is needed, inspect WorkBuddy process args:

```bash
ps aux | rg -i 'WorkBuddy|codebuddy|workbuddy'
```

## Safety

- Always create a backup before editing `codebuddy.js`.
- Do not commit API keys from `~/.workbuddy/models.json`.
- Avoid changing unrelated app resources.
- WorkBuddy updates may replace the patched file; rerun the patcher after updates.
