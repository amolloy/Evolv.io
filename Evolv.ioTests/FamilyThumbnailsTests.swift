//
//  FamilyThumbnailsTests.swift
//  Evolv.ioTests
//
//  The lineage view's thumbnail cache, in the app's own sandbox.
//

import Testing
import Foundation
import CoreGraphics
@testable import Evolv_io

@MainActor
struct FamilyThumbnailsTests {
	@Test func aRenderedThumbnailComesBackFromDisk() async throws {
		// A constant no other run has used, so this render is a miss.
		let expression = "(+ x \(Double.random(in: 0..<1)))"
		let thumbnails = FamilyThumbnails.shared
		#expect(await thumbnails.cachedThumbnail(for: expression) == nil)

		let start = Date()
		guard case .image(let rendered) = await thumbnails.thumbnail(for: expression) else {
			Issue.record("didn't render")
			return
		}
		let renderTime = Date().timeIntervalSince(start)

		// The PNG is written in the background.
		var fromDisk: CGImage?
		for _ in 0..<50 {
			thumbnails.dropMemoryCache()
			let readStart = Date()
			fromDisk = await thumbnails.cachedThumbnail(for: expression)
			if fromDisk != nil {
				print("Family thumbnail: render \(renderTime)s, disk read \(Date().timeIntervalSince(readStart))s")
				break
			}
			try await Task.sleep(for: .milliseconds(100))
		}
		let image = try #require(fromDisk)
		#expect(image.width == rendered.width && image.height == rendered.height)
	}
}
