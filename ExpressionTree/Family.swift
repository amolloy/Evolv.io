//
//  Family.swift
//  ExpressionTree
//
//  A family: every genotype in one line of evolution, the unexplored
//  branches included, minus the ones the user rejected. Members come in
//  litters, the children of one breeding action, and a litter records its
//  parents, seed and settings so it can be made again. This is the model
//  and its `family.json` coding; the document and lineage view are in the
//  app. See Documentation/EvolutionUI.md.
//

import Foundation

public struct Family: Equatable, Sendable {
	public static let currentFormat = 1

	public var created: Date
	/// The number in the next id handed out. Ids are never reused, so a
	/// rejected member's id stays unused.
	public var nextID: Int
	/// Defaults for new litters. Each litter keeps its own copy.
	public var settings: Settings
	/// In the order they were made.
	public private(set) var litters: [Litter]
	/// In the order they were made; a litter's members are together and in
	/// litter order.
	public private(set) var members: [Member]

	public init(settings: Settings = Settings(), created: Date = Date()) {
		self.created = created
		self.nextID = 1
		self.settings = settings
		self.litters = []
		self.members = []
	}

	// MARK: - Types

	public struct Settings: Codable, Equatable, Sendable {
		/// Children per breed. Sims showed 19 (a parent and 19 children
		/// make his 4x5 sheets).
		public var litterSize: Int = 19
		public var mutationsPerChild: Double = 1
		public var maxDepth: Int = RandomExpressionGenerator.Configuration().maxDepth
		/// Nodes a mutation or random litter never introduces.
		public var excludedFunctions: [String] = []
		public var excludedRootFunctions: [String] = RandomExpressionGenerator.Configuration.defaultExcludedRootFunctions.sorted()
		public var excludedVariables: [String] = RandomExpressionGenerator.Configuration.defaultExcludedVariables.sorted()

		public init() {}

		public var generatorConfiguration: RandomExpressionGenerator.Configuration {
			var configuration = RandomExpressionGenerator.Configuration()
			configuration.maxDepth = maxDepth
			configuration.excludedFunctions = Set(excludedFunctions)
			configuration.excludedRootFunctions = Set(excludedRootFunctions)
			configuration.excludedVariables = Set(excludedVariables)
			return configuration
		}

		public var mutatorConfiguration: ExpressionMutator.Configuration {
			var configuration = ExpressionMutator.Configuration()
			configuration.mutationsPerChild = mutationsPerChild
			return configuration
		}
	}

	public struct Litter: Codable, Equatable, Identifiable, Sendable {
		/// How a litter was made. A plain string underneath, so a family
		/// written by a newer version with kinds this one doesn't know still
		/// opens.
		public struct Kind: RawRepresentable, Codable, Hashable, Sendable {
			public let rawValue: String
			public init(rawValue: String) { self.rawValue = rawValue }

			/// No parents: new genotypes from RandomExpressionGenerator.
			public static let random = Kind(rawValue: "random")
			/// No parents: genotypes brought in from the library, a file or
			/// pasted text.
			public static let seed = Kind(rawValue: "seed")
			/// One parent: ExpressionMutator children.
			public static let mutation = Kind(rawValue: "mutation")
			/// Two parents. Not implemented yet; reserved so the format
			/// doesn't change when it is.
			public static let mating = Kind(rawValue: "mating")

			public init(from decoder: Decoder) throws {
				rawValue = try decoder.singleValueContainer().decode(String.self)
			}

			public func encode(to encoder: Encoder) throws {
				var container = encoder.singleValueContainer()
				try container.encode(rawValue)
			}
		}

		public let id: String
		public let kind: Kind
		/// Member ids, empty for a root litter. The first is the primary
		/// parent, whose branch the litter is drawn in.
		public let parents: [String]
		/// The seed the children were drawn with, for `random` and
		/// `mutation`. Written as a string, since JSON numbers lose
		/// precision above 2^53.
		public let seed: UInt64?
		/// Where a `seed` litter came from, e.g. `library:11-figure-9`.
		public let source: String?
		/// The settings the litter was made with, for `random` and
		/// `mutation`.
		public let settings: Settings?
		public let created: Date

		enum CodingKeys: String, CodingKey {
			case id, kind, parents, seed, source, settings, created
		}

		public init(id: String, kind: Kind, parents: [String], seed: UInt64?, source: String?, settings: Settings?, created: Date) {
			self.id = id
			self.kind = kind
			self.parents = parents
			self.seed = seed
			self.source = source
			self.settings = settings
			self.created = created
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			id = try container.decode(String.self, forKey: .id)
			kind = try container.decode(Kind.self, forKey: .kind)
			parents = try container.decodeIfPresent([String].self, forKey: .parents) ?? []
			if let text = try container.decodeIfPresent(String.self, forKey: .seed) {
				guard let value = UInt64(text) else {
					throw DecodingError.dataCorruptedError(forKey: .seed, in: container, debugDescription: "seed \"\(text)\" isn't a UInt64")
				}
				seed = value
			} else {
				seed = nil
			}
			source = try container.decodeIfPresent(String.self, forKey: .source)
			settings = try container.decodeIfPresent(Settings.self, forKey: .settings)
			created = try container.decode(Date.self, forKey: .created)
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(id, forKey: .id)
			try container.encode(kind, forKey: .kind)
			try container.encode(parents, forKey: .parents)
			try container.encodeIfPresent(seed.map(String.init), forKey: .seed)
			try container.encodeIfPresent(source, forKey: .source)
			try container.encodeIfPresent(settings, forKey: .settings)
			try container.encode(created, forKey: .created)
		}
	}

	public struct Member: Codable, Equatable, Identifiable, Sendable {
		public let id: String
		public let litter: String
		/// Position in its litter, from 0. Kept after siblings are rejected,
		/// so it can have gaps.
		public let index: Int
		/// Genotype text. Not parsed when the family loads, so a member
		/// using a node that isn't loaded any more still opens.
		public let expression: String
		/// What changed from the parent, for a `mutation` child.
		public let mutations: [MutationRecord]
		public var name: String?
		public var starred: Bool
		/// View state: the lineage view hides this member's descendants.
		public var collapsed: Bool

		enum CodingKeys: String, CodingKey {
			case id, litter, index, expression, mutations, name, starred, collapsed
		}

		public init(id: String, litter: String, index: Int, expression: String, mutations: [MutationRecord] = [],
					name: String? = nil, starred: Bool = false, collapsed: Bool = false) {
			self.id = id
			self.litter = litter
			self.index = index
			self.expression = expression
			self.mutations = mutations
			self.name = name
			self.starred = starred
			self.collapsed = collapsed
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			id = try container.decode(String.self, forKey: .id)
			litter = try container.decode(String.self, forKey: .litter)
			index = try container.decode(Int.self, forKey: .index)
			expression = try container.decode(String.self, forKey: .expression)
			mutations = try container.decodeIfPresent([MutationRecord].self, forKey: .mutations) ?? []
			name = try container.decodeIfPresent(String.self, forKey: .name)
			starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
			collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
		}

		/// Leaves out empty and default fields, so the file stays readable.
		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(id, forKey: .id)
			try container.encode(litter, forKey: .litter)
			try container.encode(index, forKey: .index)
			try container.encode(expression, forKey: .expression)
			if !mutations.isEmpty { try container.encode(mutations, forKey: .mutations) }
			try container.encodeIfPresent(name, forKey: .name)
			if starred { try container.encode(starred, forKey: .starred) }
			if collapsed { try container.encode(collapsed, forKey: .collapsed) }
		}
	}

	/// One entry of ExpressionMutator's log, as text.
	public struct MutationRecord: Codable, Equatable, Sendable {
		public let kind: String
		/// Argument indices from the root to the node that mutated.
		public let path: [Int]
		public let before: String
		public let after: String

		public init(kind: String, path: [Int], before: String, after: String) {
			self.kind = kind
			self.path = path
			self.before = before
			self.after = after
		}

		public init(_ mutation: ExpressionMutator.Mutation) {
			self.init(kind: mutation.kind.rawValue, path: mutation.path,
					  before: mutation.before.description, after: mutation.after.description)
		}
	}

	public struct FamilyError: LocalizedError, Equatable {
		public let errorDescription: String?
		init(_ message: String) { errorDescription = message }
	}

	// MARK: - Lookups

	public func member(id: String) -> Member? {
		members.first { $0.id == id }
	}

	public func litter(id: String) -> Litter? {
		litters.first { $0.id == id }
	}

	/// The members of `litterID`, in litter order.
	public func members(ofLitter litterID: String) -> [Member] {
		members.filter { $0.litter == litterID }.sorted { $0.index < $1.index }
	}

	/// A member's parents' ids (its litter's parents).
	public func parents(of memberID: String) -> [String] {
		member(id: memberID).flatMap { litter(id: $0.litter) }?.parents ?? []
	}

	/// The litters with `memberID` as a parent, in the order they were made.
	public func litters(bredFrom memberID: String) -> [Litter] {
		litters.filter { $0.parents.contains(memberID) }
	}

	public func hasBeenBredFrom(_ memberID: String) -> Bool {
		litters.contains { $0.parents.contains(memberID) }
	}

	/// Every member descended from any of `memberIDs`, not including them.
	public func descendants(of memberIDs: Set<String>) -> Set<String> {
		var found = Set<String>()
		var frontier = memberIDs
		while !frontier.isEmpty {
			let childLitters = Set(litters.filter { !Set($0.parents).isDisjoint(with: frontier) }.map(\.id))
			let children = Set(members.filter { childLitters.contains($0.litter) }.map(\.id)).subtracting(found)
			found.formUnion(children)
			frontier = children
		}
		return found.subtracting(memberIDs)
	}

	/// Each member's generation: 0 for roots, otherwise one more than its
	/// highest-generation parent. The lineage view's columns.
	public func generations() -> [String: Int] {
		let litterOfMember = Dictionary(members.map { ($0.id, $0.litter) }, uniquingKeysWith: { first, _ in first })
		var generationByLitter: [String: Int] = [:]
		// Litters only ever have parents made before them, so one pass in
		// creation order is enough.
		for litter in litters {
			generationByLitter[litter.id] = litter.parents
				.map { parent in litterOfMember[parent].flatMap { generationByLitter[$0] }.map { $0 + 1 } ?? 0 }
				.max() ?? 0
		}
		return Dictionary(members.map { ($0.id, generationByLitter[$0.litter] ?? 0) }, uniquingKeysWith: { first, _ in first })
	}

	/// A litter's generation (its members' column).
	public func generation(ofLitter litterID: String, generations: [String: Int]? = nil) -> Int {
		let generations = generations ?? self.generations()
		return litter(id: litterID)?.parents.map { (generations[$0] ?? -1) + 1 }.max() ?? 0
	}

	// MARK: - Making members

	/// Adds a root litter of `settings.litterSize` random genotypes drawn
	/// from `seed`, using the family's settings. The same seed and settings
	/// give the same genotypes as the random grid and `generate_genotypes`.
	@discardableResult
	public mutating func addRandomLitter(signatures: [String: NodeSignature], seed: UInt64, created: Date = Date()) -> Litter {
		let generator = RandomExpressionGenerator(signatures: signatures, configuration: settings.generatorConfiguration)
		var rng = SeededRandomNumberGenerator(seed: seed)
		let expressions = (0..<settings.litterSize).map { _ in generator.generate(using: &rng).description }
		return addLitter(kind: .random, parents: [], seed: seed, source: nil, settings: settings, created: created,
						 children: expressions.map { ($0, []) })
	}

	/// Adds a root litter of genotypes from elsewhere (the library, a file,
	/// pasted text). `source` says where, for display.
	@discardableResult
	public mutating func addSeedLitter(expressions: [String], source: String?, created: Date = Date()) throws -> Litter {
		guard !expressions.isEmpty else { throw FamilyError("A seed litter needs at least one genotype.") }
		return addLitter(kind: .seed, parents: [], seed: nil, source: source, settings: nil, created: created,
						 children: expressions.map { ($0, []) })
	}

	/// Breeds a litter of `settings.litterSize` mutated children from
	/// `parentID`, drawn from `seed`. The same parent, seed and settings
	/// give the same children as `mutate_genotype`.
	@discardableResult
	public mutating func breed(_ parentID: String, signatures: [String: NodeSignature], seed: UInt64, created: Date = Date()) throws -> Litter {
		guard let parentMember = member(id: parentID) else {
			throw FamilyError("There's no member \(parentID) in this family.")
		}
		let parent: GeneratedExpression
		do {
			parent = try GeneratedExpression(parsing: parentMember.expression)
		} catch {
			throw FamilyError("Couldn't read \(parentID): \(error)")
		}
		let generator = RandomExpressionGenerator(signatures: signatures, configuration: settings.generatorConfiguration)
		let mutator = ExpressionMutator(generator: generator, configuration: settings.mutatorConfiguration)
		let unknown = mutator.unknownNodes(in: parent)
		guard unknown.isEmpty else {
			throw FamilyError("\(parentID) uses nodes that aren't loaded: \(unknown.sorted().joined(separator: ", ")).")
		}
		var rng = SeededRandomNumberGenerator(seed: seed)
		var children: [(String, [MutationRecord])] = []
		for _ in 0..<settings.litterSize {
			guard let child = mutator.mutate(parent, using: &rng) else {
				throw FamilyError("No mutation of \(parentID) changed it within the size limit of \(mutator.maxNodes(forParent: parent)) nodes.")
			}
			children.append((child.expression.description, child.mutations.map(MutationRecord.init)))
		}
		return addLitter(kind: .mutation, parents: [parentID], seed: seed, source: nil, settings: settings, created: created,
						 children: children)
	}

	private mutating func addLitter(kind: Litter.Kind, parents: [String], seed: UInt64?, source: String?, settings: Settings?,
									created: Date, children: [(expression: String, mutations: [MutationRecord])]) -> Litter {
		let litter = Litter(id: takeID(prefix: "L"), kind: kind, parents: parents, seed: seed, source: source,
							settings: settings, created: created)
		litters.append(litter)
		for (index, child) in children.enumerated() {
			members.append(Member(id: takeID(prefix: "g"), litter: litter.id, index: index,
								  expression: child.expression, mutations: child.mutations))
		}
		return litter
	}

	private mutating func takeID(prefix: String) -> String {
		defer { nextID += 1 }
		return "\(prefix)\(nextID)"
	}

	// MARK: - Changing members

	/// Removes `memberIDs` for good. A member with descendants can only go
	/// with its whole branch, so unless `includingDescendants` is set that
	/// throws. Litters left with no members go too. Returns every member
	/// removed.
	@discardableResult
	public mutating func reject(_ memberIDs: Set<String>, includingDescendants: Bool) throws -> Set<String> {
		let unknown = memberIDs.filter { member(id: $0) == nil }
		guard unknown.isEmpty else {
			throw FamilyError("There's no member \(unknown.sorted().joined(separator: ", ")) in this family.")
		}
		let descendants = descendants(of: memberIDs)
		if !descendants.isEmpty && !includingDescendants {
			throw FamilyError("Rejecting that would leave \(descendants.count) descendant(s) without a parent.")
		}
		let removed = memberIDs.union(descendants)
		members.removeAll { removed.contains($0.id) }
		let remainingLitters = Set(members.map(\.litter))
		litters.removeAll { !remainingLitters.contains($0.id) }
		return removed
	}

	/// Changes a member's name, star or collapsed state.
	public mutating func update(_ memberID: String, _ change: (inout Member) -> Void) {
		guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
		change(&members[index])
	}

	// MARK: - family.json

	private struct File: Codable {
		var format: Int
		var created: Date
		/// `nextId`, not `nextID`, so it matches `next_id` in the file.
		var nextId: Int
		var settings: Settings
		var litters: [Litter]
		var members: [Member]
	}

	public init(json data: Data) throws {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		decoder.dateDecodingStrategy = .iso8601
		let format: Int
		do {
			struct Header: Decodable { var format: Int }
			format = try decoder.decode(Header.self, from: data).format
		} catch {
			throw FamilyError("This isn't a family file: \(error.localizedDescription)")
		}
		guard format <= Self.currentFormat else {
			throw FamilyError("This family was saved by a newer version of Evolv.io (format \(format)).")
		}
		let file = try decoder.decode(File.self, from: data)
		created = file.created
		nextID = file.nextId
		settings = file.settings
		litters = file.litters
		members = file.members
		try validate()
	}

	/// Sorted keys and indented, so it diffs well and reads by hand.
	public func json() throws -> Data {
		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .convertToSnakeCase
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		return try encoder.encode(File(format: Self.currentFormat, created: created, nextId: nextID,
									   settings: settings, litters: litters, members: members))
	}

	/// Checks what the rest of the model relies on: unique ids, every
	/// member in a litter that exists, and every litter's parents made
	/// before it.
	private func validate() throws {
		var memberIDs = Set<String>()
		for member in members where !memberIDs.insert(member.id).inserted {
			throw FamilyError("Member id \(member.id) is used twice.")
		}
		var litterIDs = Set<String>()
		var seenMembers = Set<String>()
		for litter in litters {
			guard litterIDs.insert(litter.id).inserted else {
				throw FamilyError("Litter id \(litter.id) is used twice.")
			}
			for parent in litter.parents where !seenMembers.contains(parent) {
				throw FamilyError("Litter \(litter.id)'s parent \(parent) is missing or comes after it.")
			}
			seenMembers.formUnion(members.filter { $0.litter == litter.id }.map(\.id))
		}
		for member in members where !litterIDs.contains(member.litter) {
			throw FamilyError("Member \(member.id)'s litter \(member.litter) is missing.")
		}
	}
}
