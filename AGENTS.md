# Agent Instructions

This repository documents and patches a WorkBuddy custom-model compatibility bug.

## Goal

Help OpenClaw, Claude Code, Codex, or another local coding agent understand and reproduce the fix for strict OpenAI-compatible custom model providers.

## Patch Name

Use this name for the actual design:

```text
workbuddy-openai-compatible-adapter
```

The old name, `workbuddy-custom-model-sanitizer`, is kept only as a compatibility wrapper because early versions of this repo used it.

## Problem Summary

WorkBuddy 4.22.x can send internal message objects to custom OpenAI-compatible `/chat/completions` providers.

Example provider error:

```text
400 Extra inputs are not permitted, field: 'messages[1].agent', value: 'cli'
```

Rejected fields may include:

```text
agent, messageId, model, traceId, conversationRequestId, rawUsage, usage, reasoning, annotations
```

These are WorkBuddy internal fields. They should remain in WorkBuddy's local state and traces, but they should not be sent to third-party model APIs.

## First-Principles Model

Treat this as a protocol-boundary bug, not as a model-selection bug.

WorkBuddy has an internal protocol:

- Conversation metadata
- Agent bookkeeping
- Trace ids
- Usage objects
- Reasoning display state
- Tool execution state

OpenAI-compatible providers expect a wire protocol:

- `messages[].role`
- `messages[].content`
- optional OpenAI-standard multimodal blocks
- optional OpenAI-standard function tool schemas
- optional assistant `tool_calls`
- optional tool result `tool_call_id`

The patch should translate at the boundary.

## Intended Fix

Patch WorkBuddy in three places.

Outbound HTTP adapter:

- Keep: `role`, `content`, `name`, `tool_calls`, `tool_call_id`
- Normalize roles to OpenAI-compatible values
- Preserve OpenAI-style `image_url` blocks when `supportsImages === true`
- Convert content arrays to text for text-only custom models
- Preserve and normalize OpenAI-style function tools when `supportsToolCall !== false`
- Strip `tools` and `tool_choice` when `supportsToolCall === false`
- Convert unpaired tool results to user-visible text
- Remove WorkBuddy-only metadata
- Leave WorkBuddy's local conversation storage alone

Inbound streaming adapter:

- Accumulate `delta.tool_calls` by `index`
- Preserve id, name, and argument deltas independently
- Open a WorkBuddy `tool_use` block only when the tool name is known
- Use `functions.Name:n` ids as a narrow WorkBuddy-specific name fallback
- Stop all started tool blocks at `finish_reason: "tool_calls"`

Model response adapter:

- In `resolveFunctionOrHandoff`, recover an empty `function_call.name` from `call_id`, `callId`, or `id` when it uses WorkBuddy's `functions.Name:n` pattern
- This is the execution-side protocol boundary; UI stream events can look correct while this path still has an empty name

Kimi K2.6 profile:

- WorkBuddy has built-in Moonshot/Kimi plugins for `kimi-k2.5` and `kimi-k2.6`
- Extend only the tool-result content-array plugin to also match `kimi-k2p6` and `kimi-k2p6-turbo`
- Do not extend thinking temperature or reasoning placeholder plugins for this Fireworks route
- Strip request-level `reasoning`, `reasoning_effort`, and `reasoning_summary` when a custom model has `supportsReasoning: false`
- Keep this model-specific; do not apply Moonshot behavior to all custom models

Executor guard:

- If an internal tool call still has an empty `name`, derive it from `functions.Name:n`
- Keep this as a fuse, not the primary conversion layer

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

## Verification

After patching:

```bash
node --check /Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy.js
```

Then fully quit and restart WorkBuddy.

If debugging is needed, inspect WorkBuddy logs and traces with targeted commands:

```bash
rg -n "Extra inputs|Tool  not found|tool_call|finish_reason|Error response" ~/.workbuddy/logs
```

## Safety

- Always create a backup before editing `codebuddy.js`.
- Do not commit API keys from `~/.workbuddy/models.json`.
- Avoid changing unrelated app resources.
- WorkBuddy updates may replace the patched file; rerun the patcher after updates.
