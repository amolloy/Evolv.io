//
//  FamilyTests.swift
//  ExpressionTreeTests
//
//  The family model (Family), its family.json coding, and the lineage
//  view's layout (FamilyLayout).
//

import Testing
import Foundation
import CoreGraphics
@testable import ExpressionTree

private let repositoryRoot = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()

private let signatures = DSLLibrary.scanWithSignatures(
	roots: [repositoryRoot.appendingPathComponent("Evolv.io/Resources/BundledNodes")], reservedNames: []).signatures

private let created = Date(timeIntervalSince1970: 1_791_000_000)

/// A random root litter, then a litter bred from its first member.
private func twoGenerations() throws -> Family {
	var family = Family(created: created)
	let roots = family.addRandomLitter(signatures: signatures, seed: 1, created: created)
	try family.breed(family.members(ofLitter: roots.id)[0].id, signatures: signatures, seed: 2, created: created)
	return family
}

/// A family with a two-parent litter, written as JSON since there's no
/// mating yet.
private let matingJSON = """
{
  "format": 1, "created": "2026-10-11T13:20:00Z", "next_id": 20,
  "settings": { "litter_size": 2, "mutations_per_child": 1, "max_depth": 10,
                "excluded_functions": [], "excluded_root_functions": [], "excluded_variables": [] },
  "litters": [
    { "id": "L1", "kind": "seed", "parents": [], "created": "2026-10-11T13:20:00Z" },
    { "id": "L4", "kind": "mutation", "parents": ["g2"], "seed": "7", "created": "2026-10-11T13:20:00Z" },
    { "id": "L7", "kind": "mating", "parents": ["g5", "g3"], "created": "2026-10-11T13:20:00Z" }
  ],
  "members": [
    { "id": "g2", "litter": "L1", "index": 0, "expression": "(abs x)" },
    { "id": "g3", "litter": "L1", "index": 1, "expression": "(abs y)" },
    { "id": "g5", "litter": "L4", "index": 0, "expression": "(abs (cos x))" },
    { "id": "g6", "litter": "L4", "index": 1, "expression": "(cos x)" },
    { "id": "g8", "litter": "L7", "index": 0, "expression": "(abs (cos y))" }
  ]
}
"""

struct FamilyModelTests {
	@Test func randomLitterIsTheRandomGridsGenotypes() {
		var family = Family(created: created)
		let litter = family.addRandomLitter(signatures: signatures, seed: 42)
		let generator = RandomExpressionGenerator(signatures: signatures, configuration: family.settings.generatorConfiguration)
		var rng = SeededRandomNumberGenerator(seed: 42)
		let expected = (0..<19).map { _ in generator.generate(using: &rng).description }
		#expect(family.members(ofLitter: litter.id).map(\.expression) == expected)
		#expect(litter.kind == .random && litter.parents.isEmpty && litter.seed == 42)
	}

	@Test func breedingIsMutateGenotypeWithTheSameSeed() throws {
		let family = try twoGenerations()
		let parent = family.members[0]
		let litter = family.litters[1]
		let generator = RandomExpressionGenerator(signatures: signatures, configuration: family.settings.generatorConfiguration)
		let mutator = ExpressionMutator(generator: generator)
		var rng = SeededRandomNumberGenerator(seed: 2)
		let parentExpression = try GeneratedExpression(parsing: parent.expression)
		let expected = (0..<19).map { _ in mutator.mutate(parentExpression, using: &rng)! }
		let children = family.members(ofLitter: litter.id)
		#expect(children.map(\.expression) == expected.map(\.expression.description))
		#expect(children.map(\.mutations) == expected.map { $0.mutations.map(Family.MutationRecord.init) })
		#expect(litter.parents == [parent.id] && litter.kind == .mutation && litter.settings == family.settings)
	}

	@Test func generationsAreOneMoreThanTheOldestParent() throws {
		let family = try Family(json: Data(matingJSON.utf8))
		let generations = family.generations()
		#expect(generations == ["g2": 0, "g3": 0, "g5": 1, "g6": 1, "g8": 2])
		#expect(family.parents(of: "g8") == ["g5", "g3"])
		#expect(family.descendants(of: ["g3"]) == ["g8"])
		#expect(family.descendants(of: ["g2"]) == ["g5", "g6", "g8"])
	}

	@Test func rejectingAMemberWithChildrenNeedsTheWholeBranch() throws {
		var family = try twoGenerations()
		let parent = family.members[0].id
		#expect(throws: Family.FamilyError.self) {
			try family.reject([parent], includingDescendants: false)
		}
		let removed = try family.reject([parent], includingDescendants: true)
		#expect(removed.count == 20)
		#expect(family.litters.count == 1 && family.members.count == 18)
		#expect(family.member(id: parent) == nil)
	}

	@Test func rejectingTheLastOfALitterRemovesTheLitterAndIdsArentReused() throws {
		var family = Family(created: created)
		try family.addSeedLitter(expressions: ["(abs x)"], source: "pasted")
		let id = family.members[0].id
		try family.reject([id], includingDescendants: false)
		#expect(family.litters.isEmpty && family.members.isEmpty)
		try family.addSeedLitter(expressions: ["(abs y)"], source: nil)
		#expect(family.members[0].id != id)
	}
}

struct FamilyJSONTests {
	@Test func roundTrips() throws {
		var family = try twoGenerations()
		family.update(family.members[3].id) { $0.name = "Nice one"; $0.starred = true }
		family.update(family.members[0].id) { $0.collapsed = true }
		#expect(try Family(json: family.json()) == family)
	}

	@Test func seedsAboveTwoToThe53rdSurvive() throws {
		var family = Family(created: created)
		family.addRandomLitter(signatures: signatures, seed: UInt64.max - 1)
		let text = String(decoding: try family.json(), as: UTF8.self)
		#expect(text.contains("\"seed\" : \"18446744073709551614\""))
		#expect(try Family(json: family.json()).litters[0].seed == UInt64.max - 1)
	}

	@Test func leavesOutDefaults() throws {
		let text = String(decoding: try twoGenerations().json(), as: UTF8.self)
		#expect(!text.contains("starred") && !text.contains("collapsed") && !text.contains("\"name\""))
		#expect(text.contains("\"litter_size\" : 19"))
	}

	@Test func keepsKindsItDoesntKnow() throws {
		let json = matingJSON.replacingOccurrences(of: "\"mating\"", with: "\"graft\"")
		let family = try Family(json: Data(json.utf8))
		#expect(family.litter(id: "L7")?.kind.rawValue == "graft")
		#expect(String(decoding: try family.json(), as: UTF8.self).contains("\"graft\""))
	}

	@Test func refusesNewerFormatsAndBrokenFamilies() {
		let newer = matingJSON.replacingOccurrences(of: "\"format\": 1", with: "\"format\": 2")
		#expect(throws: Family.FamilyError.self) { try Family(json: Data(newer.utf8)) }
		let orphan = matingJSON.replacingOccurrences(of: "\"parents\": [\"g2\"]", with: "\"parents\": [\"g99\"]")
		#expect(throws: Family.FamilyError.self) { try Family(json: Data(orphan.utf8)) }
		let lostLitter = matingJSON.replacingOccurrences(of: "\"litter\": \"L7\"", with: "\"litter\": \"L9\"")
		#expect(throws: Family.FamilyError.self) { try Family(json: Data(lostLitter.utf8)) }
	}
}

struct FamilyLayoutTests {
	private let metrics = FamilyLayout.Metrics()

	@Test func aLitterNobodyHasBredFromIsFullSize() {
		var family = Family(created: created)
		family.addRandomLitter(signatures: signatures, seed: 1)
		let layout = FamilyLayout(family: family, metrics: metrics)
		#expect(layout.cells.count == 19)
		#expect(layout.cells.values.allSatisfy { !$0.isChip && $0.frame.minX == 0 })
		let tops = family.members.map { layout.cells[$0.id]!.frame.minY }
		#expect(tops == (0..<19).map { CGFloat($0) * (metrics.cellSize + metrics.rowSpacing) })
	}

	@Test func unexploredSiblingsShrinkToChipsInPlace() throws {
		var family = Family(created: created)
		let roots = family.addRandomLitter(signatures: signatures, seed: 1)
		let parent = family.members(ofLitter: roots.id)[5]
		try family.breed(parent.id, signatures: signatures, seed: 2)
		let layout = FamilyLayout(family: family, metrics: metrics)
		let siblings = family.members(ofLitter: roots.id)
		#expect(siblings.filter { layout.cells[$0.id]!.isChip }.count == 18)
		// Five chips (one row of three, one of two) before the parent.
		let parentFrame = layout.cells[parent.id]!.frame
		#expect(parentFrame.minY == 2 * (metrics.chipSize + metrics.chipSpacing) - metrics.chipSpacing + metrics.rowSpacing)
		#expect(layout.cells[siblings[4].id]!.frame.maxY < parentFrame.minY)
		#expect(layout.cells[siblings[6].id]!.frame.minY > parentFrame.maxY)
		// The new litter starts level with its parent, one column right.
		let litterFrame = layout.litterFrames[family.litters[1].id]!
		#expect(litterFrame.minY == parentFrame.minY)
		#expect(litterFrame.minX == metrics.cellSize + metrics.columnSpacing)
		// Siblings after the parent sit below its whole band.
		#expect(layout.cells[siblings[6].id]!.frame.minY > litterFrame.maxY)
		#expect(layout.connectors == [FamilyLayout.Connector(
			parent: parent.id, litter: family.litters[1].id,
			from: CGPoint(x: parentFrame.maxX, y: parentFrame.midY),
			to: CGPoint(x: litterFrame.minX, y: litterFrame.minY + metrics.cellSize / 2), isPrimary: true)])
	}

	@Test func breedingAgainMovesNothingAboveOrInsideTheParentsBranch() throws {
		var family = try twoGenerations()
		let parent = family.members[0].id
		let child = family.members(ofLitter: family.litters[1].id)[3].id
		try family.breed(child, signatures: signatures, seed: 3)
		let before = FamilyLayout(family: family, metrics: metrics)
		try family.breed(parent, signatures: signatures, seed: 4)
		let after = FamilyLayout(family: family, metrics: metrics)

		let parentTop = before.cells[parent]!.frame.minY
		let branch = family.descendants(of: [parent]).union([parent])
		for (id, cell) in before.cells where cell.frame.minY <= parentTop || branch.contains(id) {
			#expect(after.cells[id] == cell, "\(id) moved")
		}
		// The new litter goes under the parent's first one.
		#expect(after.litterFrames[family.litters[3].id]!.minY == before.litterFrames[family.litters[1].id]!.maxY + metrics.litterSpacing)
	}

	@Test func collapsedMembersHideTheirBranch() throws {
		var family = try twoGenerations()
		let parent = family.members[0].id
		family.update(parent) { $0.collapsed = true }
		let layout = FamilyLayout(family: family, metrics: metrics)
		#expect(layout.cells.count == 19)
		#expect(layout.hiddenDescendants == [parent: 19])
		#expect(layout.litterFrames.count == 1 && layout.connectors.isEmpty)
	}

	@Test func aMatingLitterIsInItsFirstParentsBranchWithADashedLineToTheSecond() throws {
		let family = try Family(json: Data(matingJSON.utf8))
		let layout = FamilyLayout(family: family, metrics: metrics)
		let column = metrics.cellSize + metrics.columnSpacing
		#expect(layout.litterFrames["L7"]!.minX == 2 * column)
		#expect(layout.litterFrames["L7"]!.minY == layout.cells["g5"]!.frame.minY)
		let lines = layout.connectors.filter { $0.litter == "L7" }
		#expect(lines.map(\.parent) == ["g5", "g3"])
		#expect(lines.map(\.isPrimary) == [true, false])
		// g3 sits below g2's whole branch.
		#expect(layout.cells["g3"]!.frame.minY > layout.litterFrames["L7"]!.maxY)
	}
}
