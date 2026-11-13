# Contributing to nodch

nodch is an unofficial notch mode for [Nod](https://github.com/n8n-io/nod). Thanks for helping.

## Scope

nodch is only a notch mode for Nod. It has no chat UI; anything bigger opens Nod's own window. It talks to an
unmodified Nod over its HTTP API and SSE, and never copies Nod's application code. It never approves, retries or
sends anything on the user's behalf without an explicit user action. There is no Nod or n8n logo or brand mark in
this repo. If a change grows the island into an app, open an issue first.

## Build and check

Needs macOS 26 and the Swift 6 command-line tools. Xcode is not needed.

```sh
swift build --package-path app
swift run --package-path app NodchChecks   # must exit 0
scripts/bundle.sh                          # optional: build/Nodch.app, ad-hoc signed
```

The checks are an executable (`NodchChecks`), not XCTest. Add a check there for the behavior you change.

## Try it without Nod

```sh
swift run --package-path app Nodch --demo              # cycles through every state
swift run --package-path app Nodch --snapshot <dir>    # renders every state to PNG
```

The [README](README.md) explains how to run against a real Nod.

## Pull requests

- Keep them small and focused on one change.
- Run the build and `NodchChecks` first and say so in the PR.
- For UI changes, attach screenshots (`--snapshot` is handy).
- Code adapted from Pippa keeps a one-line comment naming the Pippa file it came from (see [NOTICE](NOTICE)).
- Everything on GitHub is in English: docs, commits, pull requests, code comments.

By contributing you agree that your work is licensed under Apache-2.0. See the
[Code of Conduct](CODE_OF_CONDUCT.md); report security problems as described in [SECURITY.md](SECURITY.md).
