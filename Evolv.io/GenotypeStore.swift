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

	private init() {
		reload()
	}

	func reload() {
		let result = GenotypeLibrary.scan(roots: GenotypeLibrary.productionRoots)
		genotypes = result.genotypes
		loadIssues = result.issues
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
}
