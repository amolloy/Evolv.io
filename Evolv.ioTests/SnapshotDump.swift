//
//  SnapshotDump.swift
//  Evolv.ioTests
//
//  Renders every sample expression in ContentView to a PNG so you can diff
//  two runs (e.g. before/after a node change) to see exactly what moved.
//  Not a pass/fail test -- the run's output directory is printed to the
//  test log; copy it out and compare against a previous run's copy.
//

import Testing
import Foundation
import ExpressionTree
@testable import Evolv_io

struct SnapshotDump {
	static let testSnapshotKeys = [
		"Figure 9",
		"Figure 10",
	]

	@Test @MainActor func dumpSampleExpressions() async throws {
		let outputDirectory = Self.snapshotsDirectory()
		try? FileManager.default.removeItem(at: outputDirectory)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

		let parser = Parser()
		let size = CGSize(width: 400, height: 400)
		var written = 0

		for name in SnapshotDump.testSnapshotKeys {
			let expression = ContentView.sampleExpressions[name]!
			let node: any Node
			do {
				node = try parser.parse(expression)
			} catch {
				print("Skipping \"\(name)\" -- failed to parse: \(error)")
				continue
			}

			let renderer = NodeRenderer(node: node, evaluator: Evaluator(size: size))
			await renderer.render()

			guard let image = renderer.cgImage(), let data = image.pngData() else {
				print("Skipping \"\(name)\" -- failed to render")
				continue
			}

			let fileURL = outputDirectory.appendingPathComponent(Self.sanitize(name)).appendingPathExtension("png")
			try data.write(to: fileURL)
			written += 1
		}

		print("Wrote \(written)/\(ContentView.sampleExpressions.count) snapshots to \(outputDirectory.path)")
	}

	/// The app is sandboxed with no filesystem write entitlement beyond its
	/// own container, so this can't land directly in the repo -- it goes in
	/// the container's temporary directory instead. The path is printed at
	/// the end of the run; copy it out (or `open` it) to compare against a
	/// previous run.
	private static func snapshotsDirectory() -> URL {
		FileManager.default.temporaryDirectory.appendingPathComponent("EvolvIoSnapshots")
	}

	private static func sanitize(_ name: String) -> String {
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
		return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
	}
}
