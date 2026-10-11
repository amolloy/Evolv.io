//
//  FamilyThumbnails.swift
//  Evolv.io
//
//  Thumbnails for the lineage view. A family can have hundreds of members
//  and each distinct tree costs a Metal pipeline compile, so renders are
//  cached in memory and as PNGs in the app's Caches folder, keyed by the
//  expression, the render size, supersampling and a fingerprint of every
//  node definition. The same genotype in two families shares an image,
//  nothing goes into the document or iCloud, and editing a node (then
//  Reload Custom Nodes) or relaunching after an edit gets fresh renders.
//  At most a few render at once.
//

import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import ExpressionTree

@MainActor
final class FamilyThumbnails {
	static let shared = FamilyThumbnails()

	enum Outcome {
		case image(CGImage)
		/// The expression doesn't parse with the nodes loaded now.
		case unreadable
	}

	private static let maxConcurrentRenders = 4

	private let memory = NSCache<NSString, CGImage>()
	private let directory: URL?
	private var nodeFingerprint: String
	private var running = 0
	private var waiting: [CheckedContinuation<Void, Never>] = []

	private init() {
		memory.countLimit = 2000
		directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
			.appendingPathComponent("FamilyThumbnails", isDirectory: true)
		if let directory {
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		nodeFingerprint = Self.fingerprintNodes()
		NotificationCenter.default.addObserver(forName: NodeRegistry.didReloadNotification, object: nil, queue: .main) { _ in
			MainActor.assumeIsolated {
				FamilyThumbnails.shared.nodesReloaded()
			}
		}
	}

	/// The thumbnail for `expression` at `size` pixels square: from memory,
	/// from disk, or rendered (waiting for a free render slot).
	func thumbnail(for expression: String, size: Int) async -> Outcome {
		let key = cacheKey(expression: expression, size: size)
		if let image = memory.object(forKey: key as NSString) {
			return .image(image)
		}
		let fileURL = directory?.appendingPathComponent(key + ".png")
		if let fileURL, let image = await Self.readPNG(fileURL) {
			memory.setObject(image, forKey: key as NSString)
			return .image(image)
		}
		guard let node = try? ContentView.parser.parse(expression) else {
			return .unreadable
		}

		await acquire()
		defer { release() }
		// Scrolled away while waiting: don't render it.
		if Task.isCancelled {
			return .unreadable
		}
		let renderer = NodeRenderer(node: node, evaluator: Evaluator(size: CGSize(width: size, height: size)))
		await renderer.render()
		guard let image = renderer.cgImage() else {
			return .unreadable
		}
		// A failed render (the GPU gave up, say) isn't cached, so it's
		// tried again next time.
		if renderer.renderError == nil {
			memory.setObject(image, forKey: key as NSString)
			if let fileURL {
				Task.detached(priority: .utility) { Self.writePNG(image, to: fileURL) }
			}
		}
		return .image(image)
	}

	private func cacheKey(expression: String, size: Int) -> String {
		let supersample = UserDefaults.standard.isSupersamplingEnabled ? 4 : 1
		let text = "\(nodeFingerprint)\n\(size)\n\(supersample)\n\(expression)"
		return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
	}

	private func nodesReloaded() {
		memory.removeAllObjects()
		nodeFingerprint = Self.fingerprintNodes()
	}

	/// A hash of every node definition file's path and contents.
	private static func fingerprintNodes() -> String {
		var hasher = SHA256()
		for root in DSLLibrary.productionRoots {
			guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
			let files = enumerator.compactMap { $0 as? URL }
				.filter { $0.pathExtension == "evolvnode" }
				.sorted { $0.path < $1.path }
			for file in files {
				hasher.update(data: Data(file.path.utf8))
				if let contents = try? Data(contentsOf: file) {
					hasher.update(data: contents)
				}
			}
		}
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	// MARK: - Render slots

	private func acquire() async {
		if running < Self.maxConcurrentRenders {
			running += 1
			return
		}
		await withCheckedContinuation { waiting.append($0) }
	}

	/// Hands the slot straight to the next waiter, if any.
	private func release() {
		if waiting.isEmpty {
			running -= 1
		} else {
			waiting.removeFirst().resume()
		}
	}

	// MARK: - PNG files

	nonisolated private static func readPNG(_ url: URL) async -> CGImage? {
		await Task.detached(priority: .userInitiated) {
			guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
			return CGImageSourceCreateImageAtIndex(source, 0, nil)
		}.value
	}

	nonisolated private static func writePNG(_ image: CGImage, to url: URL) {
		guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
		CGImageDestinationAddImage(destination, image, nil)
		CGImageDestinationFinalize(destination)
	}
}
