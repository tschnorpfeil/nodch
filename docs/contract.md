# Real Nod client contract

Run from the nodch repository with Swift 6.4 command-line tools, Node >=24.21,
Docker (on this machine: the already running `colima-spf` context), curl and git:

```sh
scripts/contract.sh
```

The script clones **unmodified Nod 915e4f1f0f5ee6e3af422bcc2814dc4c6a851cc1** into
`$TMPDIR/nodch-contract/nod` (falling back to `/tmp/nodch-contract`). It refuses a
modified checkout. Dependencies are installed with `npx -y pnpm@10.34.5`; nothing
is installed globally. Package-manager caches, per-run data and logs stay below
that cache directory. It starts its own disposable PostgreSQL 17 container,
a minimal Python workspace container with networking disabled, Nod's original
`src/server/index.ts` and a loopback-only OpenAI-compatible model stub. The model
and Nod server default to ports 14311 and 14310. Override them with
`NODCH_STUB_PORT` and `NODCH_CONTRACT_PORT` if needed.

Nod runs with an isolated environment and a disposable vault key. No real model
keys, connected accounts, browser container, voice models or paid services are
needed. The stub calls Nod's real `manage_personal_context` tool with
`notification_preferences_update {proactivePaused:true}`. Its trust response
requires confirmation; its confirmation and confirmation-review responses satisfy
Nod's normal schemas. Nod creates and executes the approval itself. No database
rows, server source, adapters or approval services are replaced by the fixture.

`NodchContract` uses the production `NodClient` and `NodSession` to assert:

- Anonymous state request returns 401; access-key cookie returns 200.
- SSE connects and fetches the initial state.
- Sending a prompt is accepted, and SSE plus state exposes `.needsYou`.
- Explicit approval is accepted; a second explicit answer returns 409.
- Stop is accepted; the pinned Nod checkout remains clean.

A trap stops both processes and removes only this run's two containers, including
on failure or Ctrl-C. Data and logs remain in the printed `run.*` directory for
inspection. Nod may log its own shutdown/resource or PostgreSQL deprecation
warnings; failed contract assertions still cause a nonzero exit. To inspect the
checkout independently:

```sh
git -C "${TMPDIR:-/tmp}/nodch-contract/nod" rev-parse HEAD
git -C "${TMPDIR:-/tmp}/nodch-contract/nod" status --porcelain
```

## Live Nod and nodch for a screenshot

Keep this command running in a terminal:

```sh
scripts/contract.sh --serve
```

It prints a browser access link and the exact `NOD_URL` and `NOD_DATA_ROOT` for
that run. Open the printed access link in the default browser; the fragment sets
Nod's browser cookie. Send any prompt in Nod to create a pending **Pause proactive
notifications?** approval. Leave it pending while taking the screenshot. `--serve`
does not run the approval assertions or answer the approval. The stub supports
this one synthetic scenario; it is not a general-purpose assistant.

In another terminal, use the **printed** environment values to launch nodch:

```sh
NOD_URL=http://127.0.0.1:14310 \
NOD_DATA_ROOT=/absolute/path/from/the/printed/run/data \
  swift run --package-path app Nodch
```

The UI integrator must create and retain a session, attach its store to the UI,
and call `start()`; stop observation with `disconnect()`:

```swift
let configuration = try NodConfiguration.fromEnvironment()
let session = NodSession(client: NodClient(configuration: configuration))
let store = session.store
session.start()
```

This client-only change does not wire the placeholder Nodch executable to a UI;
the island integration is separate. The session implements the existing
`NodActions` seam without modifying `Model.swift`. `openNod(path:)` opens the
configured HTTP server plus the requested path using `NSWorkspace`.

For interactive client assertions against the running fixture:

```sh
NOD_URL=http://127.0.0.1:14310 \
NOD_DATA_ROOT=/absolute/path/from/the/printed/run/data \
  swift run --package-path app NodchContract
```

Use a fresh `--serve` run for this command: the contract expects an idle initial
conversation. Ctrl-C in the serving terminal cleans up the processes and containers.

## Verified server details

Sources in the pinned Nod checkout:

- `src/server/network.ts`: the source server's default port is **4310**.
- `src/server/config.ts`: default data root is `.local`, resolved against **Nod's
  working directory**, not a universal application-support directory. When nodch
  starts elsewhere, set `NOD_DATA_ROOT` explicitly.
- `src/server/access.ts` and `app.ts`: `NOD_AUTH_TOKEN` enables Bearer auth;
  otherwise read `<dataRoot>/access-key` and send `nod-access-<port>=<key>` as a
  cookie. The configured URL supplies the allowed Host header; remote deployments
  must match Nod's configured public origin. nodch's environment loader prefers
  a nonempty token over the key file and reads the key again for each request.
- `src/server/app.ts`, `audio-messages.ts`, `thread.ts`: approval answers use
  nonempty `text`, `replyToMessageId`, a fresh `clientMessageId`, and
  `approvalAnswer {approvalId,approved}`. Stale answers return 409. The session
  refreshes state and throws the conflict; it never repeats a send or approval.
- `src/server/app.ts` and `events.ts`: public SSE encodes the event type in JSON
  `data`, not an `event:` field. At this revision the public endpoint forwards
  `refresh`, `activity` and `delta`; internal `working` is not forwarded. The
  client accepts `working` as well. Heartbeats are comments every 15 seconds.
- `src/shared/contracts.ts`: pending message approvals take precedence over work
  activity; historical successful turns do not flash done on initial connection.
- `docs/src/content/docs/connect/local-models.mdx` and `src/providers/pi/`: the
  compatible provider uses `/v1/models` and OpenAI chat completions, including
  streamed tool calls. `NOD_TRUST_MODEL=selected` keeps all model calls on the
  local stub.

Deterministic, network-free checks are part of `swift run --package-path app
NodchChecks`. A `URLProtocol` fixture covers SSE reconnects, event-triggered
refreshes, coalescing, authentication failures, mutation bodies and no retries.

## Acceptance output (2026-11-13)

All three commands below exited 0 in this checkout with Swift 6.4. The command-line
toolchain emitted linker search-path warnings; they did not prevent linking.

`swift build --package-path app` (last line):

```text
Build complete! (2,00 Sek.)
```

`swift run --package-path app NodchChecks` (complete assertion output):

```text
Build complete! (1,35 Sek.)
ok   package links
ok   store starts offline
ok   SSE partial UTF-8, CR/LF/CRLF, BOM and heartbeats
ok   SSE multiline data and event/id fields
ok   SSE empty data dispatches; event without data resets
ok   SSE partial trailing event is not dispatched
ok   SSE multiple events in one chunk
ok   state ignores historical completion on initial connect
ok   state maps real Activity fields and fractional timestamp
ok   pending approval wins over running activity
ok   state counts additional pending approvals
ok   newly completed turn shows done
ok   refresh does not extend completion deadline
ok   done expires to rest
ok   failed turn exposes server error
ok   approval state working is not pending
ok   approval state done is not pending
ok   approval state declined is not pending
ok   approval state expired is not pending
ok   approval state uncertain is not pending
ok   queued turn maps without activity
ok   thread change does not announce old completion
ok   access-key file builds Nod port cookie; default port is 4310
ok   bearer takes precedence over access-key file and preserves host
ok   openNod paths stay on configured server
ok   invalid configuration rejected
ok   missing access-key reports credentials
ok   409 approval throws clear conflict
ok   409 refreshes state without retrying approval
ok   approval JSON uses message ID, approval ID, explicit decision and client UUID
ok   SSE activity triggers state refetch and mapping
ok   SSE working triggers state refetch and mapping
ok   SSE refresh triggers state refetch and mapping
ok   SSE delta does not fetch chat content
ok   401 maps to offline credentials
ok   network failure never retries send
ok   unreachable maps to offline
ok   network failure never retries approval
ok   HTTP failure never retries send
ok   invalid state JSON has a typed error
ok   session publishes completion
ok   session done timer expires without another server event
ok   every SSE reconnect refetches state without a refresh event
ok   disconnect cancels reconnects
ok   SSE reads Nod JSON event types rather than relying on event field
ok   concurrent state refreshes coalesce
All checks passed.
```

`scripts/contract.sh` (complete assertion output):

```text
PASS without credentials -> 401
PASS with credentials -> 200
PASS SSE connects and loads initial state
PASS send prompt -> accepted
PASS SSE + state -> IslandState.needsYou
PASS approve -> accepted
PASS duplicate approval -> 409 (no retry)
PASS stop -> accepted
PASS Nod pinned revision -> 915e4f1f0f5ee6e3af422bcc2814dc4c6a851cc1
PASS Nod git status --porcelain -> clean
```

`git -C "$TMPDIR/nodch-contract/nod" status`:

```text
HEAD detached at 915e4f1f
nothing to commit, working tree clean
```

The documented `scripts/contract.sh --serve` mode was also started: the Nod page
returned HTTP 200. Ctrl-C exited 130, removed both fixture containers and left
neither server nor stub listening on ports 14310/14311. UI rendering and the live
notch screenshot belong to the separate island integration and were not tested.
