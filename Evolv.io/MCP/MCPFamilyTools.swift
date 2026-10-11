//
//  MCPFamilyTools.swift
//  Evolv.io
//
//  MCP tools on the family documents open in windows (see OpenFamilies and
//  Documentation/EvolutionUI.md): make, open, save and close them, list
//  them, read one, change its settings, add root litters, breed, mate,
//  reject, and name or star members. `mate_genotypes` mates two
//  expressions without a family, like `mutate_genotype`. Changes go through FamilyDocument like the
//  window's own, so they show up at once, mark the document edited and can
//  be undone in its window.
//

import Foundation
import MCP
import ExpressionTree
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum MCPFamilyTools {
	private static let familySchema: MCP.Value = .object([
		"type": .string("string"),
		"description": .string("Which open family: its id from list_families (\"f1\"), its name, or its file path. Optional when only one is open."),
	])

	private static func memberList(_ description: String) -> MCP.Value {
		.object([
			"type": .string("array"),
			"items": .object(["type": .string("string")]),
			"description": .string(description),
		])
	}

	private static let pathSchema: MCP.Value = .object([
		"type": .string("string"),
		"description": .string("A .evolvfamily path (~ allowed), or a bare name for ~/Documents/Evolv Families/<name>.evolvfamily."),
	])

	private static func nameList(_ description: String) -> MCP.Value {
		.object([
			"type": .string("array"),
			"items": .object(["type": .string("string")]),
			"description": .string(description),
		])
	}

	static let tools: [Tool] = [
		Tool(
			name: "new_family",
			description: """
			Opens a new, empty family in a window, as File > New does, and returns its id. With \
			`path` it's saved there at once (see save_family). Start it with add_random_litter \
			or add_seed_litter.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"path": pathSchema,
				]),
			])
		),
		Tool(
			name: "open_family",
			description: """
			Opens a saved .evolvfamily in a window, as File > Open does, and returns its id (an \
			already open one isn't opened twice). The app is sandboxed: it can open families in \
			~/Documents/Evolv Families/ and ones it has opened before; for others, open the file \
			with Finder or `open` first.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"path": pathSchema,
				]),
				"required": .array([.string("path")]),
			])
		),
		Tool(
			name: "save_family",
			description: """
			Saves an open family, as File > Save does. Without `path` it saves where it is (an \
			untitled family needs a path). With `path` it's saved there and the window follows \
			it, as Save As does. A bare name such as "Blue Ripples" goes in ~/Documents/Evolv \
			Families/, the folder the sandboxed app can always write; elsewhere works only where \
			the app already has access.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"path": pathSchema,
				]),
			])
		),
		Tool(
			name: "close_family",
			description: """
			Closes an open family's window. Fails if it has unsaved changes, unless \
			discard_changes is true.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"discard_changes": .object([
						"type": .string("boolean"),
						"description": .string("Close even with unsaved changes, losing them. Default false."),
					]),
				]),
			])
		),
		Tool(
			name: "update_family_settings",
			description: """
			Changes an open family's settings for new litters, as Family Settings does (litters \
			already made keep theirs). Only the given fields change. Returns the settings. \
			Undoable in the window.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"litter_size": .object(["type": .string("integer"), "description": .string("Children per litter, 1-60.")]),
					"mutations_per_child": .object(["type": .string("number"),
													"description": .string("Average mutations per child, 0.25-8.")]),
					"max_depth": .object(["type": .string("integer"),
										  "description": .string("Deepest nesting of function calls in new random material, 1-20.")]),
					"excluded_functions": nameList("Functions never introduced by a mutation or random litter."),
					"excluded_root_functions": nameList("Functions never at the root of a random genotype."),
					"excluded_variables": nameList("Variables (x, y, z) never introduced."),
					"palette": nameList("Colours new vector literals are sometimes taken from: #RRGGBB colours and preset names (\(ColorPalette.presets.map(\.name).joined(separator: ", "))). Empty turns it off."),
					"palette_chance": .object(["type": .string("number"),
											   "description": .string("Chance a new vector literal comes from the palette, 0-1.")]),
				]),
			])
		),
		Tool(
			name: "add_random_litter",
			description: """
			Adds a root litter of random genotypes (the family's litter size, made with its \
			settings), as New Random Litter does in the window. The same seed and settings give \
			the same genotypes as generate_genotypes. Undoable in the window.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"seed": .object([
						"type": .array([.string("integer"), .string("string")]),
						"description": .string("UInt64 seed, as an integer or a decimal string. Default: random."),
					]),
				]),
			])
		),
		Tool(
			name: "add_seed_litter",
			description: """
			Adds a root litter of given genotypes, as adding genotypes from files or the \
			clipboard does in the window. Undoable in the window.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"expressions": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
											"description": .string("S-expressions, one per member.")]),
					"names": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
									  "description": .string("Optional names for the members, in the same order.")]),
					"source": .object(["type": .string("string"),
									   "description": .string("Where they came from, shown with the litter.")]),
				]),
				"required": .array([.string("expressions")]),
			])
		),
		Tool(
			name: "list_families",
			description: """
			Lists the family documents open in Evolv.io windows as JSON: id (for the other family \
			tools), name, path (absent until first saved), edited (unsaved changes), member, \
			litter and generation counts.
			""",
			inputSchema: .object(["type": .string("object"), "properties": .object([:])])
		),
		Tool(
			name: "read_family",
			description: """
			Reads an open family as JSON: settings, litters (id, kind, parents, generation, seed, \
			source, member ids) and members (id, litter, index, generation, expression, \
			bred_from when someone has been bred from it, name and starred when set, and the \
			mutations that made it when include_mutations is true). Render members with \
			render or render_grid.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"generation": .object([
						"type": .string("integer"),
						"description": .string("Only members of this generation (0 is the roots)."),
					]),
					"include_mutations": .object([
						"type": .string("boolean"),
						"description": .string("Include each member's mutation log. Default false."),
					]),
				]),
			])
		),
		Tool(
			name: "breed_family",
			description: """
			Breeds a litter of mutated children (the family's litter size, settings from its \
			Family Settings) from each listed member, exactly as pressing Return in the window \
			does, and returns the new litters' ids and children. Undoable in the window.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"parents": memberList("Member ids to breed from, e.g. [\"g4\"]."),
					"seed": .object([
						"type": .array([.string("integer"), .string("string")]),
						"description": .string("UInt64 seed for the first litter (the next gets seed + 1, ...), as an integer or a decimal string. Default: random."),
					]),
				]),
				"required": .array([.string("parents")]),
			])
		),
		Tool(
			name: "mate_family",
			description: """
			Mates two members of an open family, as Mate does in the window: graft (a random node \
			of one parent replaced by a random node of the other, the receiving parent a coin \
			flip per child) or crossover (both trees walked together, either parent's version \
			taken at each difference; needs the same root). Up to the litter size of different \
			children, none equal to a parent, so crossover litters are often smaller. Returns the \
			litter and each child's base parent and grafts. Undoable in the window.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"parents": memberList("Two member ids; the first is the primary parent, whose branch the litter is drawn in."),
					"method": .object(["type": .string("string"), "enum": .array([.string("graft"), .string("crossover")]),
									   "description": .string("Default graft.")]),
					"seed": .object([
						"type": .array([.string("integer"), .string("string")]),
						"description": .string("UInt64 seed, as an integer or a decimal string. Default: random."),
					]),
				]),
				"required": .array([.string("parents")]),
			])
		),
		Tool(
			name: "mate_genotypes",
			description: """
			Mates two expressions without a family: up to `count` different children by graft or \
			crossover (see mate_family), none equal to a parent. Returns JSON: seed, and each \
			child's expression, base (0 or 1, the parent it's built on) and grafts (kind, path in \
			the base, before, after). Same seed, same children.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"parents": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
										"description": .string("Two s-expressions.")]),
					"method": .object(["type": .string("string"), "enum": .array([.string("graft"), .string("crossover")]),
									   "description": .string("Default graft.")]),
					"count": .object(["type": .string("integer"), "description": .string("Most children, 1-100. Default 19.")]),
					"seed": .object([
						"type": .array([.string("integer"), .string("string")]),
						"description": .string("UInt64 seed, as an integer or a decimal string. Default: random."),
					]),
				]),
				"required": .array([.string("parents")]),
			])
		),
		Tool(
			name: "reject_family_members",
			description: """
			Removes members from an open family. A member with descendants can only go with \
			them, so that fails unless include_descendants is true. Undoable in the window.
			""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"members": memberList("Member ids to reject."),
					"include_descendants": .object([
						"type": .string("boolean"),
						"description": .string("Also reject everything bred from them. Default false."),
					]),
				]),
				"required": .array([.string("members")]),
			])
		),
		Tool(
			name: "update_family_member",
			description: "Names (\"\" removes the name) or stars a member of an open family. Undoable in the window.",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"family": familySchema,
					"member": .object(["type": .string("string"), "description": .string("Member id.")]),
					"name": .object(["type": .string("string")]),
					"starred": .object(["type": .string("boolean")]),
				]),
				"required": .array([.string("member")]),
			])
		),
	]

	private struct Failure: Error {
		let message: String
	}

	/// The result for one of these tools, or nil if `name` isn't one.
	static func call(name: String, arguments: [String: MCP.Value]?) async -> CallTool.Result? {
		guard tools.contains(where: { $0.name == name }) else { return nil }
		let args = arguments ?? [:]
		if ["new_family", "open_family", "save_family", "close_family"].contains(name) {
			return await asyncCall(name: name, args: args)
		}
		return await MainActor.run {
			do {
				let json: Any
				switch name {
					case "update_family_settings": json = try updateSettings(args)
					case "add_random_litter": json = try addRandomLitter(args)
					case "add_seed_litter": json = try addSeedLitter(args)
					case "list_families": json = list()
					case "read_family": json = try read(args)
					case "breed_family": json = try breed(args)
					case "mate_family": json = try mate(args)
					case "mate_genotypes": json = try mateGenotypes(args)
					case "reject_family_members": json = try reject(args)
					default: json = try update(args)
				}
				return try result(json)
			} catch {
				return errorResult(name, error)
			}
		}
	}

	/// The tools that wait for a window to open or a save to finish.
	@MainActor
	private static func asyncCall(name: String, args: [String: MCP.Value]) async -> CallTool.Result {
		do {
			let json: Any
			switch name {
				case "new_family": json = try await newFamily(args)
				case "open_family": json = try await open(args)
				case "close_family": json = try await close(args)
				default: json = try await save(args)
			}
			return try result(json)
		} catch {
			return errorResult(name, error)
		}
	}

	private static func result(_ json: Any) throws -> CallTool.Result {
		let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
		return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
	}

	private static func errorResult(_ name: String, _ error: Error) -> CallTool.Result {
		if let failure = error as? Failure {
			return errorResult(failure.message)
		}
		return errorResult("\(name) failed: \(error.localizedDescription)")
	}

	// MARK: - Tools

	@MainActor
	private static func list() -> [[String: Any]] {
		OpenFamilies.shared.all.map { entry in
			let family = entry.document.family
			var json: [String: Any] = [
				"id": entry.id,
				"name": entry.name,
				"members": family.members.count,
				"litters": family.litters.count,
				"generations": (family.generations().values.max() ?? -1) + 1,
			]
			json["path"] = entry.fileURL?.path
#if os(macOS)
			json["edited"] = entry.nsDocument?.isDocumentEdited
#endif
			return json
		}
	}

	@MainActor
	private static func read(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		let family = entry.document.family
		let generations = family.generations()
		let onlyGeneration = try integer(args["generation"], "generation")
		let includeMutations = args["include_mutations"]?.boolValue ?? false
		let bredFrom = Set(family.litters.flatMap(\.parents))

		let members = family.members.filter { onlyGeneration == nil || generations[$0.id] == onlyGeneration }
		let memberJSON: [[String: Any]] = members.map { member in
			var json: [String: Any] = [
				"id": member.id,
				"litter": member.litter,
				"index": member.index,
				"generation": generations[member.id] ?? 0,
				"expression": member.expression,
			]
			if bredFrom.contains(member.id) { json["bred_from"] = true }
			if let base = member.base { json["base"] = base }
			if let name = member.name { json["name"] = name }
			if member.starred { json["starred"] = true }
			if includeMutations, !member.mutations.isEmpty {
				json["mutations"] = member.mutations.map { ["kind": $0.kind, "path": $0.path, "before": $0.before, "after": $0.after] as [String: Any] }
			}
			return json
		}
		let litterIDs = Set(members.map(\.litter))
		let litterJSON: [[String: Any]] = family.litters.filter { litterIDs.contains($0.id) }.map { litter in
			var json: [String: Any] = [
				"id": litter.id,
				"kind": litter.kind.rawValue,
				"parents": litter.parents,
				"generation": family.generation(ofLitter: litter.id, generations: generations),
				"members": family.members(ofLitter: litter.id).map(\.id),
			]
			json["seed"] = litter.seed.map(String.init)
			json["source"] = litter.source
			json["method"] = litter.method
			return json
		}
		return [
			"id": entry.id,
			"name": entry.name,
			"settings": settingsJSON(family.settings),
			"litters": litterJSON,
			"members": memberJSON,
		]
	}

	@MainActor
	private static func breed(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		let parents = try strings(args["parents"], "parents")
		try checkMembers(parents, in: entry)
		let litters = try entry.document.breed(Set(parents), seed: try seed(args["seed"]), undoManager: entry.changeUndoManager)
		let family = entry.document.family
		return [
			"litters": litters.map { litter in
				[
					"id": litter.id,
					"parents": litter.parents,
					"seed": litter.seed.map(String.init) ?? "",
					"children": family.members(ofLitter: litter.id).map { ["id": $0.id, "expression": $0.expression] },
				] as [String: Any]
			},
		]
	}

	@MainActor
	private static func mate(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		let parents = try strings(args["parents"], "parents")
		guard parents.count == 2 else { throw Failure(message: "parents must be two member ids.") }
		try checkMembers(parents, in: entry)
		let litter = try entry.document.mate(parents[0], parents[1], method: try method(args), seed: try seed(args["seed"]),
											 undoManager: entry.changeUndoManager)
		return [
			"id": litter.id,
			"method": litter.method ?? "",
			"parents": litter.parents,
			"seed": litter.seed.map(String.init) ?? "",
			"children": entry.document.family.members(ofLitter: litter.id).map { member in
				[
					"id": member.id,
					"expression": member.expression,
					"base": member.base ?? "",
					"grafts": member.mutations.map { ["kind": $0.kind, "path": $0.path, "before": $0.before, "after": $0.after] as [String: Any] },
				] as [String: Any]
			},
		]
	}

	@MainActor
	private static func mateGenotypes(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let texts = try strings(args["parents"], "parents")
		guard texts.count == 2 else { throw Failure(message: "parents must be two expressions.") }
		let parents = try texts.map { text in
			do {
				return try GeneratedExpression(parsing: text)
			} catch {
				throw Failure(message: "Couldn't read \(text): \(error)")
			}
		}
		let method = try method(args)
		let count = try integer(args["count"], "count") ?? 19
		guard (1...100).contains(count) else { throw Failure(message: "count must be 1-100.") }
		let seed = try seed(args["seed"]) ?? UInt64.random(in: 0...UInt64.max)
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.excludedRootFunctions = UserDefaults.standard.randomExcludedRootNodes
		configuration.excludedVariables = UserDefaults.standard.randomExcludedVariables
		UserDefaults.standard.applyRandomPalette(to: &configuration)
		let mutator = ExpressionMutator(generator: RandomExpressionGenerator(signatures: NodeRegistry.shared.signatures,
																			 configuration: configuration))
		let unknown = mutator.unknownNodes(in: parents[0]).union(mutator.unknownNodes(in: parents[1]))
		guard unknown.isEmpty else {
			throw Failure(message: "The parents use nodes that aren't loaded: \(unknown.sorted().joined(separator: ", ")).")
		}
		if method == .crossover && !mutator.canCrossOver(parents[0], parents[1]) {
			throw Failure(message: "Crossover needs parents with the same root function; try graft.")
		}
		var rng = SeededRandomNumberGenerator(seed: seed)
		let children = mutator.mate((parents[0], parents[1]), method: method, count: count, using: &rng)
		return [
			"seed": String(seed),
			"method": method.rawValue,
			"parents": parents.map(\.description),
			"children": children.map { child in
				[
					"expression": child.expression.description,
					"node_count": child.expression.nodeCount,
					"base": child.base,
					"grafts": child.grafts.map { ["kind": $0.kind.rawValue, "path": $0.path, "before": $0.before.description, "after": $0.after.description] as [String: Any] },
				] as [String: Any]
			},
		]
	}

	@MainActor
	private static func reject(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		let members = try strings(args["members"], "members")
		try checkMembers(members, in: entry)
		let includeDescendants = args["include_descendants"]?.boolValue ?? false
		let removed = try entry.document.reject(Set(members), includingDescendants: includeDescendants, undoManager: entry.changeUndoManager)
		return ["removed": removed.sorted()]
	}

	@MainActor
	private static func update(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		guard case .string(let id)? = args["member"] else {
			throw Failure(message: "member must be a member id.")
		}
		try checkMembers([id], in: entry)
		if case .string(let name)? = args["name"] {
			entry.document.rename(id, to: name, undoManager: entry.changeUndoManager)
		}
		if let starred = args["starred"]?.boolValue {
			entry.document.setStarred(starred, for: [id], undoManager: entry.changeUndoManager)
		}
		let member = entry.document.family.member(id: id)!
		var json: [String: Any] = ["id": id, "starred": member.starred]
		json["name"] = member.name
		return json
	}


	private static func settingsJSON(_ settings: Family.Settings) -> [String: Any] {
		[
			"litter_size": settings.litterSize,
			"mutations_per_child": settings.mutationsPerChild,
			"max_depth": settings.maxDepth,
			"excluded_functions": settings.excludedFunctions,
			"excluded_root_functions": settings.excludedRootFunctions,
			"excluded_variables": settings.excludedVariables,
			"palette": settings.palette ?? [],
			"palette_chance": settings.paletteChance ?? RandomExpressionGenerator.Configuration.defaultPaletteChance,
		]
	}

	@MainActor
	private static func updateSettings(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		var settings = entry.document.family.settings
		if let size = try integer(args["litter_size"], "litter_size") {
			guard (1...60).contains(size) else { throw Failure(message: "litter_size must be 1-60.") }
			settings.litterSize = size
		}
		if let rate = try number(args["mutations_per_child"], "mutations_per_child") {
			guard (0.25...8).contains(rate) else { throw Failure(message: "mutations_per_child must be 0.25-8.") }
			settings.mutationsPerChild = rate
		}
		if let depth = try integer(args["max_depth"], "max_depth") {
			guard (1...20).contains(depth) else { throw Failure(message: "max_depth must be 1-20.") }
			settings.maxDepth = depth
		}
		let signatures = NodeRegistry.shared.signatures
		if let names = try names(args["excluded_functions"], "excluded_functions") {
			try checkFunctions(names, signatures, "excluded_functions")
			settings.excludedFunctions = names.sorted()
		}
		if let names = try names(args["excluded_root_functions"], "excluded_root_functions") {
			try checkFunctions(names, signatures, "excluded_root_functions")
			settings.excludedRootFunctions = names.sorted()
		}
		if let names = try names(args["excluded_variables"], "excluded_variables") {
			let unknown = names.filter { !["x", "y", "z"].contains($0) }
			guard unknown.isEmpty else { throw Failure(message: "excluded_variables can only hold x, y and z, not \(unknown.joined(separator: ", ")).") }
			settings.excludedVariables = names.sorted()
		}
		if let entries = try names(args["palette"], "palette") {
			let bad = entries.filter { ColorPalette.colors(resolving: [$0]) == nil }
			guard bad.isEmpty else {
				throw Failure(message: "palette entries must be #RRGGBB or a preset name, not \(bad.joined(separator: ", ")).")
			}
			settings.palette = ColorPalette.colors(resolving: entries)
		}
		if let chance = try number(args["palette_chance"], "palette_chance") {
			guard (0...1).contains(chance) else { throw Failure(message: "palette_chance must be 0-1.") }
			settings.paletteChance = chance
		}
		if settings != entry.document.family.settings {
			entry.document.change("Change Family Settings", undoManager: entry.changeUndoManager) { $0.settings = settings }
		}
		return settingsJSON(entry.document.family.settings)
	}

	private static func checkFunctions(_ names: [String], _ signatures: [String: NodeSignature], _ argument: String) throws {
		let unknown = names.filter { signatures[$0] == nil }
		guard unknown.isEmpty else {
			throw Failure(message: "\(argument) has functions that aren't loaded: \(unknown.joined(separator: ", ")).")
		}
	}

	@MainActor
	private static func addRandomLitter(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		let litter = entry.document.addRandomLitter(seed: try seed(args["seed"]), undoManager: entry.changeUndoManager)
		return litterJSON(litter, in: entry)
	}

	@MainActor
	private static func addSeedLitter(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		guard let expressions = try names(args["expressions"], "expressions"), !expressions.isEmpty else {
			throw Failure(message: "expressions must be a non-empty array of s-expressions.")
		}
		for text in expressions {
			do {
				_ = try GeneratedExpression(parsing: text)
			} catch {
				throw Failure(message: "Couldn't read \(text): \(error)")
			}
		}
		let memberNames = try names(args["names"], "names") ?? []
		guard memberNames.count <= expressions.count else { throw Failure(message: "There are more names than expressions.") }
		var source: String?
		if case .string(let text)? = args["source"] { source = text }
		let litter = try entry.document.addSeedLitter(expressions: expressions, names: memberNames, source: source,
													  undoManager: entry.changeUndoManager)
		return litterJSON(litter, in: entry)
	}

	@MainActor
	private static func litterJSON(_ litter: Family.Litter, in entry: OpenFamilies.Entry) -> [String: Any] {
		var json: [String: Any] = [
			"id": litter.id,
			"kind": litter.kind.rawValue,
			"members": entry.document.family.members(ofLitter: litter.id).map { member in
				var json: [String: Any] = ["id": member.id, "expression": member.expression]
				json["name"] = member.name
				return json
			},
		]
		json["seed"] = litter.seed.map(String.init)
		json["source"] = litter.source
		return json
	}

	// MARK: - Windows and files

	/// Where a bare name goes: the folder the sandboxed app is allowed to
	/// write (see the temporary exception in Evolv_io.entitlements).
	static let defaultFolderName = "Documents/Evolv Families"

	/// The user's real home, not the sandbox container's.
	private static var homeDirectory: URL {
		if let home = getpwuid(getuid())?.pointee.pw_dir {
			return URL(fileURLWithPath: String(cString: home), isDirectory: true)
		}
		return FileManager.default.homeDirectoryForCurrentUser
	}

	private static func fileURL(_ args: [String: MCP.Value]) throws -> URL? {
		let text: String
		switch args["path"] {
			case nil, .null?: return nil
			case .string(let value)?: text = value
			default: throw Failure(message: "path must be a string.")
		}
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw Failure(message: "path is empty.") }
		var url: URL
		if trimmed.hasPrefix("~/") {
			url = homeDirectory.appending(path: String(trimmed.dropFirst(2)))
		} else if trimmed.hasPrefix("/") {
			url = URL(fileURLWithPath: trimmed)
		} else if !trimmed.contains("/") {
			url = homeDirectory.appending(path: defaultFolderName).appending(path: trimmed)
		} else {
			throw Failure(message: "path must be absolute, start with ~/, or be a bare name.")
		}
		if url.pathExtension != "evolvfamily" {
			url = url.appendingPathExtension("evolvfamily")
		}
		return url.standardizedFileURL
	}

#if os(macOS)
	/// Waits for the window showing `document` to register.
	@MainActor
	private static func entry(for document: NSDocument) async throws -> OpenFamilies.Entry {
		for _ in 0..<100 {
			if let entry = OpenFamilies.shared.all.first(where: { $0.nsDocument === document }) {
				return entry
			}
			try await Task.sleep(for: .milliseconds(50))
		}
		throw Failure(message: "The family opened, but its window didn't appear.")
	}

	@MainActor
	private static func nsDocument(_ entry: OpenFamilies.Entry) throws -> NSDocument {
		guard let document = entry.nsDocument else {
			throw Failure(message: "\(entry.name)'s window isn't ready; try again.")
		}
		return document
	}

	@MainActor
	private static func newFamily(_ args: [String: MCP.Value]) async throws -> [String: Any] {
		let url = try fileURL(args)
		let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
		let entry = try await entry(for: document)
		if let url {
			try await save(entry, to: url)
		}
		return try describe(entry.id)
	}

	@MainActor
	private static func open(_ args: [String: MCP.Value]) async throws -> [String: Any] {
		guard let url = try fileURL(args) else { throw Failure(message: "open_family needs a path.") }
		let document: NSDocument
		do {
			(document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
		} catch {
			throw Failure(message: "Couldn't open \(url.path): \(error.localizedDescription) Outside ~/\(defaultFolderName), the sandboxed app can only open files it's been given, so open it with Finder or `open` instead.")
		}
		return try describe(try await entry(for: document).id)
	}

	@MainActor
	private static func save(_ args: [String: MCP.Value]) async throws -> [String: Any] {
		let entry = try family(args)
		if let url = try fileURL(args) {
			try await save(entry, to: url)
		} else {
			let document = try nsDocument(entry)
			guard let url = document.fileURL else {
				throw Failure(message: "\(entry.name) hasn't been saved yet; give a path or a name.")
			}
			try await document.save(to: url, ofType: document.fileType ?? UTType.evolvFamily.identifier, for: .saveOperation)
		}
		return try describe(entry.id)
	}

	/// Saves as `url`, which the window then shows.
	@MainActor
	private static func save(_ entry: OpenFamilies.Entry, to url: URL) async throws {
		let document = try nsDocument(entry)
		do {
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try await document.save(to: url, ofType: document.fileType ?? UTType.evolvFamily.identifier, for: .saveAsOperation)
		} catch {
			throw Failure(message: "Couldn't save to \(url.path): \(error.localizedDescription) The sandboxed app can always save in ~/\(defaultFolderName); pass a bare name to save there.")
		}
		OpenFamilies.shared.register(entry.document, fileURL: document.fileURL ?? url, undoManager: nil)
	}

	@MainActor
	private static func close(_ args: [String: MCP.Value]) async throws -> [String: Any] {
		let entry = try family(args)
		let document = try nsDocument(entry)
		// A change marks the document edited when its undo group ends, at
		// the end of the run loop pass, so let a change just made land.
		try await Task.sleep(for: .milliseconds(100))
		if document.isDocumentEdited && args["discard_changes"]?.boolValue != true {
			throw Failure(message: "\(entry.name) has unsaved changes; save it first, or pass discard_changes.")
		}
		document.close()
		return ["closed": entry.id, "name": entry.name]
	}

	/// list_families' entry for one family.
	@MainActor
	private static func describe(_ id: String) throws -> [String: Any] {
		guard let json = list().first(where: { $0["id"] as? String == id }) else {
			throw Failure(message: "The family closed.")
		}
		return json
	}
#else
	private static func unavailable() -> Failure {
		Failure(message: "Family windows and files are only available over MCP on macOS.")
	}

	@MainActor private static func newFamily(_ args: [String: MCP.Value]) async throws -> [String: Any] { throw unavailable() }
	@MainActor private static func open(_ args: [String: MCP.Value]) async throws -> [String: Any] { throw unavailable() }
	@MainActor private static func save(_ args: [String: MCP.Value]) async throws -> [String: Any] { throw unavailable() }
	@MainActor private static func close(_ args: [String: MCP.Value]) async throws -> [String: Any] { throw unavailable() }
#endif

	// MARK: - Arguments

	@MainActor
	private static func family(_ args: [String: MCP.Value]) throws -> OpenFamilies.Entry {
		var key: String?
		if case .string(let value)? = args["family"] { key = value }
		if let entry = OpenFamilies.shared.find(key) {
			return entry
		}
		let open = OpenFamilies.shared.all
		if open.isEmpty {
			throw Failure(message: "No family is open. Open or create one in Evolv.io (File > New or Open).")
		}
		let names = open.map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
		throw Failure(message: key == nil ? "Several families are open; say which: \(names)." : "No open family matches \"\(key!)\". Open: \(names).")
	}

	@MainActor
	private static func checkMembers(_ ids: [String], in entry: OpenFamilies.Entry) throws {
		let missing = ids.filter { entry.document.family.member(id: $0) == nil }
		guard missing.isEmpty else {
			throw Failure(message: "\(entry.name) has no member \(missing.joined(separator: ", ")).")
		}
	}

	private static func strings(_ value: MCP.Value?, _ name: String) throws -> [String] {
		guard case .array(let values)? = value else {
			throw Failure(message: "\(name) must be an array of member ids.")
		}
		let ids = values.compactMap { value -> String? in
			if case .string(let id) = value { return id }
			return nil
		}
		guard !ids.isEmpty, ids.count == values.count else {
			throw Failure(message: "\(name) must be a non-empty array of member ids.")
		}
		return ids
	}

	private static func method(_ args: [String: MCP.Value]) throws -> MatingMethod {
		switch args["method"] {
			case nil, .null?: return .graft
			case .string(let text)?:
				guard let method = MatingMethod(rawValue: text) else { throw Failure(message: "method must be graft or crossover.") }
				return method
			default: throw Failure(message: "method must be graft or crossover.")
		}
	}

	private static func integer(_ value: MCP.Value?, _ name: String) throws -> Int? {
		switch value {
			case nil, .null?: return nil
			case .int(let int)?: return int
			case .double(let double)? where double == double.rounded(): return Int(double)
			default: throw Failure(message: "\(name) must be an integer.")
		}
	}

	private static func number(_ value: MCP.Value?, _ name: String) throws -> Double? {
		switch value {
			case nil, .null?: return nil
			case .int(let int)?: return Double(int)
			case .double(let double)?: return double
			default: throw Failure(message: "\(name) must be a number.")
		}
	}

	/// An array of strings, possibly empty.
	private static func names(_ value: MCP.Value?, _ name: String) throws -> [String]? {
		switch value {
			case nil, .null?: return nil
			case .array(let values)?:
				let names = values.compactMap { value -> String? in
					if case .string(let text) = value { return text }
					return nil
				}
				guard names.count == values.count else { throw Failure(message: "\(name) must be an array of strings.") }
				return names
			default: throw Failure(message: "\(name) must be an array of strings.")
		}
	}

	private static func seed(_ value: MCP.Value?) throws -> UInt64? {
		switch value {
			case nil, .null?:
				return nil
			case .int(let value)? where value >= 0:
				return UInt64(value)
			case .string(let text)?:
				guard let parsed = UInt64(text) else { throw Failure(message: "seed \"\(text)\" isn't a UInt64.") }
				return parsed
			default:
				throw Failure(message: "seed must be a non-negative integer or a decimal string.")
		}
	}

	private static func errorResult(_ text: String) -> CallTool.Result {
		CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
	}
}
