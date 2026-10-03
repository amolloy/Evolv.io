//
//  GenotypeStore.swift
//  Evolv.io
//
//  The app's live list of genotypes (bundled + user `.evolvgenotype` files,
//  see GenotypeLibrary), shared by the sidebar and the MCP tools. Reloaded
//  in place by the "Reload Genotypes" menu item and after every MCP write
//  or delete, so the sidebar picks up changes without a relaunch.
//

import Foundation
import Observation
import ExpressionTree

@MainActor
@Observable
final class GenotypeStore {
	static let shared = GenotypeStore()

	private(set) var genotypes: [Genotype] = []
	private(set) var loadIssues: [GenotypeLoadIssue] = []
	/// The user genotypes arranged by the folders they're in on disk.
	private(set) var userOutline = GenotypeFolder(path: [])

	private init() {
		reload()
	}

	func reload() {
		let result = GenotypeLibrary.scan(roots: GenotypeLibrary.productionRoots)
		genotypes = result.genotypes
		loadIssues = result.issues
		let folders = GenotypeLibrary.containerGenotypesDirectory.map(GenotypeLibrary.folders(under:)) ?? []
		userOutline = GenotypeLibrary.outline(of: genotypes.filter { $0.source == .user }, folders: folders)
		for issue in loadIssues {
			print("Genotype load issue (\(issue.fileURL.lastPathComponent)): \(issue.message)")
		}
	}

	func genotype(id: String) -> Genotype? {
		genotypes.first { $0.id == id }
	}

	struct SaveError: LocalizedError {
		let errorDescription: String?
	}

	/// Writes `expression` as a new user genotype called `name` and reloads.
	/// The file name comes from `name` (lowercased, anything but letters and
	/// digits turned into dashes), with -2, -3, ... added if that id is
	/// taken, so saving never overwrites an existing genotype.
	@discardableResult
	func saveUserGenotype(name: String, expression: String) throws -> Genotype {
		guard let directory = GenotypeLibrary.containerGenotypesDirectory else {
			throw SaveError(errorDescription: "Couldn't find the Genotypes folder.")
		}
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
		var slug = trimmedName.lowercased()
			.map { $0.isLetter || $0.isNumber ? String($0) : "-" }
			.joined()
			.split(separator: "-")
			.joined(separator: "-")
		if slug.isEmpty { slug = "genotype" }

		let takenIDs = Set(genotypes.map(\.id))
		var id = slug
		var suffix = 2
		while takenIDs.contains(id) || FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id).\(GenotypeLibrary.fileExtension)").path) {
			id = "\(slug)-\(suffix)"
			suffix += 1
		}

		let fileURL = directory.appendingPathComponent("\(id).\(GenotypeLibrary.fileExtension)")
		let header = trimmedName.isEmpty ? "" : "---\nname: \"\(trimmedName)\"\n---\n"
		do {
			try (header + expression + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
		} catch {
			throw SaveError(errorDescription: "Couldn't write \(fileURL.lastPathComponent): \(error.localizedDescription)")
		}

		reload()
		guard let saved = genotype(id: id) else {
			let issue = loadIssues.first { $0.fileURL.lastPathComponent == fileURL.lastPathComponent }
			throw SaveError(errorDescription: "Wrote \(fileURL.lastPathComponent), but it didn't load: \(issue?.message ?? "unknown problem")")
		}
		return saved
	}

	/// Writes `expression` to `fileURL` (anywhere, e.g. from a save panel),
	/// replacing what's there, with the file name as the genotype's name.
	/// Reloads afterwards, so a file saved into the user Genotypes folder
	/// shows up in the library.
	func writeGenotype(expression: String, to fileURL: URL) throws {
		let name = fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "\"", with: "")
		let header = name.isEmpty ? "" : "---\nname: \"\(name)\"\n---\n"
		do {
			try (header + expression + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
		} catch {
			throw SaveError(errorDescription: "Couldn't write \(fileURL.lastPathComponent): \(error.localizedDescription)")
		}
		reload()
	}

	// MARK: - Folders

	/// The on-disk folder for `path` (relative to the user Genotypes folder).
	func folderURL(_ path: [String]) throws -> URL {
		guard let root = GenotypeLibrary.containerGenotypesDirectory else {
			throw SaveError(errorDescription: "Couldn't find the Genotypes folder.")
		}
		return path.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
	}

	/// Why `name` can't be a folder name, or nil if it can.
	static func folderNameProblem(_ name: String) -> String? {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty { return "A folder needs a name." }
		if trimmed.contains("/") || trimmed.contains(":") { return "Folder names can't contain \"/\" or \":\"." }
		if trimmed.hasPrefix(".") { return "Folder names can't start with \".\"." }
		return nil
	}

	/// Creates a folder called `name` inside `parent` and reloads. Returns
	/// the new folder's path.
	@discardableResult
	func createFolder(named name: String, in parent: [String]) throws -> [String] {
		if let problem = Self.folderNameProblem(name) {
			throw SaveError(errorDescription: problem)
		}
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let url = try folderURL(parent + [trimmed])
		if FileManager.default.fileExists(atPath: url.path) {
			throw SaveError(errorDescription: "There's already a folder called \"\(trimmed)\" there.")
		}
		do {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		} catch {
			throw SaveError(errorDescription: "Couldn't create \"\(trimmed)\": \(error.localizedDescription)")
		}
		reload()
		return parent + [trimmed]
	}

	/// Renames the folder at `path` to `newName` and reloads. Returns the
	/// folder's new path.
	@discardableResult
	func renameFolder(_ path: [String], to newName: String) throws -> [String] {
		if let problem = Self.folderNameProblem(newName) {
			throw SaveError(errorDescription: problem)
		}
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		let newPath = Array(path.dropLast()) + [trimmed]
		guard newPath != path else { return path }
		let source = try folderURL(path)
		let destination = try folderURL(newPath)
		// A case-only rename is the same folder on a case-insensitive disk.
		if FileManager.default.fileExists(atPath: destination.path), path.last?.lowercased() != trimmed.lowercased() {
			throw SaveError(errorDescription: "There's already a folder called \"\(trimmed)\" there.")
		}
		do {
			try FileManager.default.moveItem(at: source, to: destination)
		} catch {
			throw SaveError(errorDescription: "Couldn't rename \"\(path.last ?? "")\": \(error.localizedDescription)")
		}
		reload()
		return newPath
	}

	/// Moves the folder at `path`, and everything in it, to the Trash.
	func trashFolder(_ path: [String]) throws {
		guard !path.isEmpty else { return }
		do {
			try FileManager.default.trashItem(at: try folderURL(path), resultingItemURL: nil)
		} catch let error as SaveError {
			throw error
		} catch {
			throw SaveError(errorDescription: "Couldn't move \"\(path.last ?? "")\" to the Trash: \(error.localizedDescription)")
		}
		reload()
	}

	/// Moves a user genotype's file into the folder at `folder`, keeping its
	/// file name (and so its id), and reloads.
	func move(_ genotype: Genotype, to folder: [String]) throws {
		guard genotype.source == .user else {
			throw SaveError(errorDescription: "Bundled genotypes can't be moved.")
		}
		guard genotype.folder != folder else { return }
		let destination = try folderURL(folder).appendingPathComponent(genotype.fileURL.lastPathComponent)
		if FileManager.default.fileExists(atPath: destination.path) {
			throw SaveError(errorDescription: "There's already a \(destination.lastPathComponent) in that folder.")
		}
		do {
			try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
			try FileManager.default.moveItem(at: genotype.fileURL, to: destination)
		} catch {
			throw SaveError(errorDescription: "Couldn't move \(genotype.fileURL.lastPathComponent): \(error.localizedDescription)")
		}
		reload()
	}

	/// Moves the folder at `path` inside the folder at `newParent`, and
	/// reloads. Returns its new path.
	@discardableResult
	func moveFolder(_ path: [String], into newParent: [String]) throws -> [String] {
		guard let name = path.last else { return path }
		guard !newParent.starts(with: path) else {
			throw SaveError(errorDescription: "A folder can't go inside itself.")
		}
		let newPath = newParent + [name]
		guard newPath != path else { return path }
		let destination = try folderURL(newPath)
		if FileManager.default.fileExists(atPath: destination.path) {
			throw SaveError(errorDescription: "There's already a folder called \"\(name)\" there.")
		}
		do {
			try FileManager.default.moveItem(at: try folderURL(path), to: destination)
		} catch {
			throw SaveError(errorDescription: "Couldn't move \"\(name)\": \(error.localizedDescription)")
		}
		reload()
		return newPath
	}

	/// Moves whatever was dropped on a folder in the sidebar there: a user
	/// genotype or folder from this library is moved; a `.evolvgenotype`
	/// file from elsewhere (e.g. Finder) is copied in, unless its id is
	/// already taken. Anything else is ignored. Returns whether anything
	/// changed.
	@discardableResult
	func handleDrop(of urls: [URL], into folder: [String]) throws -> Bool {
		let root = try folderURL([]).standardizedFileURL.pathComponents
		var changed = false
		for url in urls {
			let components = url.standardizedFileURL.pathComponents
			if components.starts(with: root) {
				let relative = Array(components.dropFirst(root.count))
				if url.pathExtension == GenotypeLibrary.fileExtension {
					if let genotype = genotypes.first(where: { $0.source == .user && $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
						try move(genotype, to: folder)
						changed = true
					}
				} else if !relative.isEmpty, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
					try moveFolder(relative, into: folder)
					changed = true
				}
			} else if url.pathExtension == GenotypeLibrary.fileExtension {
				let id = url.deletingPathExtension().lastPathComponent
				if genotype(id: id) != nil {
					throw SaveError(errorDescription: "There's already a genotype called \"\(id)\" in the library.")
				}
				let destination = try folderURL(folder).appendingPathComponent(url.lastPathComponent)
				do {
					try FileManager.default.copyItem(at: url, to: destination)
				} catch {
					throw SaveError(errorDescription: "Couldn't copy \(url.lastPathComponent): \(error.localizedDescription)")
				}
				reload()
				changed = true
			}
		}
		return changed
	}
}
