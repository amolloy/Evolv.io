//
//  ImageExport.swift
//  Evolv.io
//
//  Export Image…, from the context menu on grid thumbnails and full size
//  views: a dialog for the size, file format, supersampling and a few other
//  options, which renders the genotype again at that size and writes it out.
//  The dialog's settings are kept across launches, and its supersampling
//  setting only applies to exports, never to the app's own Supersampling
//  setting.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ExpressionTree
#if os(macOS)
import AppKit
#endif

/// Rendering and encoding for Export Image…, separate from the dialog.
enum ImageExporter {
	/// The image formats ImageIO can write, on macOS and iOS alike, less the
	/// GPU texture, icon and image sequence formats nobody exports a picture
	/// as. PNG and JPEG come first, then the rest by name.
	static let formats: [UTType] = {
		let excluded: Set<String> = [
			"com.apple.atx", "org.khronos.ktx", "org.khronos.ktx2", "org.khronos.astc",
			"com.microsoft.dds", "public.pvr", "public.heics", "com.microsoft.ico",
			"com.apple.icns", "public.pbm",
		]
		let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
		let types = identifiers
			.filter { !excluded.contains($0) }
			.compactMap { UTType($0) }
			.filter { $0.conforms(to: .image) && $0.preferredFilenameExtension != nil }
		let first: [UTType] = [.png, .jpeg].filter(types.contains)
		let rest = types
			.filter { !first.contains($0) }
			.sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
		return first + rest
	}()

	/// The formats with a quality setting.
	static let lossyFormats: Set<UTType> = Set(["public.jpeg", "public.heic", "public.avif", "public.jpeg-2000"].compactMap(UTType.init))

	static func name(of format: UTType) -> String {
		let ext = format.preferredFilenameExtension?.uppercased() ?? format.identifier
		guard let description = format.localizedDescription else { return ext }
		return "\(ext) (\(description))"
	}

	/// Renders `node` at `size` x `size` with `supersample` x `supersample`
	/// samples per pixel, off the main actor. Colors map the same as on screen.
	static func render(node: any Node, size: Int, supersample: Int) async throws -> CGImage {
		try await Task.detached(priority: .userInitiated) {
			let evaluator = Evaluator(size: CGSize(width: size, height: size))
			let data = try evaluator.render(node: node, scale: 1, supersample: supersample)
			guard let image = NodeRenderer.cgImage(data: data, width: size, height: size) else {
				throw ExportError(message: "Couldn't build an image from the render.")
			}
			return image
		}.value
	}

	/// The formats ImageIO writes XMP metadata into, so they can carry the
	/// genotype (see `encode`). The others (BMP, EXR, JPEG 2000, TGA) drop it,
	/// and PSD drops the `evolv:` namespace.
	static let metadataFormats: Set<UTType> = Set(["public.png", "public.jpeg", "com.compuserve.gif", "public.tiff",
												   "public.heic", "public.avif"].compactMap(UTType.init))

	/// The XMP namespace for the genotype stored in exported images.
	static let xmpNamespace = "https://evolv.io/ns/genotype/1.0/"
	static let xmpPrefix = "evolv"

	/// `image` as a `format` file. `quality` (0...1) applies to lossy
	/// formats. `genotype`, if given and `format` supports it, is stored in
	/// the file's XMP metadata: the expression as `evolv:expression` (and
	/// the name as `evolv:name`), and the expression again as the image's
	/// description, where Finder, Preview and photo apps show it.
	static func encode(_ image: CGImage, as format: UTType, quality: Double, genotype: RandomGenotype?) throws -> Data {
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, format.identifier as CFString, 1, nil) else {
			throw ExportError(message: "Can't write \(name(of: format)) files.")
		}
		var properties: [CFString: Any] = [:]
		if lossyFormats.contains(format) {
			properties[kCGImageDestinationLossyCompressionQuality] = quality
		}
		let metadata = CGImageMetadataCreateMutable()
		CGImageMetadataSetValueWithPath(metadata, nil, "xmp:CreatorTool" as CFString, "Evolv.io" as CFString)
		if let genotype {
			CGImageMetadataRegisterNamespaceForPrefix(metadata, xmpNamespace as CFString, xmpPrefix as CFString, nil)
			CGImageMetadataSetValueWithPath(metadata, nil, "\(xmpPrefix):expression" as CFString, genotype.text as CFString)
			if let name = genotype.name {
				CGImageMetadataSetValueWithPath(metadata, nil, "\(xmpPrefix):name" as CFString, name as CFString)
			}
			CGImageMetadataSetValueWithPath(metadata, nil, "dc:description" as CFString, genotype.text as CFString)
		}
		CGImageDestinationAddImageAndMetadata(destination, image, metadata, properties as CFDictionary)
		guard CGImageDestinationFinalize(destination) else {
			throw ExportError(message: "Couldn't encode the image as \(name(of: format)).")
		}
		return data as Data
	}

	/// The expression an exported image stored with `encode`, if any.
	static func embeddedExpression(in data: Data) -> String? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			  let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
			  let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "\(xmpPrefix):expression" as CFString) else {
			return nil
		}
		return CGImageMetadataTagCopyValue(tag) as? String
	}

	struct ExportError: LocalizedError {
		let message: String
		var errorDescription: String? { message }
	}
}

/// The Export Image dialog. Every setting is stored in user defaults, so
/// it opens the way it was last left.
struct ExportImageSheet: View {
	let genotype: RandomGenotype

	/// Suggested sizes: from the grid's thumbnails up to twice the full size view.
	private static let sizePresets: [(size: Int, label: String)] = [
		(256, "256 × 256 (thumbnail)"),
		(512, "512 × 512"),
		(800, "800 × 800 (full size)"),
		(1024, "1024 × 1024"),
		(1200, "1200 × 1200"),
		(1600, "1600 × 1600 (2× full size)"),
	]
	private static let sizeRange = 16...4096
	/// Samples per side of each pixel; 0 follows the app's Supersampling setting.
	private static let supersampleOptions = [1, 2, 3, 4, 6, 8]
	private static let customSizeTag = -1

	@AppStorage("exportImageSize") private var size = 1600
	@AppStorage("exportImageCustomSize") private var isCustomSize = false
	@AppStorage("exportImageFormat") private var formatIdentifier = UTType.png.identifier
	@AppStorage("exportImageQuality") private var quality = 0.9
	@AppStorage("exportImageSupersample") private var supersample = 0
	@AppStorage("exportImageEmbedGenotype") private var embedGenotype = true

	@Environment(\.dismiss) private var dismiss
	@State private var isExporting = false
	@State private var errorMessage: String?
#if !os(macOS)
	@State private var exportedFile: ExportedImageFile?
#endif

	private var format: UTType {
		UTType(formatIdentifier).flatMap { ImageExporter.formats.contains($0) ? $0 : nil } ?? .png
	}

	private var clampedSize: Int {
		min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
	}

	/// The supersampling the export will use, with 0 resolved to the app's setting.
	private var effectiveSupersample: Int {
		supersample == 0 ? (UserDefaults.standard.isSupersamplingEnabled ? 4 : 1) : supersample
	}

	private var sizeSelection: Binding<Int> {
		Binding {
			isCustomSize || !Self.sizePresets.contains(where: { $0.size == size }) ? Self.customSizeTag : size
		} set: { newValue in
			if newValue == Self.customSizeTag {
				isCustomSize = true
			} else {
				isCustomSize = false
				size = newValue
			}
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Export Image")
				.font(.headline)
			Form {
				Picker("Size", selection: sizeSelection) {
					ForEach(Self.sizePresets, id: \.size) { preset in
						Text(preset.label).tag(preset.size)
					}
					Divider()
					Text("Custom").tag(Self.customSizeTag)
				}
				if sizeSelection.wrappedValue == Self.customSizeTag {
					LabeledContent("Pixels") {
						HStack {
							TextField("Pixels", value: $size, format: .number.grouping(.never))
								.labelsHidden()
								.frame(width: 80)
							Text("× \(clampedSize) (\(Self.sizeRange.lowerBound)–\(Self.sizeRange.upperBound))")
								.foregroundStyle(.secondary)
						}
					}
				}

				Picker("Format", selection: $formatIdentifier) {
					ForEach(ImageExporter.formats, id: \.identifier) { format in
						Text(ImageExporter.name(of: format)).tag(format.identifier)
					}
				}
				if ImageExporter.lossyFormats.contains(format) {
					LabeledContent("Quality") {
						HStack {
							Slider(value: $quality, in: 0.1...1)
							Text(quality, format: .percent.precision(.fractionLength(0)))
								.monospacedDigit()
								.frame(width: 44, alignment: .trailing)
						}
					}
				}

				Picker("Supersampling", selection: $supersample) {
					Text("Same as app (\(UserDefaults.standard.isSupersamplingEnabled ? "4 × 4" : "off"))").tag(0)
					Divider()
					ForEach(Self.supersampleOptions, id: \.self) { samples in
						Text(samples == 1 ? "Off" : "\(samples) × \(samples)").tag(samples)
					}
				}

				Toggle("Store genotype in image metadata", isOn: $embedGenotype)
					.disabled(!ImageExporter.metadataFormats.contains(format))
					.help(ImageExporter.metadataFormats.contains(format)
						  ? "Saves the expression and name in the file's XMP metadata"
						  : "\(format.preferredFilenameExtension?.uppercased() ?? "This format") files can't store it")
			}
#if os(macOS)
			.formStyle(.columns)
#endif

			Text(summary)
				.font(.caption)
				.foregroundStyle(.secondary)
			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}
			HStack {
				if isExporting {
					ProgressView()
						.controlSize(.small)
					Text("Rendering…")
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Export…", action: export)
					.keyboardShortcut(.defaultAction)
			}
			.disabled(isExporting)
		}
		.padding()
#if os(macOS)
		.frame(width: 460)
#else
		.fileExporter(isPresented: Binding { exportedFile != nil } set: { if !$0 { exportedFile = nil } },
					  document: exportedFile,
					  contentType: format,
					  defaultFilename: defaultFilename) { result in
			if case .failure(let error) = result {
				errorMessage = error.localizedDescription
			} else {
				dismiss()
			}
		}
#endif
	}

	private var summary: String {
		let samples = effectiveSupersample * effectiveSupersample
		return "\(clampedSize) × \(clampedSize) pixels, \(samples) sample\(samples == 1 ? "" : "s") per pixel."
	}

	private var defaultFilename: String {
		genotype.name ?? "Untitled"
	}

	/// Renders and encodes with the dialog's current settings.
	private func renderData() async throws -> Data {
		let rendered = try await ImageExporter.render(node: genotype.node, size: clampedSize, supersample: effectiveSupersample)
		return try ImageExporter.encode(rendered, as: format, quality: quality,
										genotype: embedGenotype ? genotype : nil)
	}

#if os(macOS)
	/// Asks where to save first, then renders, so a cancelled save panel
	/// doesn't cost a render.
	private func export() {
		size = clampedSize
		errorMessage = nil
		let panel = NSSavePanel()
		panel.title = "Export Image"
		panel.nameFieldStringValue = defaultFilename
		panel.allowedContentTypes = [format]
		panel.canCreateDirectories = true
		panel.isExtensionHidden = false
		let completion: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			isExporting = true
			Task {
				defer { isExporting = false }
				do {
					try await renderData().write(to: url, options: .atomic)
					dismiss()
				} catch {
					errorMessage = error.localizedDescription
				}
			}
		}
		if let window = NSApp.keyWindow {
			panel.beginSheetModal(for: window, completionHandler: completion)
		} else {
			panel.begin(completionHandler: completion)
		}
	}
#else
	/// Renders, then asks where to save.
	private func export() {
		size = clampedSize
		errorMessage = nil
		isExporting = true
		Task {
			defer { isExporting = false }
			do {
				exportedFile = ExportedImageFile(data: try await renderData(), contentType: format)
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}
#endif
}

#if !os(macOS)
/// An encoded image for `fileExporter`.
private struct ExportedImageFile: FileDocument {
	static let readableContentTypes: [UTType] = [.image]

	let data: Data
	let contentType: UTType

	init(data: Data, contentType: UTType) {
		self.data = data
		self.contentType = contentType
	}

	init(configuration: ReadConfiguration) throws {
		throw CocoaError(.fileReadUnsupportedScheme)
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
#endif
