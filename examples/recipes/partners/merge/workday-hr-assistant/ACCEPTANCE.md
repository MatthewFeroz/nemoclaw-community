<!-- SPDX-FileCopyrightText: Copyright (c) 2026 Merge. -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Acceptance checks

Record actual evidence, not expected outcomes. Use synthetic data in an
authorized test tenant. Keep credentials, one-time links, and tenant or user
identifiers out of public output, including screenshots.

`scripts/verify.sh` automates the boundary, read, and key-scope checks and exits
non-zero when an executed case misses its expected outcome. The items below that
a script cannot establish are listed separately.

## Completed

- [x] Record the NemoClaw, OpenShell, and OpenClaw versions used for evidence.
- [x] Create a Tool Pack containing only the six hr-reader tools, and confirm by
      re-reading the pack that the tool filter applied.
- [x] Issue a runtime-only access key bound to that pack and Registered User,
      with an expiry, and confirm it carries no management scope.
- [x] Register the Tool Pack with the sandbox using that runtime key.
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
- [x] Confirm the runtime key cannot create a Tool Pack (case 6).
- [x] Confirm the runtime key cannot address a Tool Pack it is not bound to
      (case 7).
- [x] Capture terminal evidence of a passing run with identifiers replaced.
- [x] Narrow the Workday OAuth application credential to the four functional
      areas the six tools need, so the token scope matches the Tool Pack.

## Outstanding

- [ ] Revoke the runtime key and re-run with `EXPECT_REVOKED=1`. The Agent
      Handler API exposes `GET`, `HEAD`, and `OPTIONS` on access keys and no
      delete, so revocation is a dashboard action.
- [ ] Re-authorize the Workday connection so the stored token is issued under
      the narrowed credential. The registered application credential now scopes
      to the four functional areas the six tools need, and reads continue to
      succeed, but the stored authorization predates the change and was issued
      to the previous client. Re-authorizing aligns the token with the role and
      avoids a refresh against a client that no longer exists.
- [ ] Repeat setup and teardown on a second host to confirm the documented path
      is reproducible.
- [ ] Confirm example name, placement, and provenance with a maintainer.

## Evidence boundaries

These checks cover one role's tool availability, the scope of the key that
reaches it, and credential handling. They do not establish Workday record-level
isolation, resistance to every prompt-injection technique, or prevention of
exfiltration through permitted destinations. No such claim belongs in the pull
request (PR).

Tool availability and record visibility are different boundaries. A role that
can call `list_workers` reaches whatever that Workday account's security groups
permit. Narrowing the Tool Pack does not narrow the account.

The access token carries the functional areas granted to the Workday API client,
which is a separate control from the Tool Pack. Both should be narrowed for a
role; this example currently narrows one and documents the other.

If network exfiltration prevention enters scope later, first specify the entire
permitted destination set, including inference and output channels, then verify
a denied request through the permitted adapter runtime. A denied `curl` does not
establish that the agent runtime cannot reach the same destination, because the
policy is scoped to executable paths.
