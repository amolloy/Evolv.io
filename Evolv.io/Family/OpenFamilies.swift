//
//  OpenFamilies.swift
//  Evolv.io
//
//  The family documents open in windows, so the MCP family tools can find
//  them. DocumentGroup doesn't list its documents, so each family window
//  registers its own, with the window's undo manager, so changes made
//  through MCP are undoable in the window like any other.
//

import Foundation
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
		}
	}

	func unregister(_ document: FamilyDocument) {
		entries[ObjectIdentifier(document)] = nil
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
