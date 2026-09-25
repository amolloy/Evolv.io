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

### `render(...)`

Renders an expression through the app's own `Parser` + Metal pipeline and
returns PNGs as MCP image content -- no filesystem involved, so it sidesteps
the sandbox the same way `write_node` does. Colors are mapped exactly like
the on-screen view (each channel clamped to 0...1). Source:
`Evolv.io/MCP/MCPRenderTool.swift`.

- `expression` *or* `sample`: an s-expression, or the name of one of
  `ContentView.sampleExpressions` (e.g. `"Figure 9"`, case-insensitive).
- `reference` (optional): `"Figure 9"`, `"Figure 10"` or `"Figure 12"` --
  Sims' originals, `Documentation/OriginalFigure{9,10,12}.gif`, which ship in
  the app bundle (they're in the app target's Resources build phase). With a
  reference, the result is one image with **our render on the left and the
  original on the right**, both at the output size (the original is scaled).
- `x_min`, `x_max`, `y_min`, `y_max` (optional): the coordinate rectangle to
  render, y running bottom to top. Default: the app's -1...1 square
  *cropped* to the output aspect ratio -- the reference's width/height
  (Figure 9 464x367, Figure 10 463x368, Figure 12 780x616, all about 1.26),
  else `width`/`height` if both are given, else 1. For these wide figures
  that means x from -1 to 1 and y from about -0.79 to 0.79: the top and
  bottom are cut off, which is how Sims' figures appear in the paper
  (widening x instead does *not* match them). A tall aspect would crop the
  sides instead.
- `width`, `height` (optional): output pixels. If only one is given the
  other follows the x/y range's aspect; with neither, the reference's own
  pixel size, else 512 tall. Max 4096 per side.
- `supersample` (optional, 1-8, default 4): samples per pixel per axis,
  matching the app's Supersampling setting.
- `crops` (optional): an array of `{x_min, x_max, y_min, y_max}` regions.
  Each is **re-rendered** at `width` pixels across (not upscaled), and, with
  a reference, paired with the same region cut from the original (that half
  *is* upscaled, and assumes the main framing is how the original lines up).

The result starts with a text block giving the actual size, framing, and
the raw min/max of the render output per channel (handy for spotting values
the 0...1 display clamp is hiding), then one image per render.

Supporting change: `Evaluator.render(node:bounds:supersample:)` /
`MetalRenderContext.render(node:width:height:bounds:...)` take an arbitrary
`CGRect` instead of `scale`; the old `scale:` entry points are now the
centered-square special case and produce bit-identical output.

## What's *not* exposed yet

A `list_nodes`/`get_node` read-back tool for the user Nodes folder.

## Implementation notes, if extending this

- The MCP SDK's `StatelessHTTPServerTransport` only converts between its own
  `HTTPRequest`/`HTTPResponse` value types and JSON-RPC -- it does not own a
  socket. The SDK's own HTTP example depends on SwiftNIO for that. This
  project deliberately avoided adding NIO as a second new dependency and
  hand-rolled a minimal HTTP/1.1 bridge with `Network.framework`
  (`NWListener`/`NWConnection`) instead -- one request per connection, no
  keep-alive, no chunked transfer-encoding, no SSE. That's why every tool
  returns its whole result in one response and nothing streams.
- `NWListener(using: parameters, on: port)` and setting
  `parameters.requiredLocalEndpoint` to the same host:port are redundant and
  throw `EINVAL` -- bind the port via `requiredLocalEndpoint` only and use
  `NWListener(using: parameters)` with no separate port argument.
- Port `4848` is a hardcoded constant in `EvolvMCPServer.swift`. If it's ever
  in use by something else, the app logs the failure and simply doesn't
  start the server -- it doesn't crash.
