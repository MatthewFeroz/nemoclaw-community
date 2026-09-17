<!-- SPDX-FileCopyrightText: Copyright (c) 2026 Merge. -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Workday HR assistant with role-scoped tool access

| Catalog field | Value |
| --- | --- |
| Description | Give a NemoClaw agent read access to Workday workers, organizations, and time-off through a Merge Agent Handler Tool Pack that withholds compensation, payslip, and payment tools. |
| Industry | ✨ Other |
| Requirements | Existing NemoClaw sandbox with managed MCP support · Merge Agent Handler organization · Workday tenant with an OAuth API client |
| NemoClaw | v0.0.124 |
| Harness | OpenClaw 2026.7.1 |
| OpenShell | 0.0.116 |
| Contributor | Merge |

An HR assistant agent answers questions about the org chart and time-off
balances. It cannot read salaries and it cannot issue payments, because those
tools are absent from the role's Tool Pack. The agent never holds the Workday
credential: OpenShell keeps it on the host and substitutes it at egress.

This recipe is for teams who need an agent to reach a system of record while a
named role bounds what it can do there. It was contributed by
[Merge](https://merge.dev).

## Screenshot

Terminal evidence from `scripts/verify.sh` against a live Workday
implementation tenant:

```text
== Section A: authorization boundary (Agent Handler, scoped key) ==
Advertised tools: 7
  PASS  case 1: 'workday__list_workers' is advertised to this role
  PASS  case 2: 'workday__request_one_time_payment' is not advertised to this role
  PASS  case 3: 'workday__request_one_time_payment' refused at the authorization boundary (tool_not_found)

== Section B: live read ==
  PASS  case 4: 'workday__list_workers' returned a result over MCP
  PASS  case 4b: the agent completed a read through the sandbox

passed=5 failed=0 skipped=1
```

Notice case 3. The refusal is `tool_not_found` from the Tool Pack catalog, not a
credential error and not a refusal the model composed. The capability does not
exist for this role.

## At A Glance

| Question | Answer |
| --- | --- |
| Category | Partner Recipe |
| Contributor or provenance | Merge |
| Use this when | An agent needs a system of record, and a role must bound what it can do there |
| You will get | A sandboxed agent that reads Workday people data, with an executable check that its excluded tools stay refused |
| Runs on | An existing NemoClaw host with a managed OpenClaw sandbox |
| Requires | Managed remote MCP support, an Agent Handler management key and runtime key, a Workday tenant with an OAuth API client |
| Verified on | NemoClaw v0.0.124 · OpenClaw 2026.7.1 · OpenShell 0.0.116 · macOS 15 on Apple Silicon with Docker Desktop · a Workday implementation tenant · an OpenAI-compatible inference endpoint |
| Evidence level | live end-to-end |
| Support and maturity | Best-effort community support; see [SUPPORT.md](../../../../../SUPPORT.md) |
| External access, data, and actions | Setup contacts Agent Handler and changes sandbox configuration. Reads return live Workday people data. Tool results reach the configured inference provider. Service charges may apply. |
| Start here | [Setup](#setup) |
| Confirm success | [Verification](#verification) |

## What this example does

Three components divide the work:

| Component | Responsibility |
| --- | --- |
| OpenClaw, in the sandbox | Runs the agent and calls tools |
| OpenShell, on the host | Holds the Agent Handler key outside the sandbox and bounds egress |
| Agent Handler | Decides which tools exist for the role, and holds the Workday credential |

The authorization boundary is the Tool Pack, enforced by Agent Handler. It is
not the model's restraint, and it is not the network policy. OpenShell keeps the
credential out of the sandbox and bounds the destination, but a managed MCP
registration permits every tool the server advertises. Narrowing the Tool Pack
is what removes a capability.

That distinction is the point of the example. An instruction reaching the agent
through retrieved data cannot argue its way to a tool the Tool Pack does not
contain, because no such tool is ever advertised.

The `workday-hr-reader` pack contains six of the Workday connector's sixty
tools:

```text
list_workers            get_absence_balances
get_worker              list_time_off_entries
list_organizations      get_organization_workers
```

Absent by construction: `get_employee_compensation`, `list_worker_pay_slips`,
`request_one_time_payment`, and `create_payroll_input`.

## Credentials and secret handling

This recipe uses two distinct Agent Handler keys. Keeping them separate is the
reason the sandbox cannot widen its own access.

| Key | Used by | Scope |
| --- | --- | --- |
| Management key | `scripts/setup-packs.sh`, from trusted administration | Creates Tool Packs |
| Runtime key | `scripts/onboard.sh` | One Tool Pack and one Registered User |

Issue the runtime key with an expiry. Do not use a management key in the
sandbox registration.

`scripts/onboard.sh` passes the runtime key through the child process
environment, so it never enters a command argument or a shell history entry.
NemoClaw registers it as an OpenShell provider on the host. Inside the sandbox
the agent sees only the placeholder `openshell:resolve:env:MERGE_AH_MCP_TOKEN`.

Workday credentials stay in Agent Handler. The sandbox never receives them.

## Setup

### 1. Register a Workday API client

A Workday Security Administrator runs the **Register API Client** task with the
**Authorization Code Grant** type and registers the Agent Handler callback URL
shown on the Application Credentials page of the Agent Handler dashboard.

Grant only the functional areas the six tools need: Staffing, Organizations and
Roles, Time Off and Leave, and Tenant Non-Configurable. Withholding
Compensation and Payroll keeps the access token as narrow as the Tool Pack.

Workday displays the client secret once. Record the Client ID and secret, then
add them to Agent Handler under Application Credentials for Workday.

The **View API Clients** task reports three endpoints. The connection form needs
the host of the REST API endpoint, the tenant from its final path segment, and
the host of the authorization endpoint. The REST host and the authorization
host are usually different values.

### 2. Create the Tool Packs

```bash
cp .env.example .env    # then set MERGE_AH_ADMIN_KEY
bash scripts/setup-packs.sh
```

The script creates `workday-hr-reader` and `workday-hr-approver`, then re-reads
each pack to confirm the tool filter applied. Record the reader pack identifier
in `.env` as `MERGE_AH_TOOL_PACK_ID`.

### 3. Link the Workday account

Call the `authenticate_workday` tool for the Registered User to obtain a
one-time link, then open it and sign in to Workday. Treat that link as a
credential; it authorizes account linking for whoever opens it.

### 4. Register the Tool Pack with the sandbox

Set `MERGE_AH_MCP_TOKEN` and `MERGE_AH_REGISTERED_USER_ID` in `.env`, then:

```bash
bash scripts/onboard.sh
bash scripts/status.sh
```

`status.sh` reports credential resolution, the advertised tools, and the applied
policy presets. Review the advertised list against the intended role; anything
beyond the six read tools means the Tool Pack is wider than this example
describes.

## Verification

**Evidence level:** live end-to-end

```bash
bash scripts/verify.sh
```

**Expected result:**

```text
  PASS  case 1: 'workday__list_workers' is advertised to this role
  PASS  case 2: 'workday__request_one_time_payment' is not advertised to this role
  PASS  case 3: 'workday__request_one_time_payment' refused at the authorization boundary (tool_not_found)
  PASS  case 4: 'workday__list_workers' returned a result over MCP
  PASS  case 4b: the agent completed a read through the sandbox

passed=5 failed=0 skipped=1
```

The script exits non-zero if any executed case misses its expected outcome.

A role boundary can also be observed directly. Asking the agent to issue a
payment and to report compensation produces a refusal that names the missing
tools:

```text
I could not complete either request.

Unavailable tools:
- `workday__create_one_time_payment` (or equivalent payment-write tool):
  unavailable because the merge-workday server exposes no payment, bonus,
  payroll-write, or compensation-change tool.

No payment was issued, and no compensation data was retrieved.
```

**This verifies:** the reader tool is advertised and returns live tenant data;
the excluded tool is neither advertised nor accepted, and its refusal is an
authorization decision rather than a credential failure; the credential resolves
on the wire without entering the sandbox; and the agent completes a read through
the sandbox using the registered inference route.

**This does not verify:** record-level isolation inside Workday; resistance to
every prompt-injection technique; prevention of data exfiltration through the
inference provider or other permitted destinations; or behavior after key
revocation, which `verify.sh` reports only when `EXPECT_REVOKED=1` is set after
an actual revocation.

## Permissions and limitations

- Existing sandbox network grants remain. Adding this route does not make the
  sandbox default-deny or remove unrelated destinations. Review the full
  effective policy before making an egress claim.
- The generated policy permits the adapter's executable paths. Another process
  using the same permitted runtime can reach the endpoint. Binary restrictions
  do not establish an employee identity.
- OpenShell's credential boundary does not constrain what a permitted endpoint
  returns. Agent Handler and the configured inference provider are intentional
  recipients of tool results.
- Tool availability is the boundary this example demonstrates. It makes no claim
  about which records within Workday the linked account can reach; that remains
  a Workday security-group question.
- `verify.sh` reports an inconclusive result rather than a pass when a refusal
  cannot be attributed to authorization.

## Teardown

```bash
bash scripts/teardown.sh
```

Revoke the runtime key in Agent Handler afterward; removing the registration
does not invalidate the key. Removal does not terminate already-open streams.
This recipe does not create or destroy the sandbox, and leaves Workday
application credentials in Agent Handler intact.

## Known limitations

- Tool-level scoping uses the `tool_names` field on a Tool Pack connector entry.
  The API accepts `tools`, `enabled_tools`, and `active_tools` and then ignores
  them, producing a pack with the connector's full tool list. `setup-packs.sh`
  re-reads each pack for this reason.
- `openclaw mcp probe` completes successfully but reports a policy denial when
  closing the MCP session, because the generated policy has no rule for the
  session-closing `DELETE`. Discovery and tool calls are unaffected.

## Third-party dependencies

None beyond NemoClaw, OpenShell, and the OpenClaw harness. The scripts use
`bash`, `curl`, and `python3`, and add no packages.
