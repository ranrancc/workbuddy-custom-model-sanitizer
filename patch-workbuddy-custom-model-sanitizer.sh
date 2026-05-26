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
  'if(ev&&this.isCustomModelRequest(el,ec)){let ei=!1,ea=!0===ec?.supportsImages,eu=!1!==ec?.supportsToolCall,ed=ei=>{if(!ei)return null;if("string"==typeof ei)return{url:ei};if("object"==typeof ei&&"string"==typeof ei.url){let ea={url:ei.url};return"string"==typeof ei.detail&&(ea.detail=ei.detail),ea}return null},ep=el=>{if(null==el)return"";if("string"==typeof el)return el;if(Array.isArray(el)){if(ea){let ea=[];for(let eu of el)if("string"==typeof eu)ea.push({type:"text",text:eu});else if(eu&&"object"==typeof eu){if(("text"===eu.type||"input_text"===eu.type)&&("string"==typeof eu.text||"string"==typeof eu.input_text))ea.push({type:"text",text:eu.text||eu.input_text});else if("image_url"===eu.type){let el=ed(eu.image_url);el&&ea.push({type:"image_url",image_url:el})}else if("input_image"===eu.type){let el=ed(eu.image_url||eu.url||eu.image);el&&ea.push({type:"image_url",image_url:el})}else("string"==typeof eu.text||"string"==typeof eu.input_text)&&ea.push({type:"text",text:eu.text||eu.input_text})}return ea.length?ea:""}return el.map(ei=>"string"==typeof ei?ei:ei&&"object"==typeof ei&&("string"==typeof ei.text||"string"==typeof ei.input_text)?ei.text||ei.input_text:"").filter(Boolean).join("\\n")}return"object"==typeof el&&"string"==typeof el.text?el.text:String(el)},eG=ei=>Array.isArray(ei)?ei.map(ei=>{let ea=ei?.function||{};if(!ei?.id||"string"!=typeof ea.name)return null;let el={id:ei.id,type:"function",function:{name:ea.name,arguments:"string"==typeof ea.arguments?ea.arguments:JSON.stringify(ea.arguments??{})}};return el}).filter(Boolean):void 0,em=ei=>Array.isArray(ei)?ei.map(ei=>{let ea=ei?.function||ei;if(!ea||"string"!=typeof ea.name)return null;let el={type:"function",function:{name:ea.name}};return"string"==typeof ea.description&&(el.function.description=ea.description),ea.parameters&&"object"==typeof ea.parameters&&(el.function.parameters=ea.parameters),el}).filter(Boolean):void 0,ef=ei=>"system"===ei||"developer"===ei?"system":"assistant"===ei?"assistant":"tool"===ei||"toolResult"===ei||"function"===ei?"tool":"user";Array.isArray(ev.messages)&&(ev.messages=ev.messages.map(ea=>{if(!ea||"object"!=typeof ea)return null;let el=ef(ea.role),ec=ep(ea.content);if("tool"===el&&!ea.tool_call_id&&!ea.toolCallId){el="user";ec="string"==typeof ec&&ec?"Tool result:\\n"+ec:"Tool result: (empty)"}let eu={role:el,content:ec};ea.name&&(eu.name=ea.name),ea.tool_call_id?eu.tool_call_id=ea.tool_call_id:ea.toolCallId&&(eu.tool_call_id=ea.toolCallId);let ed=eG(ea.tool_calls);ed?.length&&(eu.tool_calls=ed);return!eu.content&&"assistant"===eu.role&&!eu.tool_calls?null:eu}).filter(Boolean),eA=!0,this.logger.debug(`Sanitized messages for custom model ${el}`)),eu?Array.isArray(ev.tools)&&(ev.tools=em(ev.tools),ev.tools?.length||(delete ev.tools),eA=!0):(void 0!==ev.tools||void 0!==ev.tool_choice)&&(delete ev.tools,delete ev.tool_choice,eA=!0,this.logger.info(`Stripped tools/tool_choice from request body (model ${el} does not support tool calls)`));if(eu&&ev.tool_choice&&"object"==typeof ev.tool_choice){let ei=ev.tool_choice?.function?.name;"function"===ev.tool_choice.type&&"string"==typeof ei?ev.tool_choice={type:"function",function:{name:ei}}:delete ev.tool_choice,eA=!0}}eA&&ev&&"string"==typeof eh&&(eh=JSON.stringify(ev));';

const legacyExitReplacement =
  'if(ev&&this.isCustomModelRequest(el,ec)&&Array.isArray(ev.messages)){let ei=!1;ev.messages=ev.messages.map(ea=>{if(!ea||"object"!=typeof ea)return null;let ec="system"===ea.role||"developer"===ea.role?"system":"assistant"===ea.role?"assistant":"tool"===ea.role?"tool":"user",eu=ea.content;if(Array.isArray(eu))eu=eu.map(ei=>"string"==typeof ei?ei:ei&&"object"==typeof ei&&("string"==typeof ei.text||"string"==typeof ei.input_text)?ei.text||ei.input_text:"").filter(Boolean).join("\\n"),ei=!0;else if(null==eu)eu="";else if("string"!=typeof eu){eu="object"==typeof eu&&"string"==typeof eu.text?eu.text:String(eu),ei=!0}if("tool"===ec&&!ea.tool_call_id&&!ea.toolCallId){ec="user";eu=eu?"Tool result:\\n"+eu:"Tool result: (empty)"}let ed={role:ec,content:eu};return ea.name&&(ed.name=ea.name),ea.tool_call_id?ed.tool_call_id=ea.tool_call_id:ea.toolCallId&&(ed.tool_call_id=ea.toolCallId),Array.isArray(ea.tool_calls)&&(ed.tool_calls=ea.tool_calls),!ed.content&&"assistant"===ed.role&&!ed.tool_calls?null:ed}).filter(Boolean),eA=!0,ei&&this.logger.debug(`Sanitized messages for custom model ${el}`)}ev&&this.isCustomModelRequest(el,ec)&&ec?.supportsToolCall===!1&&(void 0!==ev.tools||void 0!==ev.tool_choice)&&(delete ev.tools,delete ev.tool_choice,eA=!0,this.logger.info(`Stripped tools/tool_choice from request body (model ${el} does not support tool calls)`)),eA&&ev&&"string"==typeof eh&&(eh=JSON.stringify(ev));';

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

if (text.includes(exitReplacement)) {
  console.log("exit sanitizer already patched");
} else if (text.includes(legacyExitReplacement)) {
  text = text.replace(legacyExitReplacement, exitReplacement);
  changed = true;
  console.log("upgraded legacy exit sanitizer");
} else if (text.includes("Sanitized messages for custom model")) {
  const marker = text.indexOf("Sanitized messages for custom model");
  const legacyStart = 'if(ev&&this.isCustomModelRequest(el,ec)';
  const legacyEnd = 'let ek={url:eu,method:ed';
  const start = marker >= 0 ? text.lastIndexOf(legacyStart, marker) : -1;
  const end = marker >= 0 ? text.indexOf(legacyEnd, marker) : -1;
  if (start < 0 || end < 0) {
    console.error("found legacy sanitizer marker, but could not locate legacy sanitizer bounds");
    process.exit(2);
  }
  text = text.slice(0, start) + exitReplacement + text.slice(end);
  changed = true;
  console.log("upgraded bounded legacy exit sanitizer");
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

log "Patching streaming tool-call name fallback"
node - "$CLI_BUNDLE" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");

const oldText =
  'content_block:{type:"tool_use",id:ei.id,name:ei.function?.name||"",input:{}}}';

const newText =
  'content_block:{type:"tool_use",id:ei.id,name:ei.function?.name||("string"==typeof ei.id&&ei.id.startsWith("functions.")?ei.id.slice(10).split(":")[0]:""),input:{}}}';

if (text.includes(newText)) {
  console.log("streaming tool-call name fallback already patched");
} else {
  const count = text.split(oldText).length - 1;
  if (count !== 1) {
    console.error(`expected one streaming tool-call fallback match, got ${count}`);
    process.exit(2);
  }
  text = text.replace(oldText, newText);
  fs.writeFileSync(file, text);
  console.log("patched streaming tool-call name fallback");
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
