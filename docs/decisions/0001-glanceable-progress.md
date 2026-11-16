# 0001: Glanceable progress

Status: decided, one item prototyped. Date: 2026-11-16.

nodch exists so that a glance at the notch tells you what Nod is doing. Four ideas could help: a step trail, a
background-work hint, "how long did it take", and an update check. This note picks what to build, so nobody builds all
four.

## How the evidence was gathered

**These are derivations from Nod's source code, not measurements.** No Nod server was run and no tokens were spent.
Everything below about Nod comes from the pinned, unmodified revision
[`915e4f1`](https://github.com/n8n-io/nod/tree/915e4f1f0f5ee6e3af422bcc2814dc4c6a851cc1), cited as `file:line`. Nothing
was copied into this repository. What the code cannot say (how many distinct steps a typical turn emits in practice) is
marked **open** and needs a real turn to settle.

## What Nod's code says

| Question | Answer from the code | Nod source |
|---|---|---|
| Where does `activity` come from? | One SQL read over running or queued turns, `DISTINCT ON (session_id)`: at most one entry per session. | `src/server/activity.ts:13`, `:23`, `:39` |
| How is `step` chosen? | Only the latest `step`, `thought` or `retry` event of the turn (or the task's `now_text`). Earlier steps are not in the payload. | `src/server/activity.ts:19`, `:27-28` |
| Who writes `step` events? | The model, through `set_status`; the prompt tells it to use it for "longer work" and to skip quick replies. Also the first line of a non-final model text note. | `src/runtime/tools.ts:195-200`, `src/runtime/prompt.ts:43`, `src/runtime/index.ts:847-853`, `:1050-1067` |
| How often is `activity` published? | After a `refresh` or `working` server event, debounced to 250 ms, and only if the JSON changed. `quietSince` is in the payload, so most refreshes change it. | `src/server/activity.ts:109-128`, `:89`; `src/server/events.ts:19-24` |
| When does `background: true` appear? | When the turn is not owner-started (source `schedule` or `event`). Such a turn is listed only if it also has a task row. | `src/server/thread.ts:87`, `src/server/activity.ts:39`, `:99` |
| What does `tool` carry? | A fixed label ("Running a command", …) only while a tool without a site runs. | `src/server/activity.ts:43-58`, `:90-92` |
| Is `finishedAt` set? | Yes on every finish: succeeded, waiting, failed (`finishTurn`), merged turns, and cancellations. | `src/server/thread.ts:1103`, `:2215-2216`, `:1400`, `:837` |
| Is it in the API? | Yes, as `Turn.finishedAt?: string \| null`. `startedAt` is not exposed. | `src/shared/contracts.ts:68-76`, `src/server/app.ts:301` |
| What is `since` measured from? | `COALESCE(started_at, created_at)`. The turn contract has only `createdAt`, so a duration from the API includes any wait in the queue. | `src/server/activity.ts:13`, `src/shared/contracts.ts:68-76` |
| Does a turn that asks for approval end? | `finishTurn(..., 'waiting')` sets `finished_at`; resuming starts a new turn with source `resume`. A duration is therefore per turn row. | `src/server/thread.ts:2216`, `:1017` |

## Verdicts

### 1. Step trail (M): later

The payload holds one step, so a trail means nodch remembers the values it sees between state fetches. Steps come from
the model's optional `set_status` calls and note first lines (`tools.ts:195-200`, `prompt.ts:43`): a quick turn has
none, and a long one has as many as the model chose to write. The plan's bar was at least three distinct steps per
typical turn. The code cannot show that, and a fetch that lands between two steps loses one. **Open:** log the distinct
`step` values of a few real multi-step turns (no text, no tokens). Build only if three or more is typical. Until then
the single live line stays.

### 2. Background-work hint (S): later

The island already shows background work when it is the only activity: the mapper falls back to the first entry
(`NodState.swift`, `state.activity?.first`). The hidden case is a background turn running alongside the person's own
turn, and Nod lists a background turn only when it has a task row (`activity.ts:39`). That is narrow. A badge also
competes with the existing "+N" approvals badge for the same wing space. Revisit when someone reports not seeing a
task that ran next to their own turn.

### 3. "Done in N s" (S): build, prototyped

`finishedAt` is set on every normal finish, is already decoded and unused, and needs no extra request
(`thread.ts:1103`, `contracts.ts:74`). The prototype shows the duration on the trailing side of the done wing, in the
`m:ss` format the working counter used, only when the turn took at least 5 s (a "0:02" beside every quick reply is
noise). A missing, unreadable or negative `finishedAt` gives no duration. Known imprecision: the span starts at
`createdAt`, so queue time counts, and an approval pause ends a turn (see the table).

### 4. Opt-in update check (M): later, as a Settings toggle off by default

It breaks no rule on its own, but README's Privacy section promises that nodch talks only to the Nod address. A check
needs its own server (GitHub's releases API), must be off by default, and must be named in that section. It does not
help the glance, so it ships on its own plan, not in this one.

## What was built

Only item 3: `IslandState.done(summary:took:)`, mapped from `finishedAt - createdAt`, shown in the wing, with checks in
`NodchChecks` and a `done-took` snapshot scene. Nothing else from the list.

## Follow-up plans to write

1. Measure real `step` counts per turn against a running Nod (gates item 1).
2. Update-check toggle (item 4), with the Privacy wording.
