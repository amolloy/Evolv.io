//
//  ColorPalette.swift
//  ExpressionTree
//
//  Named palettes RandomExpressionGenerator can take vector literals from
//  (Configuration.palette). The colours come from published palette sets:
//  MetBrewer (Blake R. Mills, CC0; palettes from works in the
//  Metropolitan Museum of Art), wesanderson (Karthik Ram, MIT; from
//  wesandersonpalettes.tumblr.com), Coolors, and matplotlib's viridis.
//  See Documentation/RandomGeneration.md.
//

import Foundation

public struct ColorPalette: Hashable, Sendable, Identifiable {
	public let name: String
	/// `#RRGGBB`.
	public let colors: [String]

	public var id: String { name }

	public init(name: String, colors: [String]) {
		self.name = name
		self.colors = colors
	}

	public static let presets: [ColorPalette] = [
		// Coolors' popular teal/sand/coral palette; the first default.
		ColorPalette(name: "Coolors", colors: ["#264653", "#2A9D8F", "#E9C46A", "#F4A261", "#E76F51"]),
		// MetBrewer.
		ColorPalette(name: "Hokusai", colors: ["#6D2F20", "#B75347", "#DF7E66", "#E09351", "#EDC775", "#94B594", "#224B5E"]),
		ColorPalette(name: "Hiroshige", colors: ["#E76254", "#EF8A47", "#F7AA58", "#FFD06F", "#FFE6B7", "#AADCE0", "#72BCD5", "#528FAD", "#376795", "#1E466E"]),
		ColorPalette(name: "Klimt", colors: ["#DF9ED4", "#C93F55", "#EACC62", "#469D76", "#3C4B99", "#924099"]),
		ColorPalette(name: "Monet", colors: ["#4E6D58", "#749E89", "#ABCCBE", "#E3CACF", "#C399A2", "#9F6E71", "#41507B", "#7D87B2", "#C2CAE3"]),
		ColorPalette(name: "Van Gogh", colors: ["#BD3106", "#D9700E", "#E9A00E", "#EEBE04", "#5B7314", "#C3D6CE", "#89A6BB", "#454B87"]),
		ColorPalette(name: "Isfahan", colors: ["#4E3910", "#845D29", "#AE8548", "#E3C28B", "#4FB6CA", "#178F92", "#175F5D", "#054544"]),
		// wesanderson. Grand Budapest is its GrandBudapest1 and 2 together.
		ColorPalette(name: "Zissou", colors: ["#3B9AB2", "#78B7C5", "#EBCC2A", "#E1AF00", "#F21A00"]),
		ColorPalette(name: "Grand Budapest", colors: ["#F1BB7B", "#FD6467", "#5B1A18", "#D67236", "#E6A0C4", "#C6CDF7", "#7294D4"]),
		ColorPalette(name: "Moonrise Kingdom", colors: ["#85D4E3", "#F4B5BD", "#9C964A", "#CDC08C", "#FAD77B"]),
		ColorPalette(name: "Asteroid City", colors: ["#0A9F9D", "#CEB175", "#E54E21", "#6C8645", "#C18748"]),
		// matplotlib's viridis, five stops.
		ColorPalette(name: "Viridis", colors: ["#440154", "#3B528B", "#21918C", "#5EC962", "#FDE725"]),
	]

	public static func preset(named name: String) -> ColorPalette? {
		presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
	}

	/// `entries` as `#RRGGBB` colours, each entry a colour or a preset's
	/// name (which stands for all its colours), so
	/// `["Zissou", "#FFFFFF"]` is Zissou plus white. nil if an entry is
	/// neither.
	public static func colors(resolving entries: [String]) -> [String]? {
		var colors: [String] = []
		for entry in entries {
			if let preset = preset(named: entry) {
				colors += preset.colors
			} else if RandomExpressionGenerator.paletteColor(hex: entry) != nil {
				colors.append(entry)
			} else {
				return nil
			}
		}
		return colors
	}

	/// The preset whose colours are exactly `colors`, if any.
	public static func preset(matching colors: [String]) -> ColorPalette? {
		let wanted = colors.map { $0.uppercased() }
		return presets.first { $0.colors == wanted }
	}
}
