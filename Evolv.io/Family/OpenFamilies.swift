//
//  OpenFamilies.swift
//  Evolv.io
//
//  The family documents open in windows, so the MCP family tools can find
//  them. DocumentGroup doesn't list its documents, so each family window
//  registers its own, with the window's undo manager, so changes made
//  through MCP are undoable in the window like any other, and its window,
//  whose NSDocument saves and closes it.
//

import SwiftUI
import ExpressionTree

@MainActor
final class OpenFamilies {
	static let shared = OpenFamilies()

	struct Entry {
		/// `f1`, `f2`, ... in the order windows opened; stable while open.
		let id: String
		let document: FamilyDocument
		var fileURL: URL?
		weak var undoManager: UndoManager?

		/// The undo manager for changes: the document's own once its window
		/// is known, since the view's can be missing when it registers, and
		/// a change undoable there also marks the document edited.
		var changeUndoManager: UndoManager? {
#if os(macOS)
			if let undoManager = nsDocument?.undoManager { return undoManager }
#endif
			return undoManager
		}
#if os(macOS)
		weak var window: NSWindow?

		/// DocumentGroup's NSDocument for this family, which saves and
		/// closes it; nil until its window is known.
		var nsDocument: NSDocument? {
			window?.windowController?.document as? NSDocument
		}
#endif

		/// The file name without its extension, or "Untitled".
		var name: String {
			fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
		}
	}

	private var entries: [ObjectIdentifier: Entry] = [:]
	private var nextNumber = 1

	func register(_ document: FamilyDocument, fileURL: URL?, undoManager: UndoManager?) {
		let key = ObjectIdentifier(document)
		if var entry = entries[key] {
			entry.fileURL = fileURL
			entry.undoManager = undoManager ?? entry.undoManager
			entries[key] = entry
		} else {
			entries[key] = Entry(id: "f\(nextNumber)", document: document, fileURL: fileURL, undoManager: undoManager)
			nextNumber += 1
#if os(macOS)
			entries[key]?.window = pendingWindows.removeValue(forKey: key)?.window
#endif
		}
	}

#if os(macOS)
	/// The window can be known before or after `register`. A nil window,
	/// from a reader view leaving as the window's content changes, is
	/// ignored; the entry goes when the window closes.
	func setWindow(_ window: NSWindow?, for document: FamilyDocument) {
		guard let window else { return }
		let key = ObjectIdentifier(document)
		if entries[key] != nil {
			entries[key]?.window = window
		} else {
			pendingWindows[key] = PendingWindow(window: window)
		}
	}

	private struct PendingWindow {
		weak var window: NSWindow?
	}

	private var pendingWindows: [ObjectIdentifier: PendingWindow] = [:]
#endif

	func unregister(_ document: FamilyDocument) {
		entries[ObjectIdentifier(document)] = nil
#if os(macOS)
		pendingWindows[ObjectIdentifier(document)] = nil
#endif
	}

	/// Open families, oldest window first.
	var all: [Entry] {
		entries.values.sorted { Int($0.id.dropFirst())! < Int($1.id.dropFirst())! }
	}

	/// By id (`f2`), name (`Blue Ripples`, ignoring case) or file path.
	/// With one family open, nil finds it.
	func find(_ key: String?) -> Entry? {
		guard let key, !key.isEmpty else {
			return all.count == 1 ? all[0] : nil
		}
		return all.first { $0.id == key }
			?? all.first { $0.name.caseInsensitiveCompare(key) == .orderedSame }
			?? all.first { $0.fileURL?.path == key }
	}
}

#if os(macOS)
/// Reports the window a view is in, for `OpenFamilies.setWindow`.
struct WindowReader: NSViewRepresentable {
	let onChange: (NSWindow?) -> Void

	func makeNSView(context: Context) -> NSView {
		ReaderView(onChange: onChange)
	}

	func updateNSView(_ nsView: NSView, context: Context) {}

	private final class ReaderView: NSView {
		let onChange: (NSWindow?) -> Void

		init(onChange: @escaping (NSWindow?) -> Void) {
			self.onChange = onChange
			super.init(frame: .zero)
		}

		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			onChange(window)
		}
	}
}
#endif
