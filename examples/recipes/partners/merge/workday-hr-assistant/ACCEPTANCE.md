<!-- SPDX-FileCopyrightText: Copyright (c) 2026 Merge. -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Acceptance checks

Record actual evidence, not expected outcomes. Use synthetic data in an
authorized test tenant. Keep credentials, one-time links, and tenant or user
identifiers out of public output.

`scripts/verify.sh` automates the boundary and read checks and exits non-zero
when an executed case misses its expected outcome. The remaining items below
are the ones a script cannot establish.

## Completed

- [x] Record the NemoClaw, OpenShell, and OpenClaw versions used for evidence.
- [x] Create a Tool Pack containing only the six hr-reader tools, and confirm by
      re-reading the pack that the tool filter applied.
- [x] Register the Tool Pack from the host using a runtime-only key.
- [x] Confirm credential resolution on the wire, and that the agent
      configuration carries the OpenShell placeholder rather than the key.
- [x] Confirm tool discovery reports exactly the intended tools, including any
      protocol or meta-tools.
- [x] Confirm the reader tool returns live tenant data over MCP.
- [x] Confirm the agent completes the same read through the sandbox, using the
      registered inference route.
- [x] Confirm an excluded tool is neither advertised nor accepted, and that the
      refusal is an authorization decision rather than a credential failure.
- [x] Confirm a direct instruction to use excluded tools produces a refusal that
      names the missing capability, with no write performed.

## Outstanding

- [ ] Add a terminal screenshot of a passing `verify.sh` run. The expected
      output is preserved as searchable text in the README; the image is still
      required by the example README template.
- [ ] Narrow the Workday OAuth application credential to the four functional
      areas the six tools need. The Tool Pack already withholds compensation and
      payroll tools; matching the token scope keeps both layers aligned.
- [ ] Revoke the runtime key, re-run with `EXPECT_REVOKED=1`, and record that
      new sessions are refused.
- [ ] Repeat setup and teardown on a second host to confirm the documented path
      is reproducible.
- [ ] Confirm example name, placement, and provenance with a maintainer.

## Evidence boundaries

These checks cover one role's tool availability and credential handling. They do
not establish Workday record-level isolation, resistance to every
prompt-injection technique, or prevention of exfiltration through permitted
destinations. No such claim belongs in the pull request (PR).

Tool availability and record visibility are different boundaries. A role that
can call `list_workers` reaches whatever that Workday account's security groups
permit. Narrowing the Tool Pack does not narrow the account.

If network exfiltration prevention enters scope later, first specify the entire
permitted destination set, including inference and output channels, then verify
a denied request through the permitted adapter runtime. A denied `curl` does not
establish that the agent runtime cannot reach the same destination, because the
policy is scoped to executable paths.
