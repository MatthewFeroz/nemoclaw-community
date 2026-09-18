#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Create the two Agent Handler Tool Packs this example contrasts:
#
#   workday-hr-reader    org chart and time-off, read-only
#   workday-hr-approver  the same, plus time-off request submission
#
# The approver name is retained for compatibility; request_time_off submits a
# request and does not grant approval authority.
#
# Neither pack contains compensation, payslip, or payment tools. That absence is
# the example's security property, so it belongs in version control where a
# reviewer can read it — not in a dashboard click-through nobody can audit.
#
# Tool-level scoping uses the `tool_names` field on a connector entry. Note that
# `tools`, `enabled_tools`, and `active_tools` are accepted by the API and then
# SILENTLY IGNORED, yielding a pack with the connector's full tool list. Always
# re-read the pack after writing it; this script does.
#
# Needs an Agent Handler MANAGEMENT key (MERGE_AH_ADMIN_KEY), not the runtime
# key the sandbox uses. Run it from trusted administration, never in a sandbox.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/_lib.sh"

command -v curl    >/dev/null || { echo "curl not in PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not in PATH" >&2; exit 1; }
require_var MERGE_AH_ADMIN_KEY "an Agent Handler management key; the runtime key cannot create Tool Packs"

READER_TOOLS='["list_workers","get_worker","list_organizations","get_organization_workers","get_absence_balances","list_time_off_entries"]'
APPROVER_TOOLS='["list_workers","get_worker","list_organizations","get_organization_workers","get_absence_balances","list_time_off_entries","request_time_off"]'

create_pack() {
  local name="$1" desc="$2" tools="$3" body out id got
  body="$(python3 -c '
import json,sys
name,desc,tools=sys.argv[1],sys.argv[2],json.loads(sys.argv[3])
print(json.dumps({"name":name,"description":desc,
  "connectors":[{"slug":"workday","tool_names":tools}]}))' "$name" "$desc" "$tools")"

  out="$(curl -s --max-time 40 -X POST "$AH_BASE_URL/api/v1/tool-packs/" \
    -H @- \
    -H "Content-Type: application/json" --data "$body" <<< "Authorization: Bearer $MERGE_AH_ADMIN_KEY")"

  id="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
  if [[ -z "$id" ]]; then
    echo "  failed to create '$name': $(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  # Re-read, because a silently-ignored tool filter is the failure mode here.
  got="$(curl -s --max-time 30 "$AH_BASE_URL/api/v1/tool-packs/$id/" \
    -H @- <<< "Authorization: Bearer $MERGE_AH_ADMIN_KEY" \
    | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(",".join(sorted(t["name"] for c in d.get("connectors",[]) for t in c.get("tools",[]))))')"

  local want
  want="$(printf '%s' "$tools" | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin))))')"
  if [[ "$got" != "$want" ]]; then
    echo "  WARNING '$name' ($id) did not scope as requested." >&2
    echo "    wanted: $want" >&2
    echo "    got:    $got" >&2
    return 1
  fi
  echo "  $name -> $id"
  echo "    tools ($(printf '%s' "$got" | tr ',' '\n' | grep -c .)): $got"
}

echo "Creating Tool Packs under $AH_BASE_URL"
create_pack "workday-hr-reader" \
  "Read-only Workday HR assistant: org chart and time-off. No compensation, payslips, or payments." \
  "$READER_TOOLS"
create_pack "workday-hr-approver" \
  "Workday HR assistant with time-off request submission. No compensation, payslips, or payments." \
  "$APPROVER_TOOLS"

echo
echo "Put the reader pack id in .env as MERGE_AH_TOOL_PACK_ID, then:"
echo "  bash scripts/onboard.sh && bash scripts/verify.sh"
