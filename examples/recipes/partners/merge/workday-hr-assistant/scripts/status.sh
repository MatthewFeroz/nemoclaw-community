#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Report the registration's health: credential resolution, generated policy,
# and the tools Agent Handler advertises to this sandbox.
#
# Tool discovery sends `initialize` and `tools/list`. It does NOT execute a
# business tool on the connected system, so a successful discovery is not
# evidence that the linked authorization works. scripts/verify.sh establishes
# that.
#
# Read-only: changes nothing.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/_lib.sh"

command -v nemoclaw >/dev/null || { echo "nemoclaw not in PATH" >&2; exit 1; }

if ! sandbox_exists "$NEMOCLAW_SANDBOX_NAME"; then
  echo "error: sandbox '$NEMOCLAW_SANDBOX_NAME' not found — run scripts/onboard.sh first" >&2
  exit 1
fi

echo "== Registration and credential resolution =="
run nemoclaw "$NEMOCLAW_SANDBOX_NAME" mcp status "$MCP_SERVER_NAME"

echo
echo "== Advertised tools =="
run nemoclaw "$NEMOCLAW_SANDBOX_NAME" mcp status "$MCP_SERVER_NAME" --tools

echo
echo "== Effective OpenShell policy for this route =="
# Inspect the generated policy rather than asserting an egress claim. Unrelated
# grants elsewhere in the sandbox are not removed by adding this route.
run nemoclaw "$NEMOCLAW_SANDBOX_NAME" policy list || true

echo
echo "Review the advertised tool list above against the intended role."
echo "Anything beyond the hr-reader tools means the Tool Pack is too wide."
