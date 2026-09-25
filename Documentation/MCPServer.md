# The in-app MCP server

Evolv.io runs its own [Model Context Protocol](https://modelcontextprotocol.io)
server, in-process, whenever the app itself is running. It exists to solve one
specific problem: an AI coding assistant's shell/file tools run as a separate
process, and macOS sandboxes Evolv.io's container (`~/Library/Containers/
com.amolloy.Evolv-io/`) so *no other process* -- not a plain shell, not even
Finder driven by AppleScript -- can read or write into it without the user
personally clicking through a picker. That means an assistant can't hot-edit
`.evolvnode` files into the app's user Nodes folder, and can't read back
rendered snapshots, by normal file-tool means.

The app itself has no such restriction on its own container. So instead of
fighting the sandbox, the app exposes an MCP server on `127.0.0.1:4848`
(loopback only) that does file writes and reloads *from inside the sandbox
boundary*, and hands results back over HTTP instead of the filesystem.

Source: `Evolv.io/MCP/EvolvMCPServer.swift`. Started unconditionally (all
configurations, not just Debug) from `Evolv_ioApp.init()` -- if the app is
running, the server is listening. Console prints `EvolvMCPServer: listening
on 127.0.0.1:4848` at launch, or `EvolvMCPServer: failed to create listener on
port 4848: <error>` if something else already has that port.

## Prerequisite: the app has to actually be running

This is not a standalone background service -- it's part of the Evolv.io
process. If the app isn't running (built + launched via Xcode, e.g.
`RunProject`), there is nothing listening on port 4848 and every tool call
will fail to connect. Restarting the app restarts the server (fresh node
registry, fresh listener).

## One-time setup (already done for this project, listed for reference)

- **Entitlement**: `com.apple.security.network.server` is granted via the
  `ENABLE_INCOMING_NETWORK_CONNECTIONS = YES` build setting (Xcode's Signing &
  Capabilities > App Sandbox > Incoming Connections), not a key in
  `Evolv_io.entitlements` -- required under App Sandbox for any incoming
  listening socket, even loopback-only ones.
- **Dependency**: the official
  [`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk)
  (product name `MCP`) is added to the Evolv.io app target via Xcode's
  Package Dependencies -- added through Xcode's own UI, not by hand-editing
  `project.pbxproj` (that file's package-reference graph is easy to corrupt
  by hand and hard to diagnose when it is).
- **Client registration**: registered once via
  `claude mcp add --transport http evolv-io http://127.0.0.1:4848/`, which
  wrote the server into this project's local Claude Code config. A **new
  session on this same machine should already see it** -- if a tool named
  `mcp__evolv-io__<something>` doesn't show up in the deferred-tools list,
  re-run that `claude mcp add` command (or check `claude mcp list`).

## Using it from a fresh session

Deferred tools appear by name only, e.g. `mcp__evolv-io__write_node`. Load
its schema before calling it:

```
ToolSearch(query: "select:mcp__evolv-io__write_node")
```

Then call it like any other tool.

## Tools currently exposed

### `write_node(name, content)`

Writes an `.evolvnode` file into the app's user-editable Nodes folder
(`DSLLibrary.containerNodesDirectory`, the same folder the app's own
"Reveal Nodes Folder" menu item opens) and immediately calls
`NodeRegistry.shared.reload()` -- the same thing "Reload Custom Nodes" does,
including clearing `MetalRenderContext`'s compiled-pipeline cache. No Xcode
rebuild needed; the render updates on next paint.

- `name`: bare file name, e.g. `"log"` or `"log.evolvnode"` -- the
  `.evolvnode` extension is appended automatically if missing. Rejected if it
  contains `/` or `..` (no path traversal, no writing outside the Nodes
  folder).
- `content`: the full file contents, overwriting whatever was there.
- The result text reports the new total registered-node count and, if the
  file you just wrote failed to parse (or collided with an existing name),
  the exact `DSLLoadIssue` message for *that file* -- `isError: true` in that
  case. This means a bad edit is reported back in the same tool call, not
  discovered later by digging through console logs.

This only affects the **user** Nodes folder, not the bundled
`Evolv.io/Resources/BundledNodes/*.evolvnode` files checked into git --
those still require a normal source-file edit + Xcode rebuild to take
effect, exactly as before. Use `write_node` for live iteration; once a change
is confirmed good, port it back into the corresponding bundled file by hand
so it ships with the app and is captured in git history.

### `delete_node(name)`

Deletes an `.evolvnode` file from the same user Nodes folder and reloads the
registry, so a node removed this way disappears from the app immediately.

- `name`: same rules as `write_node` -- bare file name, `.evolvnode`
  appended if missing, `/` and `..` rejected.
- Returns `isError: true` with a clear message if no such file exists in the
  user Nodes folder. Bundled nodes can't be deleted this way (they aren't in
  that folder).
- On success, reports the new total registered-node count.

## What's *not* exposed yet

Only `write_node` and `delete_node` exist today. Rendering a tree and getting pixels back
(solving the *other* half of the original problem -- reading
`SnapshotDump`'s PNGs out of the sandboxed container) was discussed but not
built; if that becomes worth doing, `EvolvMCPServer.swift` is the place to
add a `render` tool (parse an expression via `Parser`, render via
`NodeRenderer`, return the PNG as `Tool.Content.image` directly over MCP,
no filesystem involved). Same for a `list_nodes`/`get_node` read-back tool.

## Implementation notes, if extending this

- The MCP SDK's `StatelessHTTPServerTransport` only converts between its own
  `HTTPRequest`/`HTTPResponse` value types and JSON-RPC -- it does not own a
  socket. The SDK's own HTTP example depends on SwiftNIO for that. This
  project deliberately avoided adding NIO as a second new dependency and
  hand-rolled a minimal HTTP/1.1 bridge with `Network.framework`
  (`NWListener`/`NWConnection`) instead -- one request per connection, no
  keep-alive, no chunked transfer-encoding, no SSE. That's why the tool is
  `write_node` and not something streaming.
- `NWListener(using: parameters, on: port)` and setting
  `parameters.requiredLocalEndpoint` to the same host:port are redundant and
  throw `EINVAL` -- bind the port via `requiredLocalEndpoint` only and use
  `NWListener(using: parameters)` with no separate port argument.
- Port `4848` is a hardcoded constant in `EvolvMCPServer.swift`. If it's ever
  in use by something else, the app logs the failure and simply doesn't
  start the server -- it doesn't crash.
