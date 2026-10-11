//
//  FamilyThumbnails.swift
//  Evolv.io
//
//  Thumbnails for the lineage view. A family can have hundreds of members
//  and each distinct tree costs a Metal pipeline compile, so renders are
//  cached in memory and as PNGs in the app's Caches folder, keyed by the
//  expression, supersampling and a fingerprint of every node definition.
//  Every thumbnail renders at one size, scaled down for chips and small
//  cells, so changing a cell's size never re-renders it. The same genotype in two families shares an image,
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
	/// Pixels square: 2x for the largest cell size.
	static let pixelSize = 256

	private let memory = NSCache<NSString, CGImage>()
	private let directory: URL?
	private var nodeFingerprint: String
	private var running = 0
	private var waiting: [CheckedContinuation<Void, Never>] = []

	private init() {
		// About 1,500 thumbnails.
		memory.totalCostLimit = 300 << 20
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

	/// The thumbnail for `expression`: from memory, from disk, or rendered
	/// (waiting for a free render slot).
	func thumbnail(for expression: String) async -> Outcome {
		if let image = await cachedThumbnail(for: expression) {
			return .image(image)
		}
		let key = cacheKey(expression: expression)
		let size = Self.pixelSize
		let fileURL = directory?.appendingPathComponent(key + ".png")
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
			remember(image, key: key)
			if let fileURL {
				Task.detached(priority: .utility) { Self.writePNG(image, to: fileURL) }
			}
		}
		return .image(image)
	}

	/// The thumbnail if it's in memory, right away, so a cell that's
	/// recreated (scrolled back into view) never shows a spinner.
	func memoryThumbnail(for expression: String) -> CGImage? {
		memory.object(forKey: cacheKey(expression: expression) as NSString)
	}

	/// The thumbnail from memory or disk, without rendering.
	func cachedThumbnail(for expression: String) async -> CGImage? {
		let key = cacheKey(expression: expression)
		if let image = memory.object(forKey: key as NSString) {
			return image
		}
		guard let fileURL = directory?.appendingPathComponent(key + ".png"),
			  let image = await Self.readPNG(fileURL) else {
			return nil
		}
		remember(image, key: key)
		return image
	}

	/// For tests: forget the in-memory copies, so the next lookup reads disk.
	func dropMemoryCache() {
		memory.removeAllObjects()
	}

	private func remember(_ image: CGImage, key: String) {
		memory.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
	}

	private func cacheKey(expression: String) -> String {
		let supersample = UserDefaults.standard.isSupersamplingEnabled ? 4 : 1
		let text = "\(nodeFingerprint)\n\(Self.pixelSize)\n\(supersample)\n\(expression)"
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
		if !CGImageDestinationFinalize(destination) {
			print("Couldn't cache a family thumbnail at \(url.path)")
		}
	}
}
