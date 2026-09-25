//
//  MCPDebugValuesTool.swift
//  Evolv.io
//
//  The MCP `debug_values` tool: reports what the user is currently looking
//  at -- which genotype is selected in the sidebar, and, if the
//  debug view is open, the live value of every `debug` toggle/slider it
//  shows (see LiveDebugValues), grouped by node type and param name. Lets an
//  assistant read back settings the user dialed in by hand instead of
//  asking for them to be typed out.
//

import Foundation
import MCP
import ExpressionTree

/// What the UI reports to `debug_values`. ContentView writes the selection;
/// NodeDebuggingView registers its renderer while it's on screen. Weak so a
/// dismissed debug view never keeps a stale renderer alive.
@MainActor
enum MCPLiveUIState {
    static var selectedGenotypeID: String?
    static weak var debugViewRenderer: NodeRenderer?
}

enum MCPDebugValuesTool {
    static let tool = Tool(
        name: "debug_values",
        description: """
        Returns the app's current UI state as JSON: which genotype is selected in the \
        sidebar, whether the debug view is open, and the live value of every debug toggle/slider \
        the debug view shows, grouped by node type then param name (with each control's kind, \
        range and default). Controls are empty until the debug view is open and has rendered once.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call() async -> CallTool.Result {
        let json = await MainActor.run { snapshot() }
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Failed to encode debug values: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    @MainActor
    private static func snapshot() -> [String: Any] {
        var result: [String: Any] = [:]

        if let id = MCPLiveUIState.selectedGenotypeID,
           let selected = GenotypeStore.shared.genotype(id: id) {
            var expression: [String: Any] = [
                "id": selected.id,
                "source": selected.source.rawValue,
                "display_name": selected.displayName,
                "expression": selected.expression,
            ]
            if let originalImageName = selected.originalImageName {
                expression["original_image"] = originalImageName
            }
            result["selected_expression"] = expression
        } else {
            result["selected_expression"] = NSNull()
        }

        let renderer = MCPLiveUIState.debugViewRenderer
        result["debug_view_open"] = renderer != nil

        // node type -> param name -> control
        var controls: [String: [String: Any]] = [:]
        if let live = renderer?.liveDebugValues {
            for (index, slot) in live.slots.enumerated() {
                var control: [String: Any] = [
                    "default": jsonNumber(slot.defaultValue),
                    "slot_index": slot.slotIndex,
                ]
                switch slot.kind {
                case .toggle:
                    control["kind"] = "toggle"
                    control["value"] = live.values[index] != 0
                case .slider(let minBound, let maxBound):
                    control["kind"] = "slider"
                    control["min"] = jsonNumber(minBound)
                    control["max"] = jsonNumber(maxBound)
                    control["value"] = jsonNumber(live.values[index])
                }
                controls[slot.templateName, default: [:]][slot.paramName] = control
            }
        }
        result["controls"] = controls

        return result
    }

    /// JSONSerialization writes a Double with 17 significant digits (0.03
    /// comes out as 0.029999999999999999); going through the value's
    /// shortest description keeps the output as short as the slider label.
    private static func jsonNumber<T: BinaryFloatingPoint & LosslessStringConvertible>(_ value: T) -> NSDecimalNumber {
        NSDecimalNumber(string: value.description)
    }
}
