#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Issue the runtime-only access key this example needs, bound to one Tool Pack
# and one Registered User, and record it in .env.
#
# WHY THIS SCRIPT EXISTS
# The Agent Handler dashboard creates access keys but does not offer per-Tool-Pack
# or per-Registered-User scoping; that binding is available only on the API. A key
# created in the dashboard therefore reaches every pack and user, which is the
# boundary this example is about, and verify.sh case 7 fails on such a key.
#
# SECRET HANDLING
# The management key is read from a terminal prompt with echo disabled, so it is
# not in argv, the environment of any other process, or shell history. It is
# unset as soon as the request completes. The issued runtime key is written
# straight to .env and never printed; only its prefix and length are reported.
#
# An access key value is returned once, on the creation response. After that the
# API exposes only a masked form, so a lost value cannot be recovered and the key
# must be replaced.
#
# EXPIRY IS NOT SET HERE
# This script does not set an expiry, because the create endpoint's expiry field
# is not part of the documented request body this example relies on. Set an expiry
# on the new key in the dashboard, or delete the key at teardown.
#
# Usage:
#   bash scripts/issue-runtime-key.sh
#
# Optional:
#   MERGE_AH_KEY_NAME  name recorded on the new key (default: workday-hr-reader-runtime)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/_lib.sh"

command -v curl    >/dev/null || { echo "curl not in PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not in PATH — needed to build and read JSON" >&2; exit 1; }

require_var MERGE_AH_TOOL_PACK_ID       "the hr-reader Tool Pack UUID"
require_var MERGE_AH_REGISTERED_USER_ID "the Registered User UUID linked to Workday"

KEY_NAME="${MERGE_AH_KEY_NAME:-workday-hr-reader-runtime}"
ENV_FILE="$EXAMPLE_DIR/.env"
[[ -f "$ENV_FILE" ]] || { echo "error: $ENV_FILE does not exist — copy .env.example first" >&2; exit 1; }

# Show the binding before the key is created, so a wrong pack is caught here
# rather than after a key exists.
echo "Tool Pack:       $MERGE_AH_TOOL_PACK_ID" >&2
echo "Registered User: $MERGE_AH_REGISTERED_USER_ID" >&2
echo "Key name:        $KEY_NAME" >&2

# A management key is required: a runtime key cannot create access keys, which is
# the same property verify.sh case 6 asserts.
printf 'Agent Handler MANAGEMENT key (input hidden), then press Enter: ' >&2
read -rs MERGE_AH_ADMIN_KEY; echo >&2
[[ -n "$MERGE_AH_ADMIN_KEY" ]] || { echo "error: no key entered" >&2; exit 1; }

BODY="$(python3 -c '
import json, sys
name, pack, user = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "name": name,
    "tool_pack_ids": [pack],
    "registered_user_ids": [user],
    "scopes": ["runtime:all"],
}))' "$KEY_NAME" "$MERGE_AH_TOOL_PACK_ID" "$MERGE_AH_REGISTERED_USER_ID")"

RESPONSE="$(curl -s --max-time 40 -X POST "$AH_BASE_URL/api/v1/access-keys/" \
  -H "Authorization: Bearer $MERGE_AH_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY")"
unset MERGE_AH_ADMIN_KEY

NEW_KEY="$(printf '%s' "$RESPONSE" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("key", ""))
except Exception:
    print("")')"

if [[ -z "$NEW_KEY" ]]; then
  echo "error: the response carried no key value. Response:" >&2
  printf '%s\n' "$RESPONSE" | head -c 600 >&2
  echo >&2
  exit 1
fi

# Replace the token line in place, preserving the rest of the file and its
# comments. A backup is left alongside; *.bak is ignored repository-wide.
cp "$ENV_FILE" "$ENV_FILE.bak"
python3 - "$ENV_FILE" "$NEW_KEY" <<'PY'
import re, sys
path, new = sys.argv[1], sys.argv[2]
with open(path) as handle:
    text = handle.read()
text, count = re.subn(r'^MERGE_AH_MCP_TOKEN=.*$', 'MERGE_AH_MCP_TOKEN=' + new, text, count=1, flags=re.M)
if count == 0:
    text = text.rstrip('\n') + '\nMERGE_AH_MCP_TOKEN=' + new + '\n'
with open(path, 'w') as handle:
    handle.write(text)
PY
chmod 600 "$ENV_FILE" "$ENV_FILE.bak"

echo >&2
echo "Wrote MERGE_AH_MCP_TOKEN to $ENV_FILE (prefix ${NEW_KEY:0:8}..., ${#NEW_KEY} characters)." >&2
echo "Set an expiry on '$KEY_NAME' in the dashboard, and delete the key it replaces." >&2
echo "Next: bash scripts/onboard.sh" >&2
