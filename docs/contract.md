# Real Nod client contract

Run from the nodch repository with Swift 6.4 command-line tools, Node >=24.21,
Docker, curl and git:

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
- Uploading a small text file returns its Artifact; sending its `attachmentIds`
  with empty text is accepted. GET state retains the attachment on that message.
- SSE plus state exposes `.needsYou` for the stub's approval scenario.
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

The app does this in `makeNodSession` (Connection.swift): it creates the session
with the island's store and starts it. The session implements the `NodActions` seam
in `Model.swift`. `openNod(path:)` opens the configured HTTP server plus the
requested path using `NSWorkspace`.

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
- `src/shared/files.ts`, `src/server/app.ts` and `artifacts.ts`: POST `/api/uploads`
  accepts one multipart field named `file`, limited to **90 MiB** (94,371,840
  bytes), and returns an Artifact (`id`, `name`, `mimeType`, `size`, `url`). Files
  must contain at least one byte. The client follows symlinks, rejects folders, packages, unreadable,
  empty and oversized files before any request, infers MIME with the extension's
  UTType (falling back to `application/octet-stream`), and uses the normal auth.
  Uploads expire after 24 hours; this client does not renew them or retry uploads.
- `src/server/audio-messages.ts` (`messageInput`), `app.ts:491` and
  `thread.ts` (`submitUserMessage`): a normal text message may have empty text
  when `attachmentIds` contains uploaded UUIDs. Whitespace becomes empty text;
  the route requires text or attachments. The client rejects blank text without
  attachments locally. Explicit approval answers still require nonempty text and
  no attachments. The real contract sends an attachment-only user message through
  the normal `/api/messages` route; no audio route is used.
- `docs/src/content/docs/connect/local-models.mdx` and `src/providers/pi/`: the
  compatible provider uses `/v1/models` and OpenAI chat completions, including
  streamed tool calls. `NOD_TRUST_MODEL=selected` keeps all model calls on the
  local stub.

Deterministic, network-free checks are part of `swift run --package-path app
NodchChecks`. A `URLProtocol` fixture covers SSE reconnects, event-triggered
refreshes, coalescing, authentication failures, mutation bodies and no retries.

## Latest acceptance output (2026-11-13)

`swift build --package-path app` exited 0:

```text
Build complete! (4,12 Sek.)
```

`swift run --package-path app NodchChecks` exited 0, including the new
multipart framing, MIME fallback, bearer/cookie auth, Artifact mapping,
attachmentIds, local file validation and upload error/no-retry assertions:

```text
ok   non-2xx upload is readable and never retried
ok   upload network failure is never retried
ok   invalid Artifact JSON has a typed error
All checks passed.
```

`scripts/contract.sh` installed dependencies and started the real pinned Nod,
then exited 1 at the new attachment persistence assertion:

```text
PASS without credentials -> 401
PASS with credentials -> 200
PASS SSE connects and loads initial state
PASS upload text file -> Artifact with id, name, MIME and size
PASS send attachment without text -> accepted
PASS GET state with uploaded attachment -> 200
Contract failed: GET state -> sent message carries uploaded attachment
```

This run does **not** establish attachment persistence or the later approval/stop
assertions. Investigation stopped at the requested failure gate; the exact
mismatching message field has not been diagnosed. No rerun was attempted.
The fixture trap removed its containers and processes: a subsequent Docker
container listing for `nodch-contract` and listener check for 14310/14311 were
both empty. The cached Nod checkout remained clean.

The command-line toolchain emitted linker search-path warnings; they did not
prevent the build or deterministic checks from passing. UI rendering was not
tested in this client-only task.
