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
		#expect(family.ancestors(of: "g8") == ["g5", "g3", "g2"])
		#expect(family.ancestors(of: "g6") == ["g2"])
		#expect(family.ancestors(of: "g2").isEmpty)
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

	/// No two cells overlap, and no two litters' outlines do.
	private func expectNoOverlaps(_ layout: FamilyLayout, sourceLocation: SourceLocation = #_sourceLocation) {
		let cells = layout.cells.sorted { $0.key < $1.key }
		for i in cells.indices {
			for j in cells.indices where j > i {
				#expect(!cells[i].value.frame.intersects(cells[j].value.frame), "\(cells[i].key) overlaps \(cells[j].key)",
						sourceLocation: sourceLocation)
			}
		}
		let outlines = layout.litterOutlines.sorted { $0.key < $1.key }
		for i in outlines.indices {
			for j in outlines.indices where j > i {
				#expect(!outlines[i].value.intersects(outlines[j].value), "\(outlines[i].key) overlaps \(outlines[j].key)",
						sourceLocation: sourceLocation)
			}
		}
	}

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
		// Five chips (one row of three, one of two), then the parent, then
		// the rest right below it: its litter is in the next column, so it
		// doesn't push them down.
		let parentFrame = layout.cells[parent.id]!.frame
		let chipRows = 2 * (metrics.chipSize + metrics.chipSpacing) - metrics.chipSpacing
		#expect(layout.cells[siblings[4].id]!.frame.maxY + metrics.rowSpacing == parentFrame.minY)
		#expect(layout.cells[siblings[6].id]!.frame.minY == parentFrame.maxY + metrics.rowSpacing)
		#expect(layout.cells[siblings[0].id]!.frame.minY + chipRows + metrics.rowSpacing == parentFrame.minY)
		expectNoOverlaps(layout)
	}

	@Test func aLitterIsCentredOnItsParent() throws {
		var family = Family(created: created)
		let roots = family.addRandomLitter(signatures: signatures, seed: 1)
		let parent = family.members(ofLitter: roots.id)[5]
		let litter = try family.breed(parent.id, signatures: signatures, seed: 2)
		let layout = FamilyLayout(family: family, metrics: metrics)
		let parentFrame = layout.cells[parent.id]!.frame
		let litterFrame = layout.litterFrames[litter.id]!
		#expect(litterFrame.midY == parentFrame.midY)
		#expect(litterFrame.minX == metrics.cellSize + metrics.columnSpacing)
		// It reaches above the parent, so everything is shifted to keep the
		// topmost cell at 0.
		#expect(litterFrame.minY == 0)
		// The line runs straight across.
		let line = try #require(layout.connectors.first)
		#expect(line == FamilyLayout.Connector(parent: parent.id, litter: litter.id,
											   from: CGPoint(x: parentFrame.maxX, y: parentFrame.midY),
											   to: CGPoint(x: litterFrame.minX - metrics.litterPadding, y: parentFrame.midY),
											   isPrimary: true))
	}

	/// What the centring is for: always picking the last child used to
	/// step the whole chain down a litter's worth each generation.
	@Test func aChainOfLastChildrenStaysLevel() throws {
		var family = Family(created: created)
		var litter = family.addRandomLitter(signatures: signatures, seed: 1)
		for generation in 0..<6 {
			let last = family.members(ofLitter: litter.id).last!.id
			litter = try family.breed(last, signatures: signatures, seed: UInt64(10 + generation))
		}
		let layout = FamilyLayout(family: family, metrics: metrics)
		let fullLitter = 19 * metrics.cellSize + 18 * metrics.rowSpacing
		#expect(layout.size.height < 1.6 * fullLitter)
		#expect(layout.cells.values.map(\.frame.minX).max()! == 6 * (metrics.cellSize + metrics.columnSpacing))
		expectNoOverlaps(layout)
	}

	@Test func branchesPackWithoutOverlapping() throws {
		var family = Family(created: created)
		family.addRandomLitter(signatures: signatures, seed: 1)
		var rng = SeededRandomNumberGenerator(seed: 77)
		for step in 0..<14 {
			let parent = family.members.randomElement(using: &rng)!.id
			try family.breed(parent, signatures: signatures, seed: UInt64(100 + step))
			if step % 4 == 3 {
				let a = family.members.randomElement(using: &rng)!.id
				let b = family.members.randomElement(using: &rng)!.id
				if a != b { _ = try? family.mate(a, b, method: .graft, signatures: signatures, seed: UInt64(step)) }
			}
		}
		for focus in [nil, family.ancestors(of: family.members.last!.id).union([family.members.last!.id])] {
			let layout = FamilyLayout(family: family, metrics: metrics, focus: focus)
			#expect(layout.cells.count == family.members.count)
			#expect(layout.cells.values.map(\.frame.minY).min() == 0)
			expectNoOverlaps(layout)
		}
	}

	@Test func litterOutlinesSurroundOnlyTheirOwnMembers() throws {
		let family = try twoGenerations()
		let layout = FamilyLayout(family: family, metrics: metrics)
		let pad = metrics.litterPadding
		for litter in family.litters {
			let cells = family.members(ofLitter: litter.id).map { layout.cells[$0.id]!.frame }
			let outline = try #require(layout.litterOutlines[litter.id])
			#expect(outline.minX == cells.map(\.minX).min()! - pad && outline.maxX == cells.map(\.maxX).max()! + pad)
			#expect(outline.minY == cells.map(\.minY).min()! - pad && outline.maxY == cells.map(\.maxY).max()! + pad)
		}
	}

	@Test func showPathShrinksEverythingOffThePath() throws {
		var family = try twoGenerations()
		let root = family.members[0].id
		let children = family.members(ofLitter: family.litters[1].id)
		try family.breed(children[3].id, signatures: signatures, seed: 3)
		try family.breed(children[7].id, signatures: signatures, seed: 4)
		let grandchild = family.members(ofLitter: family.litters[2].id)[5].id
		let path = family.ancestors(of: grandchild).union([grandchild])
		#expect(path == [root, children[3].id, grandchild])

		let layout = FamilyLayout(family: family, metrics: metrics, focus: path)
		#expect(layout.cells.count == family.members.count)
		for (id, cell) in layout.cells {
			#expect(cell.isChip == !path.contains(id), "\(id)")
		}
		// Off the path, a parent is a chip of its own with its litter
		// centred on it.
		let offPath = layout.cells[children[7].id]!.frame
		let offPathLitter = layout.litterFrames[family.litters[3].id]!
		#expect(offPathLitter.midY == offPath.midY)
		#expect(layout.connectors.contains { $0.parent == children[7].id && $0.from == CGPoint(x: offPath.maxX, y: offPath.midY) })
		expectNoOverlaps(layout)
	}

	@Test func anExpandedLitterKeepsEverySiblingFullSize() throws {
		var family = try twoGenerations()
		let roots = family.litters[0].id
		family.updateLitter(roots) { $0.expanded = true }
		let layout = FamilyLayout(family: family, metrics: metrics)
		#expect(family.members(ofLitter: roots).allSatisfy { layout.cells[$0.id]?.isChip == false })
		#expect(try Family(json: family.json()).litters[0].expanded)
		// Show Path still shrinks it.
		let focused = FamilyLayout(family: family, metrics: metrics, focus: [family.members[0].id])
		#expect(focused.cells[family.members[1].id]?.isChip == true)
	}

	@Test func verticalIsTheHorizontalLayoutTransposed() throws {
		var family = try twoGenerations()
		try family.breed(family.members(ofLitter: family.litters[1].id)[2].id, signatures: signatures, seed: 9)
		let across = FamilyLayout(family: family, metrics: metrics)
		let down = FamilyLayout(family: family, metrics: metrics, orientation: .vertical)
		#expect(down.orientation == .vertical && down.size == CGSize(width: across.size.height, height: across.size.width))
		for (id, cell) in across.cells {
			let flipped = try #require(down.cells[id])
			#expect(flipped.isChip == cell.isChip)
			#expect(flipped.frame == CGRect(x: cell.frame.minY, y: cell.frame.minX, width: cell.frame.height, height: cell.frame.width))
		}
		// Lines run from a parent's bottom edge to the top of its litter.
		let line = try #require(down.connectors.first)
		let parent = try #require(down.cells[line.parent]).frame
		#expect(line.from == CGPoint(x: parent.midX, y: parent.maxY))
		#expect(line.to.y == down.litterOutlines[line.litter]!.minY)
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
		#expect(layout.litterFrames["L7"]!.midY == layout.cells["g5"]!.frame.midY)
		let lines = layout.connectors.filter { $0.litter == "L7" }
		#expect(lines.map(\.parent) == ["g5", "g3"])
		#expect(lines.map(\.isPrimary) == [true, false])
		expectNoOverlaps(layout)
	}
}

struct MatingTests {
	private let mutator = ExpressionMutator(generator: RandomExpressionGenerator(signatures: signatures))

	/// Sims' 1991 §4.3 example: crossover can only make two new children.
	@Test func crossoverMakesSimsTwoNewChildren() throws {
		let a = try GeneratedExpression(parsing: "(* (abs x) (mod x y))")
		let b = try GeneratedExpression(parsing: "(* (/ y x) (* x -0.7))")
		var rng = SeededRandomNumberGenerator(seed: 1)
		let children = mutator.mate((a, b), method: .crossover, count: 19, using: &rng)
		#expect(Set(children.map(\.expression.description)) == ["(* (abs x) (* x -0.7))", "(* (/ y x) (mod x y))"])
		#expect(children.allSatisfy { $0.base == 0 && $0.grafts.allSatisfy { $0.kind == .crossover } })
	}

	@Test func crossoverNeedsTheSameRoot() throws {
		let a = try GeneratedExpression(parsing: "(abs x)")
		let b = try GeneratedExpression(parsing: "(cos x)")
		#expect(!mutator.canCrossOver(a, b))
		var rng = SeededRandomNumberGenerator(seed: 1)
		#expect(mutator.mate((a, b), method: .crossover, count: 19, using: &rng).isEmpty)
	}

	@Test func aGraftIsOneParentWithOneNodeOfTheOther() throws {
		let parents = try (GeneratedExpression(parsing: "(warped-color-noise x (abs y) 0.12 3)"),
						   GeneratedExpression(parsing: "(color-grad (bw-noise 0.2 2) 3.1 1.86 #(0.95 0.7 0.59) 1.35)"))
		var rng = SeededRandomNumberGenerator(seed: 7)
		let children = mutator.mate(parents, method: .graft, count: 19, using: &rng)
		#expect(children.count == 19)
		#expect(Set(children.map(\.expression)).count == 19)
		#expect(Set(children.map(\.base)) == [0, 1])
		for child in children {
			let (base, donor) = child.base == 0 ? parents : (parents.1, parents.0)
			let graft = try #require(child.grafts.first)
			#expect(child.grafts.count == 1 && graft.kind == .graft)
			#expect(child.expression != parents.0 && child.expression != parents.1)
			#expect(child.expression.replacing(at: graft.path, with: graft.before) == base)
			#expect(donor.subtrees().contains { $0.expression == graft.after })
			#expect(child.expression.isCallWithArguments)
		}
	}

	@Test func aMatingLitterRecordsBothParentsAndEachChildsBase() throws {
		var family = Family(created: created)
		try family.addSeedLitter(expressions: ["(warped-color-noise x (abs y) 0.12 3)", "(warped-color-noise (cos x) y 0.3 2)"],
								 source: nil, created: created)
		let (a, b) = (family.members[0].id, family.members[1].id)
		let litter = try family.mate(b, a, method: .graft, signatures: signatures, seed: 5, created: created)
		#expect(litter.kind == .mating && litter.method == "graft" && litter.parents == [b, a])
		let children = family.members(ofLitter: litter.id)
		#expect(!children.isEmpty && children.allSatisfy { $0.base == a || $0.base == b })
		#expect(family.generations()[children[0].id] == 1)
		#expect(try Family(json: family.json()) == family)

		var again = Family(created: created)
		try again.addSeedLitter(expressions: family.members(ofLitter: family.litters[0].id).map(\.expression), source: nil)
		let sameSeed = try again.mate(again.members[1].id, again.members[0].id, method: .graft, signatures: signatures, seed: 5)
		#expect(again.members(ofLitter: sameSeed.id).map(\.expression) == children.map(\.expression))

		let crossed = try family.mate(a, b, method: .crossover, signatures: signatures, seed: 1)
		// Four differences: 2^4 combinations, minus the two parents.
		#expect(family.members(ofLitter: crossed.id).count == 14)
		let other = try family.addSeedLitter(expressions: ["(abs x)"], source: nil)
		let differentRoot = family.members(ofLitter: other.id)[0].id
		#expect(throws: Family.FamilyError.self) {
			try family.mate(a, differentRoot, method: .crossover, signatures: signatures, seed: 1)
		}
	}
}
