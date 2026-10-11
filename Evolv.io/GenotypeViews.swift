//
//  GenotypeViews.swift
//  Evolv.io
//
//  Views for showing one genotype outside the library: the full size view
//  (the window File > Open Genotype opens, and the family window's full
//  size sheet), its selectable expression text, and the save sheet used
//  where there's no save panel. File > Save Genotype saves the one in the
//  key full size view (File > Open Genotype is in GenotypeWindow.swift).
//

import SwiftUI
import ExpressionTree
#if os(macOS)
import AppKit
#endif

/// One genotype's expression and the node tree parsed from it: a family
/// member, or opened from a file.
struct RandomGenotype: Identifiable {
	let id = UUID()
	let text: String
	let node: any Node
	/// The genotype file's name, for one opened from a file.
	var name: String?
}

/// A genotype rendered at 800 x 800 above its expression: the family
/// window's full size sheet, and the window File > Open Genotype opens. Its context menu
/// exports the image, and File > Save Genotype saves the genotype while it's
/// key.
struct FullSizeGenotypeView: View {
	let genotype: RandomGenotype

	@State private var exportingGenotype: RandomGenotype?

	var body: some View {
		VStack(alignment: .leading) {
			RenderedImageView(nodeRenderer: NodeRenderer(node: genotype.node,
														 evaluator: Evaluator(size: CGSize(width: 800, height: 800))))
				.contextMenu {
					Button("Export Image…") { exportingGenotype = genotype }
				}
			ExpressionTextView(text: genotype.text)
				.frame(width: 800, height: 120)
		}
		.padding()
		.sheet(item: $exportingGenotype) { genotype in
			ExportImageSheet(genotype: genotype)
		}
#if os(macOS)
		// Set here so File > Save Genotype follows whichever full size view
		// is key, when several are open.
		.focusedSceneValue(\.saveGenotype, { GenotypeFilePanels.save(genotype) })
#endif
	}
}

/// The expression in the full size view: read-only, but selectable and
/// copyable, and scrolls when it's long.
private struct ExpressionTextView: View {
	let text: String

	var body: some View {
#if os(macOS)
		SelectableTextView(text: text)
			.overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
#else
		ScrollView {
			Text(text)
				.font(.system(.body, design: .monospaced))
				.textSelection(.enabled)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
#endif
	}
}

#if os(macOS)
/// File > Save Genotype, published by the key full size view.
struct SaveGenotypeKey: FocusedValueKey {
	typealias Value = () -> Void
}

extension FocusedValues {
	var saveGenotype: SaveGenotypeKey.Value? {
		get { self[SaveGenotypeKey.self] }
		set { self[SaveGenotypeKey.self] = newValue }
	}
}

/// A non-editable NSTextView: any part of the expression can be selected and
/// copied, with the usual Copy and Select All menu items.
private struct SelectableTextView: NSViewRepresentable {
	let text: String

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSTextView.scrollableTextView()
		let textView = scrollView.documentView as! NSTextView
		textView.isEditable = false
		textView.isSelectable = true
		textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
		textView.textContainerInset = NSSize(width: 4, height: 4)
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		let textView = scrollView.documentView as! NSTextView
		if textView.string != text {
			textView.string = text
		}
	}
}
#endif

/// Asks for a name and saves the expression as a user genotype (see
/// GenotypeStore.saveUserGenotype). It then shows up in the genotype
/// library window.
/// Used where there's no save panel; on macOS, see GenotypeFilePanels.save.
struct SaveGenotypeSheet: View {
	let expression: String

	@Environment(\.dismiss) private var dismiss
	@State private var name = ""
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Save as Genotype")
				.font(.headline)
			TextField("Name", text: $name)
				.textFieldStyle(.roundedBorder)
				.onSubmit(save)
			Text(expression)
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)
				.lineLimit(4)
				.textSelection(.enabled)
			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Save", action: save)
					.keyboardShortcut(.defaultAction)
					.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
		.padding()
		.frame(width: 420)
	}

	private func save() {
		do {
			try GenotypeStore.shared.saveUserGenotype(name: name, expression: expression)
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
