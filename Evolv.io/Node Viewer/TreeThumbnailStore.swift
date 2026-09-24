//
//  TreeThumbnailStore.swift
//  Evolv.io
//

import CoreGraphics
import ExpressionTree
import Observation

/// Eagerly renders a preview thumbnail for every node in a tree diagram,
/// deduped by `node.toString()` so structurally identical subtrees (common in
/// these expression trees) share one render. Each `MetalRenderContext`
/// pipeline miss is a full runtime MSL compile (tens of ms), so the bulk
/// render is capped at a handful of concurrent nodes rather than firing one
/// task per node, and results publish incrementally so tiles fill in as they
/// land instead of all at once at the end.
@MainActor
@Observable
final class TreeThumbnailStore {
	private static let maxConcurrentRenders = 6

	private(set) var images: [String: CGImage] = [:]

	func renderAll(nodes: [LaidOutNode], evaluator: Evaluator) async {
		var seen = Set<String>()
		var pending: [(key: String, node: any Node)] = []
		for laidOut in nodes {
			let key = laidOut.node.toString()
			guard images[key] == nil, seen.insert(key).inserted else { continue }
			pending.append((key: key, node: laidOut.node))
		}
		guard !pending.isEmpty else { return }

		var iterator = pending.makeIterator()

		await withTaskGroup(of: (String, CGImage?).self) { group in
			func addNext() -> Bool {
				guard let item = iterator.next() else { return false }
				group.addTask {
					// NodeRenderer is @MainActor; the actual GPU work (and
					// the expensive pipeline compile) happens off-actor
					// inside `render()`'s own `Task.detached`, so this stays
					// cheap even though it's dispatched from here.
					let renderer = await NodeRenderer(node: item.node, evaluator: evaluator)
					await renderer.render()
					return (item.key, await renderer.cgImage())
				}
				return true
			}

			for _ in 0..<TreeThumbnailStore.maxConcurrentRenders {
				if !addNext() { break }
			}

			while let (key, image) = await group.next() {
				if Task.isCancelled { break }
				if let image {
					images[key] = image
				}
				_ = addNext()
			}
		}
	}
}
