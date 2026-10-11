//
//  ExportCaption.swift
//  Evolv.io
//
//  The expression as a caption on exported images (Export Image and Export
//  Path): white monospaced text on a dark band, either over the bottom of
//  the image or in a band added below it. The text scales with the image
//  (about 1.8% of its width, at least 11 pixels) and wraps; a caption too
//  long for its band ends in "…" (the full expression is still in the
//  file's metadata when that's on). Images under `minimumSize` pixels
//  aren't captioned: the text would cover them.
//

import Foundation
import CoreGraphics
import CoreText

enum ExportCaption: String, CaseIterable, Identifiable {
	case off
	/// Over the bottom of the image, at most `maxOverlayFraction` of it.
	case overlay
	/// In a band added below the image, which makes it taller.
	case below

	var id: String { rawValue }

	var label: String {
		switch self {
			case .off: "Off"
			case .overlay: "Over the image"
			case .below: "Below the image"
		}
	}

	static let minimumSize = 256
	private static let maxOverlayFraction: CGFloat = 0.4
	/// A band below is at most as tall as the image.
	private static let maxBelowFraction: CGFloat = 1

	static func fontSize(forWidth width: Int) -> CGFloat {
		max(11, (CGFloat(width) * 0.018).rounded())
	}

	private static func padding(forWidth width: Int) -> CGFloat {
		(fontSize(forWidth: width) * 0.6).rounded()
	}

	/// The band height `text` needs at `width`, padding included, before
	/// any cap. Export Path takes the largest over the whole path, so its
	/// images all come out the same size.
	static func bandHeight(for text: String, width: Int) -> Int {
		let padding = padding(forWidth: width)
		let framesetter = CTFramesetterCreateWithAttributedString(attributed(text, width: width))
		let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
			framesetter, CFRange(location: 0, length: 0), nil,
			CGSize(width: CGFloat(width) - 2 * padding, height: .greatestFiniteMagnitude), nil)
		return Int((fitted.height + 2 * padding).rounded(.up))
	}

	/// `image` with `text` captioned this way. `bandHeight` is the band to
	/// use (from `bandHeight(for:width:)`, maybe a larger one shared by
	/// several images); it's capped to the image's size, and text that
	/// doesn't fit ends in "…".
	func apply(to image: CGImage, text: String, bandHeight: Int) -> CGImage? {
		guard self != .off, image.width >= Self.minimumSize else { return image }
		let width = image.width
		let imageHeight = image.height
		let cap = CGFloat(imageHeight) * (self == .overlay ? Self.maxOverlayFraction : Self.maxBelowFraction)
		let band = min(CGFloat(bandHeight), cap.rounded(.down))
		let height = self == .below ? imageHeight + Int(band) : imageHeight

		guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpace(name: CGColorSpace.sRGB)!,
									  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
		// Core Graphics' origin is the bottom left: the image sits on top of
		// a band below, or fills the context for an overlay.
		let imageY = self == .below ? band : 0
		context.draw(image, in: CGRect(x: 0, y: imageY, width: CGFloat(width), height: CGFloat(imageHeight)))
		context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: self == .overlay ? 0.65 : 1))
		context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: band))

		let padding = Self.padding(forWidth: width)
		let textRect = CGRect(x: padding, y: padding, width: CGFloat(width) - 2 * padding, height: band - 2 * padding)
		guard textRect.width > 0, textRect.height > 0 else { return context.makeImage() }
		let frame = Self.frame(for: text, width: width, in: textRect)
		CTFrameDraw(frame, context)
		return context.makeImage()
	}

	/// The laid-out text, cut and ended with "…" if it doesn't all fit.
	private static func frame(for text: String, width: Int, in rect: CGRect) -> CTFrame {
		let path = CGPath(rect: rect, transform: nil)
		func layout(_ string: String) -> (CTFrame, Int) {
			let framesetter = CTFramesetterCreateWithAttributedString(attributed(string, width: width))
			let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
			return (frame, CTFrameGetVisibleStringRange(frame).length)
		}
		let full = layout(text)
		let length = (text as NSString).length
		guard full.1 < length else { return full.0 }
		// Shorten until the cut text and its ellipsis fit.
		var visible = full.1
		while visible > 0 {
			let cut = (text as NSString).substring(to: max(0, visible - 2)).trimmingCharacters(in: .whitespaces) + " …"
			let attempt = layout(cut)
			if attempt.1 >= (cut as NSString).length { return attempt.0 }
			visible -= 2
		}
		return layout("…").0
	}

	private static func attributed(_ text: String, width: Int) -> CFAttributedString {
		let font = CTFontCreateUIFontForLanguage(.userFixedPitch, fontSize(forWidth: width), nil)
			?? CTFontCreateWithName("Menlo" as CFString, fontSize(forWidth: width), nil)
		let attributes: [CFString: Any] = [
			kCTFontAttributeName: font,
			kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
		]
		return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
	}
}
