# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Shared helpers for the workday-hr-assistant scripts. Source this from each script.
# Not meant to run on its own — no shebang.

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MCP_SERVER_NAME="${MCP_SERVER_NAME:-merge-workday}"
AH_BASE_URL="${AH_BASE_URL:-https://ah-api.merge.dev}"
NEMOCLAW_SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-workday-hr}"

# Auto-source .env if present. Idempotent, and re-sourced on every call so a
# variable added to .env after a stale shell export is not missed.
load_env() {
  [[ -f "$EXAMPLE_DIR/.env" ]] || return 0
  echo "Auto-sourcing $EXAMPLE_DIR/.env"
  set -a
  # shellcheck disable=SC1091
  . "$EXAMPLE_DIR/.env"
  set +a
}

# Fail loud if the named variable is unset or empty.
require_var() {
  local name="$1" hint="${2:-}"
  if [[ -z "${!name:-}" ]]; then
    echo "error: $name is not set — set it in $EXAMPLE_DIR/.env${hint:+ ($hint)}" >&2
    exit 1
  fi
}

# Print a command, then run it.
run() {
  echo "+ $*"
  "$@"
}

# True if the named sandbox exists on the gateway.
sandbox_exists() {
  command -v openshell >/dev/null || return 1
  openshell sandbox list --names 2>/dev/null | grep -Fxq "$1"
}

# The scoped Tool Pack MCP endpoint. Built from IDs so the recipe never stores
# a pre-assembled URL that hides which pack and user it binds.
ah_mcp_url() {
  printf '%s/api/v1/tool-packs/%s/registered-users/%s/mcp' \
    "$AH_BASE_URL" "$MERGE_AH_TOOL_PACK_ID" "$MERGE_AH_REGISTERED_USER_ID"
}

# Open an MCP session against $1 (a URL) and echo its Mcp-Session-Id.
# Returns non-zero when initialize does not yield a session.
mcp_session() {
  local url="$1" headers
  headers="$(mktemp)"
  curl -s -o /dev/null -D "$headers" --max-time 30 -X POST "$url" \
    -H "Authorization: Bearer $MERGE_AH_MCP_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"workday-hr-verify","version":"1"}}}' \
    2>/dev/null || true
  local sid
  sid="$(grep -i '^mcp-session-id:' "$headers" | awk '{print $2}' | tr -d '\r')"
  rm -f "$headers"
  [[ -n "$sid" ]] || return 1
  printf '%s' "$sid"
}

# Call an MCP method against $1 with session $2 and raw JSON params $4.
# Echoes the decoded JSON-RPC payload (SSE `data:` framing stripped).
mcp_call() {
  local url="$1" sid="$2" method="$3" params="${4:-{\}}"
  curl -s --max-time 45 -X POST "$url" \
    -H "Authorization: Bearer $MERGE_AH_MCP_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: $sid" \
    --data "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"$method\",\"params\":$params}" \
    2>/dev/null | sed 's/^data: //' | grep -v '^$' | tail -n 1
}

load_env
