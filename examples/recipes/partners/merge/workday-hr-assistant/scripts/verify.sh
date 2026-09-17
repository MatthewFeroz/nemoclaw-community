#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Allowed/denied validation for the hr-reader role.
#
# WHAT THIS PROVES, AND WHERE THE BOUNDARY IS
# The authorization boundary is the Agent Handler Tool Pack, enforced
# server-side. It is not the model's restraint and not the OpenShell network
# policy: OpenShell keeps the credential out of the sandbox and bounds the
# destination, but a managed MCP registration permits every tool the server
# advertises. Narrowing the Tool Pack is what removes a capability.
#
# Case 2 is the point of the example. A prompt injection can ask for
# `approve_report` all it likes; if the pack does not contain that tool, Agent
# Handler never advertises it and refuses the call before any Workday request.
#
# Cases 1-3 need only the scoped key, so they run without a linked Concur
# account. Case 4 needs live Concur authorization and is skipped (not failed)
# when the credential is not connected. Case 5 runs only after you revoke.
#
# Section B drives a real agent turn so the sandbox path is exercised as the
# agent would. Model behavior is non-deterministic, so an agent turn is never
# used to establish a security property — only to show the integration works.
#
# Exit code: 0 if every executed case matched its expected outcome, else 1.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/_lib.sh"

command -v curl    >/dev/null || { echo "curl not in PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not in PATH — needed to read JSON-RPC replies" >&2; exit 1; }

require_var MERGE_AH_MCP_TOKEN
require_var MERGE_AH_TOOL_PACK_ID
require_var MERGE_AH_REGISTERED_USER_ID

SYSTEM_NAME="${SYSTEM_NAME:-the connected system}"
READER_TOOL="${READER_TOOL:-workday__list_workers}"
EXCLUDED_TOOL="${EXCLUDED_TOOL:-workday__request_one_time_payment}"
MCP_URL="$(ah_mcp_url)"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP  $1"; SKIP=$((SKIP+1)); }

# Extract the advertised tool names from a tools/list reply.
tool_names() {
  python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for t in d.get("result",{}).get("tools",[]): print(t.get("name",""))
'
}

# True when a tools/call reply is an error (isError, or a JSON-RPC error).
is_error_reply() {
  python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("malformed"); sys.exit(0)
if "error" in d: print("rpc_error"); sys.exit(0)
r=d.get("result",{})
if r.get("isError"): print("tool_error"); sys.exit(0)
print("ok")
'
}

# Reason string from an Agent Handler error payload, when present.
error_reason() {
  python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for item in d.get("result",{}).get("content",[]):
    try: print(json.loads(item.get("text","")).get("error_reason",""))
    except Exception: pass
'
}

echo "== Section A: authorization boundary (Agent Handler, scoped key) =="
echo "Tool Pack:       $MERGE_AH_TOOL_PACK_ID"
echo "Registered User: $MERGE_AH_REGISTERED_USER_ID"
echo

SID="$(mcp_session "$MCP_URL")" || { echo "  FAIL  could not open an MCP session — check the scoped key" >&2; exit 1; }
LIST="$(mcp_call "$MCP_URL" "$SID" tools/list '{}')"
NAMES="$(printf '%s' "$LIST" | tool_names)"
COUNT="$(printf '%s' "$NAMES" | grep -c . || true)"
echo "Advertised tools: $COUNT"

# Case 1 — the reader tool is advertised.
if printf '%s\n' "$NAMES" | grep -Fxq "$READER_TOOL"; then
  ok "case 1: '$READER_TOOL' is advertised to this role"
else
  bad "case 1: '$READER_TOOL' is NOT advertised — the Tool Pack is missing the reader tool"
fi

# Case 2 — the excluded tool is absent from the advertised set. This is the
# RBAC assertion: the capability does not exist for this role.
if printf '%s\n' "$NAMES" | grep -Fxq "$EXCLUDED_TOOL"; then
  bad "case 2: '$EXCLUDED_TOOL' IS advertised — the Tool Pack is too wide for an hr-reader role"
else
  ok "case 2: '$EXCLUDED_TOOL' is not advertised to this role"
fi

# Case 3 — calling the excluded tool is refused by Agent Handler. Runs even
# when case 2 passes: absence from the catalog and refusal on call are
# different properties, and a client can always name a tool directly.
# An error alone is NOT a pass: a missing Concur credential also errors. Only an
# authorization refusal proves the boundary. `reauth_required` means the call
# died on the credential before authorization was decided — inconclusive.
CALL="$(mcp_call "$MCP_URL" "$SID" tools/call "{\"name\":\"$EXCLUDED_TOOL\",\"arguments\":{}}")"
VERDICT="$(printf '%s' "$CALL" | is_error_reply)"
REASON="$(printf '%s' "$CALL" | error_reason)"
case "$VERDICT:$REASON" in
  ok:*)
    bad "case 3: '$EXCLUDED_TOOL' was ACCEPTED — the authorization boundary did not hold" ;;
  *:permission_denied|*:forbidden|*:unauthorized|*:tool_not_found)
    ok "case 3: '$EXCLUDED_TOOL' refused at the authorization boundary ($REASON)" ;;
  *:reauth_required)
    skip "case 3: inconclusive — the call failed on the missing Concur credential, not on authorization" ;;
  *)
    skip "case 3: inconclusive — refused with an unrecognized reason (${REASON:-$VERDICT})" ;;
esac

echo
echo "== Section B: live read =="
# Probe with the reader tool itself. A minimally-scoped pack excludes
# validate_credential, so using it here would report a missing credential when
# the real cause is correct scoping.
READ="$(mcp_call "$MCP_URL" "$SID" tools/call "{\"name\":\"$READER_TOOL\",\"arguments\":{}}")"
READ_REASON="$(printf '%s' "$READ" | error_reason)"
if [[ "$READ_REASON" == "reauth_required" ]]; then
  skip "case 4: $SYSTEM_NAME is not connected for this Registered User — run the authenticate tool and link the account"
else
  if [[ "$(printf '%s' "$READ" | is_error_reply)" == "ok" ]]; then
    ok "case 4: '$READER_TOOL' returned a result over MCP"
  else
    bad "case 4: '$READER_TOOL' failed (${READ_REASON:-unknown reason})"
  fi

  # Agent path: the same read, driven through the sandbox as the agent would.
  # Evidence of integration, never of a security property.
  if command -v nemoclaw >/dev/null && sandbox_exists "$NEMOCLAW_SANDBOX_NAME"; then
    TURN="$(nemoclaw "$NEMOCLAW_SANDBOX_NAME" agent --agent main \
      -m "Use the $MCP_SERVER_NAME MCP server to list workers. Reply with the first five worker names only." 2>&1)"
    if printf '%s' "$TURN" | grep -qiE 'error|not available|cannot'; then
      bad "case 4b: the agent turn did not complete a clean read (inspect the transcript)"
    else
      ok "case 4b: the agent completed a read through the sandbox"
    fi
  else
    skip "case 4b: sandbox '$NEMOCLAW_SANDBOX_NAME' not available for an agent turn"
  fi
fi

echo
echo "== Section D: key scope =="
# The runtime key must not be able to widen its own access. These cases fail on
# a management key, which is the point: a management key in the sandbox
# registration would silently defeat the Tool Pack boundary above.

# Case 6 — the key cannot perform management operations.
ESC="$(curl -s --max-time 25 -o /dev/null -w '%{http_code}' -X POST "$AH_BASE_URL/api/v1/tool-packs/" \
  -H "Authorization: Bearer $MERGE_AH_MCP_TOKEN" -H "Content-Type: application/json" \
  --data '{"name":"escalation-probe","description":"must be refused","connectors":[{"slug":"workday","tool_names":["request_one_time_payment"]}]}' 2>/dev/null || true)"
if [[ "$ESC" == "401" || "$ESC" == "403" ]]; then
  ok "case 6: the runtime key cannot create a Tool Pack (HTTP $ESC)"
else
  bad "case 6: the runtime key reached Tool Pack creation (HTTP $ESC) — it carries management scope"
fi

# Case 7 — the key cannot address a Tool Pack it is not bound to.
if [[ -n "${OTHER_TOOL_PACK_ID:-}" ]]; then
  OTHER_URL="$AH_BASE_URL/api/v1/tool-packs/$OTHER_TOOL_PACK_ID/registered-users/$MERGE_AH_REGISTERED_USER_ID/mcp"
  if mcp_session "$OTHER_URL" >/dev/null 2>&1; then
    bad "case 7: the key opened a session on an unbound Tool Pack"
  else
    ok "case 7: the key cannot address an unbound Tool Pack"
  fi
else
  skip "case 7: set OTHER_TOOL_PACK_ID to a pack this key is not bound to"
fi

echo
echo "== Section C: key revocation =="
# Only meaningful after you revoke the key in Agent Handler. Before revocation
# a working session is the expected state, so this reports rather than fails.
if [[ "${EXPECT_REVOKED:-0}" == "1" ]]; then
  if mcp_session "$MCP_URL" >/dev/null 2>&1; then
    bad "case 5: the revoked key still opened a session"
  else
    ok "case 5: the revoked key is refused"
  fi
else
  skip "case 5: revoke the key in the Agent Handler dashboard (the API exposes no delete), then re-run with EXPECT_REVOKED=1"
fi

echo
echo "passed=$PASS failed=$FAIL skipped=$SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
