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

// Builds test trees via `Parser().parse(...)` Lisp text rather than
// constructing node classes directly -- "+"/"/"/"*"/"abs"/"x"/"y" are all
// DSL-defined now (see Evolv.io/Resources/BundledNodes/), so there's no
// Swift type to construct directly any more. This target is app-hosted
// (see SnapshotDump.swift, which already relies on the same thing), so
// `Parser()`'s `NodeRegistry.shared` resolves the real bundled files.
struct TreeLayoutTests {

	@Test func tiersMatchDepthInASmallTree() throws {
		let root = try Parser().parse("(/ X (abs Y))")
		let layout = TreeLayout(rootNode: root)

		let byDepth = Dictionary(grouping: layout.nodes, by: \.depth)
		#expect(byDepth[0]?.count == 1)
		#expect(byDepth[1]?.count == 2)
		#expect(byDepth[2]?.count == 1)

		#expect(byDepth[0]?.first?.node.toString().hasPrefix("(/ ") == true)
		#expect(byDepth[2]?.first?.node.toString() == "y")
	}

	@Test func parentIsCenteredOverItsChildren() throws {
		let root = try Parser().parse("(+ (+ x y) (/ x y))")
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
		let root = try Parser().parse("(+ (abs (+ x y)) y)")
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
		let root = try Parser().parse("(+ (+ (* x y) (/ x y)) (abs y))")
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

struct ImageExporterTests {

	@Test func listsPNGAndJPEGFirstAndLeavesOutTextureFormats() {
		#expect(Array(ImageExporter.formats.prefix(2)) == [.png, .jpeg])
		let identifiers = ImageExporter.formats.map(\.identifier)
		#expect(!identifiers.contains("org.khronos.ktx"))
		#expect(!identifiers.contains("com.apple.icns"))
	}

	@Test func rendersAtTheRequestedSizeAndStoresTheGenotype() async throws {
		// Long enough to rule out IPTC's 2000 byte caption limit.
		let expression = "(+ x y)" + String(repeating: " ", count: 3000)
		let genotype = RandomGenotype(text: expression, node: try Parser().parse(expression), name: "Test")
		let image = try await ImageExporter.render(node: genotype.node, size: 32, supersample: 2)
		#expect(image.width == 32 && image.height == 32)

		for format in ImageExporter.formats {
			let data = try ImageExporter.encode(image, as: format, quality: 0.8, genotype: genotype)
			#expect(!data.isEmpty, "\(format.identifier)")
			if ImageExporter.metadataFormats.contains(format) {
				let embedded = ImageExporter.embeddedGenotype(in: data)
				#expect(embedded?.expression == expression, "\(format.identifier)")
				#expect(embedded?.name == "Test", "\(format.identifier)")
			}
		}

		let bare = try ImageExporter.encode(image, as: .png, quality: 1, genotype: nil)
		#expect(ImageExporter.embeddedGenotype(in: bare) == nil)
	}
}
