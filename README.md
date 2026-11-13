# nodch

A notch mode for [Nod](https://github.com/n8n-io/nod) on the Mac.

**Unofficial.** nodch is an independent prototype and is not affiliated with or endorsed by n8n.

nodch lives in the MacBook notch (or at the top of the menu bar on displays without one). It does a few things and
leaves everything else to Nod:

- Shows what Nod is doing right now.
- Lets you approve or decline what Nod asks before it acts, with the full action text.
- Opens a quick prompt with a global shortcut (⌥Space).
- Hands anything bigger, such as the conversation, the vault, payments or the browser, to Nod's own window.

nodch has no chat of its own. It talks to a running Nod over Nod's HTTP API.

## Build

Needs macOS 26 and the Swift 6 command-line tools. Xcode is not needed.

```sh
swift build --package-path app
swift run --package-path app NodchChecks
```

## Run

nodch talks to a Nod you run from source or self-host (the Nod desktop app keeps its server private).

```sh
NOD_URL=http://127.0.0.1:4310 NOD_DATA_ROOT=/path/to/nod/.local swift run --package-path app Nodch
```

`NOD_AUTH_TOKEN` replaces the access key when Nod runs with one. Without a Nod at hand:

```sh
swift run --package-path app Nodch --demo              # cycles through every state
swift run --package-path app Nodch --snapshot <dir>    # renders every state to PNG
scripts/contract.sh                                    # real Nod in Docker with a free stub model
```

See [docs/contract.md](docs/contract.md) for the contract test.

## License

Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).
