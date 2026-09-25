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
}
