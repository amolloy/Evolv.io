//
//  MCPFamilyTools.swift
//  Evolv.io
//
//  MCP tools on the family documents open in windows (see OpenFamilies and
//  Documentation/EvolutionUI.md): list them, read one, breed, mate,
//  reject, and name or star members. `mate_genotypes` mates two
//  expressions without a family, like `mutate_genotype`. Changes go through FamilyDocument like the
//  window's own, so they show up at once, mark the document edited and can
//  be undone in its window.
//

import Foundation
import MCP
import ExpressionTree

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

	static let tools: [Tool] = [
		Tool(
			name: "list_families",
			description: """
			Lists the family documents open in Evolv.io windows as JSON: id (for the other family \
			tools), name, path (absent until first saved), member, litter and generation counts.
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
		return await MainActor.run {
			do {
				let json: Any
				switch name {
					case "list_families": json = list()
					case "read_family": json = try read(args)
					case "breed_family": json = try breed(args)
					case "mate_family": json = try mate(args)
					case "mate_genotypes": json = try mateGenotypes(args)
					case "reject_family_members": json = try reject(args)
					default: json = try update(args)
				}
				let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
				return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
			} catch let failure as Failure {
				return errorResult(failure.message)
			} catch {
				return errorResult("\(name) failed: \(error.localizedDescription)")
			}
		}
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
		let settings = family.settings
		return [
			"id": entry.id,
			"name": entry.name,
			"settings": [
				"litter_size": settings.litterSize,
				"mutations_per_child": settings.mutationsPerChild,
				"max_depth": settings.maxDepth,
				"excluded_functions": settings.excludedFunctions,
			] as [String: Any],
			"litters": litterJSON,
			"members": memberJSON,
		]
	}

	@MainActor
	private static func breed(_ args: [String: MCP.Value]) throws -> [String: Any] {
		let entry = try family(args)
		let parents = try strings(args["parents"], "parents")
		try checkMembers(parents, in: entry)
		let litters = try entry.document.breed(Set(parents), seed: try seed(args["seed"]), undoManager: entry.undoManager)
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
											 undoManager: entry.undoManager)
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
		let removed = try entry.document.reject(Set(members), includingDescendants: includeDescendants, undoManager: entry.undoManager)
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
			entry.document.rename(id, to: name, undoManager: entry.undoManager)
		}
		if let starred = args["starred"]?.boolValue {
			entry.document.setStarred(starred, for: [id], undoManager: entry.undoManager)
		}
		let member = entry.document.family.member(id: id)!
		var json: [String: Any] = ["id": id, "starred": member.starred]
		json["name"] = member.name
		return json
	}

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
