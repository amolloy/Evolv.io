//
//  FamilyDocument.swift
//  Evolv.io
//
//  A family as a document: an `.evolvfamily` package holding
//  `family.json` (see Family and Documentation/EvolutionUI.md). Every
//  change goes through `change`, which registers an undo, so breeding,
//  rejecting and the rest are undoable and mark the document edited.
//

import SwiftUI
import UniformTypeIdentifiers
import ExpressionTree

extension UTType {
	/// Declared in Evolv.io-Info.plist.
	static let evolvFamily = UTType(exportedAs: "com.amolloy.evolv-io.family", conformingTo: .package)
}

final class FamilyDocument: ReferenceFileDocument {
	static let readableContentTypes: [UTType] = [.evolvFamily]
	static let familyFileName = "family.json"

	@Published private(set) var family: Family

	/// A new, empty family, with the random generator's app-wide
	/// exclusions as its defaults.
	init() {
		var settings = Family.Settings()
		settings.excludedRootFunctions = UserDefaults.standard.randomExcludedRootNodes.sorted()
		settings.excludedVariables = UserDefaults.standard.randomExcludedVariables.sorted()
		family = Family(settings: settings)
	}

	/// A new family whose first litter is one genotype from elsewhere
	/// (Start Family From This in the library).
	convenience init(seedExpression: String, source: String?) {
		self.init()
		_ = try? family.addSeedLitter(expressions: [seedExpression], source: source)
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.fileWrappers?[Self.familyFileName]?.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		family = try Family(json: data)
	}

	func snapshot(contentType: UTType) throws -> Family {
		family
	}

	/// Replaces just `family.json` in the package, so anything else in it
	/// (from a later version, say) is kept.
	func fileWrapper(snapshot: Family, configuration: WriteConfiguration) throws -> FileWrapper {
		let data = try snapshot.json()
		let package: FileWrapper
		if let existing = configuration.existingFile, existing.isDirectory {
			package = existing
		} else {
			package = FileWrapper(directoryWithFileWrappers: [:])
		}
		if let old = package.fileWrappers?[Self.familyFileName] {
			package.removeFileWrapper(old)
		}
		let file = FileWrapper(regularFileWithContents: data)
		file.preferredFilename = Self.familyFileName
		package.addFileWrapper(file)
		return package
	}

	// MARK: - Changes

	/// Applies `body` to a copy of the family and, if it doesn't throw,
	/// makes that the family, with an undo back to the old one.
	@discardableResult
	func change<Result>(_ actionName: String, undoManager: UndoManager?, _ body: (inout Family) throws -> Result) rethrows -> Result {
		var updated = family
		let result = try body(&updated)
		replace(with: updated, actionName: actionName, undoManager: undoManager)
		return result
	}

	private func replace(with newFamily: Family, actionName: String, undoManager: UndoManager?) {
		let oldFamily = family
		family = newFamily
		undoManager?.registerUndo(withTarget: self) { document in
			document.replace(with: oldFamily, actionName: actionName, undoManager: undoManager)
		}
		undoManager?.setActionName(actionName)
	}

	/// A root litter of random genotypes, with the family's settings.
	@discardableResult
	func addRandomLitter(undoManager: UndoManager?) -> Family.Litter {
		change("New Random Litter", undoManager: undoManager) { family in
			family.addRandomLitter(signatures: NodeRegistry.shared.signatures, seed: UInt64.random(in: 0...UInt64.max))
		}
	}

	/// A root litter of genotypes from elsewhere.
	@discardableResult
	/// `names`, when given, name the members in the same order.
	func addSeedLitter(expressions: [String], names: [String?] = [], source: String?, undoManager: UndoManager?) throws -> Family.Litter {
		try change(expressions.count == 1 ? "Add Genotype" : "Add Genotypes", undoManager: undoManager) { family in
			let litter = try family.addSeedLitter(expressions: expressions, source: source)
			for (member, name) in zip(family.members(ofLitter: litter.id), names) {
				family.update(member.id) { $0.name = name }
			}
			return litter
		}
	}

	/// One litter from each of `parentIDs`, in family order, as one undo.
	@discardableResult
	/// With `seed`, the first litter uses it, the next `seed + 1` and so on.
	func breed(_ parentIDs: Set<String>, seed: UInt64? = nil, undoManager: UndoManager?) throws -> [Family.Litter] {
		let ordered = family.members.map(\.id).filter(parentIDs.contains)
		return try change(ordered.count == 1 ? "Breed" : "Breed \(ordered.count)", undoManager: undoManager) { family in
			try ordered.enumerated().map { index, parent in
				let litterSeed = seed.map { $0 &+ UInt64(index) } ?? UInt64.random(in: 0...UInt64.max)
				return try family.breed(parent, signatures: NodeRegistry.shared.signatures, seed: litterSeed)
			}
		}
	}

	/// A mating litter from two members; `firstID` is the primary parent.
	@discardableResult
	func mate(_ firstID: String, _ secondID: String, method: MatingMethod, seed: UInt64? = nil,
			  undoManager: UndoManager?) throws -> Family.Litter {
		try change(method == .graft ? "Mate" : "Cross Over", undoManager: undoManager) { family in
			try family.mate(firstID, secondID, method: method, signatures: NodeRegistry.shared.signatures,
							seed: seed ?? UInt64.random(in: 0...UInt64.max))
		}
	}

	@discardableResult
	func reject(_ memberIDs: Set<String>, includingDescendants: Bool, undoManager: UndoManager?) throws -> Set<String> {
		try change("Reject", undoManager: undoManager) { family in
			try family.reject(memberIDs, includingDescendants: includingDescendants)
		}
	}

	func setStarred(_ starred: Bool, for memberIDs: Set<String>, undoManager: UndoManager?) {
		change(starred ? "Star" : "Unstar", undoManager: undoManager) { family in
			for id in memberIDs {
				family.update(id) { $0.starred = starred }
			}
		}
	}

	func rename(_ memberID: String, to name: String, undoManager: UndoManager?) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		change("Rename", undoManager: undoManager) { family in
			family.update(memberID) { $0.name = trimmed.isEmpty ? nil : trimmed }
		}
	}

	func setCollapsed(_ collapsed: Bool, for memberID: String, undoManager: UndoManager?) {
		change(collapsed ? "Collapse Branch" : "Expand Branch", undoManager: undoManager) { family in
			family.update(memberID) { $0.collapsed = collapsed }
		}
	}
}
