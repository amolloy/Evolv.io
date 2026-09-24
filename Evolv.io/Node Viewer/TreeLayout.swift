//
//  TreeLayout.swift
//  Evolv.io
//

import CoreGraphics
import ExpressionTree

/// One occurrence of a node, positioned for the top-down diagram. `id` is the
/// node's own `ObjectIdentifier` -- unique per occurrence, since the parser
/// builds a genuine tree (no shared instances).
struct LaidOutNode: Identifiable {
	let id: ObjectIdentifier
	let node: any Node
	let depth: Int
	var center: CGPoint
	var parentCenter: CGPoint?
}

/// Positions every node in `rootNode`'s tree into fixed-height tiers, root at
/// the top, using the Reingold-Tilford tidy-tree algorithm as refined by
/// Walker (1990) and given a linear-time implementation by Buchheim, Junger
/// and Leipert ("Improving Walker's Algorithm to Run in Linear Time", 2002).
/// Unlike a bounding-box layout (this type's previous implementation), this
/// lets non-adjacent subtrees interleave horizontally wherever their contours
/// don't actually collide, so a lone leaf sibling can sit close to a node
/// with a much wider (but deeper) subtree instead of being pushed out past
/// that subtree's full reserved width. The algorithm assumes every node is
/// the same fixed size, which matches this app's tiles exactly.
struct TreeLayout {
	static let tileSize = CGSize(width: 72, height: 104)
	static let tierHeight: CGFloat = 140
	static let siblingGap: CGFloat = 16

	let nodes: [LaidOutNode]
	let contentSize: CGSize

	init(rootNode: any Node) {
		let root = TreeLayout.buildWalkerTree(rootNode, depth: 0, indexAmongSiblings: 0, parent: nil)
		let distance = TreeLayout.tileSize.width + TreeLayout.siblingGap

		TreeLayout.firstWalk(root, distance: distance)
		var minX = root.x
		TreeLayout.secondWalk(root, modSum: 0, minX: &minX)
		if minX < 0 {
			TreeLayout.shiftAll(root, by: -minX)
			minX = 0
		}

		// `x` is each node's center in an algorithm-relative coordinate space
		// where the leftmost node's center can land at 0; offset by half a
		// tile so no tile's left edge goes negative.
		let xOffset = TreeLayout.tileSize.width / 2

		var laidOut: [LaidOutNode] = []
		var maxX: CGFloat = 0
		var maxDepth = 0

		func collect(_ walker: WalkerNode, parentCenter: CGPoint?) {
			let center = CGPoint(x: walker.x + xOffset,
								  y: CGFloat(walker.depth) * TreeLayout.tierHeight + TreeLayout.tileSize.height / 2)
			laidOut.append(LaidOutNode(id: walker.node.id, node: walker.node, depth: walker.depth, center: center, parentCenter: parentCenter))
			maxX = max(maxX, center.x)
			maxDepth = max(maxDepth, walker.depth)
			for child in walker.children {
				collect(child, parentCenter: center)
			}
		}
		collect(root, parentCenter: nil)

		self.nodes = laidOut
		self.contentSize = CGSize(width: maxX + xOffset, height: CGFloat(maxDepth + 1) * TreeLayout.tierHeight)
	}

	// MARK: - Buchheim/Junger/Leipert tidy-tree algorithm

	/// Working state for one node during layout. A plain class (not
	/// `LaidOutNode`) because the algorithm mutates nodes via `thread` and
	/// `ancestor` pointers that can reach across sibling subtrees -- exactly
	/// the links that make this run in O(n) instead of the O(n^2) of the
	/// original Reingold-Tilford/Walker formulation.
	private final class WalkerNode {
		let node: any Node
		let depth: Int
		let indexAmongSiblings: Int
		weak var parent: WalkerNode?
		var children: [WalkerNode] = []

		/// Preliminary, then (after `secondWalk`) final, x-coordinate.
		var x: CGFloat = 0
		/// Accumulated shift applied to this node's descendants.
		var mod: CGFloat = 0
		/// Bookkeeping for `executeShifts`, spreading a shift evenly across
		/// intermediate siblings.
		var shift: CGFloat = 0
		var change: CGFloat = 0
		/// Path-compression pointer used by `apportion` to find which
		/// ancestor a contour-conflict shift should actually be applied to.
		weak var ancestor: WalkerNode?
		/// Contour thread: when a subtree runs out of real children before
		/// the subtree it's being compared against does, this stitches its
		/// contour onto the other subtree's so future comparisons can
		/// continue in O(1) rather than re-walking from the top.
		weak var thread: WalkerNode?

		init(node: any Node, depth: Int, indexAmongSiblings: Int, parent: WalkerNode?) {
			self.node = node
			self.depth = depth
			self.indexAmongSiblings = indexAmongSiblings
			self.parent = parent
		}

		var leftContour: WalkerNode? { thread ?? children.first }
		var rightContour: WalkerNode? { thread ?? children.last }

		var leftSibling: WalkerNode? {
			guard let parent, indexAmongSiblings > 0 else { return nil }
			return parent.children[indexAmongSiblings - 1]
		}

		/// The parent's first child, or `nil` if this node already is that
		/// first child.
		var leftmostSibling: WalkerNode? {
			guard let parent, indexAmongSiblings > 0 else { return nil }
			return parent.children.first
		}
	}

	private static func buildWalkerTree(_ node: any Node, depth: Int, indexAmongSiblings: Int, parent: WalkerNode?) -> WalkerNode {
		let walker = WalkerNode(node: node, depth: depth, indexAmongSiblings: indexAmongSiblings, parent: parent)
		walker.ancestor = walker
		walker.children = node.children.enumerated().map { index, child in
			buildWalkerTree(child, depth: depth + 1, indexAmongSiblings: index, parent: walker)
		}
		return walker
	}

	/// Post-order: computes each node's preliminary `x` and `mod`, resolving
	/// conflicts between already-placed subtrees via `apportion`.
	private static func firstWalk(_ v: WalkerNode, distance: CGFloat) {
		guard !v.children.isEmpty else {
			v.x = v.leftSibling.map { $0.x + distance } ?? 0
			return
		}

		var defaultAncestor = v.children[0]
		for child in v.children {
			firstWalk(child, distance: distance)
			defaultAncestor = apportion(child, defaultAncestor: defaultAncestor, distance: distance)
		}
		executeShifts(v)

		let midpoint = (v.children.first!.x + v.children.last!.x) / 2

		if let leftSibling = v.leftSibling {
			v.x = leftSibling.x + distance
			v.mod = v.x - midpoint
		} else {
			v.x = midpoint
		}
	}

	/// Walks the inside contours of `v`'s subtree and its left sibling's
	/// subtree in lockstep; wherever they'd collide, shifts the intervening
	/// subtree(s) right by just enough to clear by `distance`.
	private static func apportion(_ v: WalkerNode, defaultAncestor: WalkerNode, distance: CGFloat) -> WalkerNode {
		guard let w = v.leftSibling, let initialVol = v.leftmostSibling else {
			return defaultAncestor
		}

		var vor = v
		var vir = v
		var vil = w
		var vol = initialVol

		var sir = v.mod
		var sor = v.mod
		var sil = vil.mod
		var sol = vol.mod

		while let nextVil = vil.rightContour, let nextVir = vir.leftContour {
			vil = nextVil
			vir = nextVir
			vol = vol.leftContour ?? vol
			vor = vor.rightContour ?? vor
			vor.ancestor = v

			let shift = (vil.x + sil) - (vir.x + sir) + distance
			if shift > 0 {
				moveSubtree(ancestorOrDefault(vil, v: v, defaultAncestor: defaultAncestor), target: v, shift: shift)
				sir += shift
				sor += shift
			}

			sil += vil.mod
			sir += vir.mod
			sol += vol.mod
			sor += vor.mod
		}

		var result = defaultAncestor
		if vil.rightContour != nil && vor.rightContour == nil {
			vor.thread = vil.rightContour
			vor.mod += sil - sor
		} else {
			if vir.leftContour != nil && vol.leftContour == nil {
				vol.thread = vir.leftContour
				vol.mod += sir - sol
			}
			result = v
		}
		return result
	}

	private static func moveSubtree(_ wl: WalkerNode, target wr: WalkerNode, shift: CGFloat) {
		let subtrees = CGFloat(wr.indexAmongSiblings - wl.indexAmongSiblings)
		wr.change -= shift / subtrees
		wr.shift += shift
		wl.change += shift / subtrees
		wr.x += shift
		wr.mod += shift
	}

	private static func ancestorOrDefault(_ vil: WalkerNode, v: WalkerNode, defaultAncestor: WalkerNode) -> WalkerNode {
		if let ancestor = vil.ancestor, let parent = v.parent, parent.children.contains(where: { $0 === ancestor }) {
			return ancestor
		}
		return defaultAncestor
	}

	/// Spreads a subtree's accumulated `shift` evenly across the siblings
	/// between it and the sibling that triggered it, so intermediate
	/// siblings' spacing changes smoothly rather than jumping.
	private static func executeShifts(_ v: WalkerNode) {
		var shift: CGFloat = 0
		var change: CGFloat = 0
		for child in v.children.reversed() {
			child.x += shift
			child.mod += shift
			change += child.change
			shift += child.shift + change
		}
	}

	/// Pre-order: turns each node's preliminary `x` (relative to its parent)
	/// into an absolute coordinate by accumulating ancestors' `mod` values.
	private static func secondWalk(_ v: WalkerNode, modSum: CGFloat, minX: inout CGFloat) {
		v.x += modSum
		minX = min(minX, v.x)
		for child in v.children {
			secondWalk(child, modSum: modSum + v.mod, minX: &minX)
		}
	}

	private static func shiftAll(_ v: WalkerNode, by amount: CGFloat) {
		v.x += amount
		for child in v.children {
			shiftAll(child, by: amount)
		}
	}
}
