#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${WORKBUDDY_APP_PATH:-/Applications/WorkBuddy.app}"
CLI_BUNDLE="$APP_PATH/Contents/Resources/app.asar.unpacked/cli/dist/codebuddy.js"
BACKUP_DIR="${WORKBUDDY_BACKUP_DIR:-$APP_PATH/Contents/Resources/workbuddy-custom-model-sanitizer-backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"

log() {
  printf '[workbuddy-custom-model-sanitizer] %s\n' "$*"
}

fail() {
  printf '[workbuddy-custom-model-sanitizer] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -f "$CLI_BUNDLE" ]] || fail "WorkBuddy CLI bundle not found: $CLI_BUNDLE"
command -v node >/dev/null 2>&1 || fail "node is required"

if [[ "${WORKBUDDY_SKIP_RUNNING_CHECK:-}" != "1" ]] && pgrep -f "WorkBuddy.app" >/dev/null 2>&1; then
  log "WorkBuddy appears to be running. Please quit it before patching."
  fail "WorkBuddy is still running"
fi

mkdir -p "$BACKUP_DIR"
BACKUP_PATH="$BACKUP_DIR/codebuddy.js.$STAMP.bak"
cp "$CLI_BUNDLE" "$BACKUP_PATH"
log "Backup created: $BACKUP_PATH"

log "Patching custom model request sanitizer"
node - "$CLI_BUNDLE" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");

const earlyNeedle =
  'let CustomModelFieldCleanupPlugin=class CustomModelFieldCleanupPlugin{constructor(){this.name="custom-model-field-cleanup"}matches(ei){if(ei.modelId.startsWith(rZ.CUSTOM_LOCAL_MODEL_PREFIX))return!0;let ea=ei.modelConfig;return ea?.trustLevel===rZ.ModelTrustLevel.CUSTOM||Array.isArray(ea?.tags)&&ea.tags.includes(rZ.MODEL_TAG_CUSTOM)}apply(ei,ea){"xhigh"===ei.reasoning_effort&&(ei.reasoning_effort="high")}};';

const earlyReplacement =
  'let CustomModelFieldCleanupPlugin=class CustomModelFieldCleanupPlugin{constructor(){this.name="custom-model-field-cleanup"}matches(ei){if(ei.modelId.startsWith(rZ.CUSTOM_LOCAL_MODEL_PREFIX))return!0;let ea=ei.modelConfig;return ea?.trustLevel===rZ.ModelTrustLevel.CUSTOM||Array.isArray(ea?.tags)&&ea.tags.includes(rZ.MODEL_TAG_CUSTOM)}apply(ei,ea){"xhigh"===ei.reasoning_effort&&(ei.reasoning_effort="high"),Array.isArray(ei.messages)&&(ei.messages=ei.messages.map(ei=>this.cleanMessage(ei)).filter(Boolean))}cleanMessage(ei){if(!ei||"object"!=typeof ei)return null;let ea=this.cleanRole(ei.role),el=this.cleanContent(ei.content);if(("toolResult"===ei.role||"tool"===ei.role)&&!ei.tool_call_id&&!ei.toolCallId){ea="user";el=el?"Tool result:\\n"+el:"Tool result: (empty)"}let ec={role:ea,content:el};return ei.name&&(ec.name=ei.name),ei.tool_call_id?ec.tool_call_id=ei.tool_call_id:ei.toolCallId&&(ec.tool_call_id=ei.toolCallId),Array.isArray(ei.tool_calls)&&(ec.tool_calls=ei.tool_calls),!ec.content&&"assistant"===ec.role&&!ec.tool_calls?null:ec}cleanRole(ei){return"system"===ei||"developer"===ei?"system":"assistant"===ei?"assistant":"tool"===ei||"toolResult"===ei?"tool":"user"}cleanContent(ei){if(null==ei)return"";if("string"==typeof ei)return ei;if(Array.isArray(ei))return ei.map(ei=>"string"==typeof ei?ei:ei&&"object"==typeof ei&&("string"==typeof ei.text||"string"==typeof ei.input_text)?ei.text||ei.input_text:"").filter(Boolean).join("\\n");return"object"==typeof ei&&"string"==typeof ei.text?ei.text:String(ei)}};';

const exitNeedle =
  'if(ev&&ec?.tags?.includes("custom")&&!1===ec.supportsImages&&Array.isArray(ev.messages)){let ei=!1;for(let ea of ev.messages)if(Array.isArray(ea.content)){let el=ea.content.filter(ei=>"text"===ei.type).map(ei=>ei.text);ea.content=el.join("\\n"),ei=!0}ei&&(eA=!0,this.logger.debug(`Flattened array content to string for custom model ${el}`))}ev&&this.isCustomModelRequest(el,ec)&&ec?.supportsToolCall===!1&&(void 0!==ev.tools||void 0!==ev.tool_choice)&&(delete ev.tools,delete ev.tool_choice,eA=!0,this.logger.info(`Stripped tools/tool_choice from request body (model ${el} does not support tool calls)`)),eA&&ev&&"string"==typeof eh&&(eh=JSON.stringify(ev));';

const exitReplacement =
  'if(ev&&this.isCustomModelRequest(el,ec)&&Array.isArray(ev.messages)){let ei=!1;ev.messages=ev.messages.map(ea=>{if(!ea||"object"!=typeof ea)return null;let ec="system"===ea.role||"developer"===ea.role?"system":"assistant"===ea.role?"assistant":"tool"===ea.role?"tool":"user",eu=ea.content;if(Array.isArray(eu))eu=eu.map(ei=>"string"==typeof ei?ei:ei&&"object"==typeof ei&&("string"==typeof ei.text||"string"==typeof ei.input_text)?ei.text||ei.input_text:"").filter(Boolean).join("\\n"),ei=!0;else if(null==eu)eu="";else if("string"!=typeof eu){eu="object"==typeof eu&&"string"==typeof eu.text?eu.text:String(eu),ei=!0}if("tool"===ec&&!ea.tool_call_id&&!ea.toolCallId){ec="user",eu=eu?"Tool result:\\n"+eu:"Tool result: (empty)",ei=!0}let ed={role:ec,content:eu};return ea.name&&(ed.name=ea.name),ea.tool_call_id?ed.tool_call_id=ea.tool_call_id:ea.toolCallId&&(ed.tool_call_id=ea.toolCallId),Array.isArray(ea.tool_calls)&&(ed.tool_calls=ea.tool_calls),!ed.content&&"assistant"===ed.role&&!ed.tool_calls?null:ed}).filter(Boolean),eA=!0,ei&&this.logger.debug(`Sanitized messages for custom model ${el}`)}ev&&this.isCustomModelRequest(el,ec)&&ec?.supportsToolCall===!1&&(void 0!==ev.tools||void 0!==ev.tool_choice)&&(delete ev.tools,delete ev.tool_choice,eA=!0,this.logger.info(`Stripped tools/tool_choice from request body (model ${el} does not support tool calls)`)),eA&&ev&&"string"==typeof eh&&(eh=JSON.stringify(ev));';

let changed = false;

if (text.includes(earlyReplacement)) {
  console.log("early sanitizer already patched");
} else {
  const count = text.split(earlyNeedle).length - 1;
  if (count !== 1) {
    console.error(`expected one early sanitizer match, got ${count}`);
    process.exit(2);
  }
  text = text.replace(earlyNeedle, earlyReplacement);
  changed = true;
  console.log("patched early sanitizer");
}

if (text.includes("Sanitized messages for custom model")) {
  console.log("exit sanitizer already patched");
} else {
  const count = text.split(exitNeedle).length - 1;
  if (count !== 1) {
    console.error(`expected one exit sanitizer match, got ${count}`);
    process.exit(2);
  }
  text = text.replace(exitNeedle, exitReplacement);
  changed = true;
  console.log("patched exit sanitizer");
}

if (changed) {
  fs.writeFileSync(file, text);
}
NODE

log "Checking JavaScript syntax"
node --check "$CLI_BUNDLE" >/dev/null

if command -v codesign >/dev/null 2>&1; then
  log "Applying ad-hoc code signature"
  codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || log "codesign failed; WorkBuddy may still run, but macOS could complain"
fi

log "Patch complete. Restart WorkBuddy."
log "To restore: cp '$BACKUP_PATH' '$CLI_BUNDLE'"
