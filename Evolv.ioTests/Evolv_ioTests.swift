//
//  Evolv_ioTests.swift
//  Evolv.ioTests
//
//  Created by Andy Molloy on 6/8/25.
//

import Testing
import ExpressionTree
@testable import Evolv_io

struct Evolv_ioTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

struct TreeLayoutTests {

	@Test func tiersMatchDepthInASmallTree() throws {
		let root = try Parser().parse("(/ X (abs Y))")
		let layout = TreeLayout(rootNode: root)

		let byDepth = Dictionary(grouping: layout.nodes, by: \.depth)
		#expect(byDepth[0]?.count == 1)
		#expect(byDepth[1]?.count == 2)
		#expect(byDepth[2]?.count == 1)

		#expect(byDepth[0]?.first?.node is Div)
		#expect(byDepth[2]?.first?.node is VariableY)
	}

	@Test func parentIsCenteredOverItsChildren() throws {
		let root = Add([Add([VariableX(), VariableY()]), Div([VariableX(), VariableY()])])
		let layout = TreeLayout(rootNode: root)

		let rootLaidOut = try #require(layout.nodes.first { $0.depth == 0 })
		let children = layout.nodes.filter { $0.depth == 1 }
		let minX = try #require(children.map(\.center.x).min())
		let maxX = try #require(children.map(\.center.x).max())

		#expect(abs(rootLaidOut.center.x - (minX + maxX) / 2) < 0.001)
	}

	@Test func loneLeafSiblingTucksInNearAWideDeeperSubtree() throws {
		// `wideDeeper` fans out two levels down (Abs -> Add -> two leaves)
		// but is only one node wide at its own depth; `loneLeaf` has no
		// depth of its own to actually conflict with that fan-out. A tidy
		// (contour-based) layout should let loneLeaf sit right next to
		// wideDeeper -- not pushed out past wideDeeper's full subtree width,
		// the way the old bounding-box layout would have.
		let wideDeeper = Abs([Add([VariableX(), VariableY()])])
		let loneLeaf = VariableY()
		let root = Add([wideDeeper, loneLeaf])
		let layout = TreeLayout(rootNode: root)

		let depth1 = layout.nodes.filter { $0.depth == 1 }.sorted { $0.center.x < $1.center.x }
		#expect(depth1.count == 2)

		let gap = depth1[1].center.x - depth1[0].center.x
		let minimumGap = TreeLayout.tileSize.width + TreeLayout.siblingGap

		#expect(abs(gap - minimumGap) < 0.001)
	}

	@Test func siblingsAtEveryDepthNeverOverlap() throws {
		// Deliberately unbalanced: the left branch is two levels deeper than
		// the right, which is exactly the shape that would expose an overlap
		// bug across different parents' bands.
		let deepLeft = Add([Mult([VariableX(), VariableY()]), Div([VariableX(), VariableY()])])
		let shallowRight = Abs([VariableY()])
		let root = Add([deepLeft, shallowRight])
		let layout = TreeLayout(rootNode: root)

		let byDepth = Dictionary(grouping: layout.nodes, by: \.depth)
		for (_, nodesAtDepth) in byDepth {
			let sortedByX = nodesAtDepth.sorted { $0.center.x < $1.center.x }
			for i in 1..<sortedByX.count {
				let previousRightEdge = sortedByX[i - 1].center.x + TreeLayout.tileSize.width / 2
				let currentLeftEdge = sortedByX[i].center.x - TreeLayout.tileSize.width / 2
				#expect(currentLeftEdge >= previousRightEdge - 0.001)
			}
		}
	}
}
