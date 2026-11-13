# Working on nodch

- Everything on GitHub is in English: docs, commits, pull requests, code comments.
- Scope: nodch is only a notch mode for Nod. No chat UI. Anything bigger opens Nod's own window.
- nodch talks to an unmodified Nod over its HTTP API and SSE. Never copy Nod's application code into this repo.
- No Nod or n8n logo or brand mark. nodch is unofficial and says so.
- Build without Xcode: `swift build --package-path app`. Checks are an executable, not XCTest:
  `swift run --package-path app NodchChecks` must exit 0.
- Code adapted from Pippa keeps a one-line comment naming the Pippa file it came from (see NOTICE).
- Never approve, retry or send anything on the user's behalf without an explicit user action.
