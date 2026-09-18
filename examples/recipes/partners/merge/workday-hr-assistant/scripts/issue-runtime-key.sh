#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Issue a runtime-only key bound to one Tool Pack and Registered User.
# Dashboard-created keys do not support this binding. Prompt for the management
# key without echo; pass secrets through stdin and save the result in a private
# .env. The key value is returned only once. Set expiry in the dashboard because
# this helper does not set it.

set +x
set -euo pipefail
umask 077
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/_lib.sh"
# Do not inherit a management credential exported by .env or the caller.
unset MERGE_AH_ADMIN_KEY

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
  -H @- \
  -H "Content-Type: application/json" \
  --data "$BODY" <<< "Authorization: Bearer $MERGE_AH_ADMIN_KEY")"
unset MERGE_AH_ADMIN_KEY

NEW_KEY="$(printf '%s' "$RESPONSE" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("key", ""))
except Exception:
    print("")')"

if [[ -z "$NEW_KEY" ]]; then
  echo "error: the response carried no key value; check the management key and bindings." >&2
  exit 1
fi

# Replace the token line in place, preserving the rest of the file and its
# comments. A backup is left alongside; *.bak is ignored repository-wide.
chmod 600 "$ENV_FILE"
if [[ -e "$ENV_FILE.bak" ]]; then chmod 600 "$ENV_FILE.bak"; fi
cp "$ENV_FILE" "$ENV_FILE.bak"
# Pass the key over stdin, not argv or an exported environment variable.
python3 -c '
import re, shlex, sys
path, new = sys.argv[1], sys.stdin.read().strip()
with open(path) as handle:
    text = handle.read()
line = "MERGE_AH_MCP_TOKEN=" + shlex.quote(new)
text, count = re.subn(r"^MERGE_AH_MCP_TOKEN=.*$", lambda _: line, text, count=1, flags=re.M)
if count == 0:
    text = text.rstrip("\n") + "\n" + line + "\n"
with open(path, "w") as handle:
    handle.write(text)
' "$ENV_FILE" <<< "$NEW_KEY"
chmod 600 "$ENV_FILE" "$ENV_FILE.bak"

echo >&2
unset NEW_KEY RESPONSE
echo "Wrote MERGE_AH_MCP_TOKEN to $ENV_FILE with owner-only permissions." >&2
echo "Set an expiry on '$KEY_NAME' in the dashboard, and delete the key it replaces." >&2
echo "Next: bash scripts/onboard.sh" >&2
