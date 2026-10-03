//
//  GenotypeLibrary.swift
//  Evolv.io
//
//  Loads `.evolvgenotype` files -- one expression each, with an optional
//  YAML-style front-matter header -- from the app-bundled genotype library
//  and the user's editable Genotypes folder. The genotype counterpart to
//  `DSLLibrary`'s node scanning; see Documentation/EvolvGenotypeFormat.md.
//
//  File shape:
//
//      ---
//      name: Figure 9
//      original_image: OriginalFigure9.gif
//      ---
//      (round (log (+ y (color-grad ...
//
//  The header is optional; without one the whole file is the expression.
//

import Foundation

/// One expression the app can show, loaded from a `.evolvgenotype` file.
public struct Genotype: Hashable, Sendable {
	public enum Source: String, Sendable {
		case bundled
		case user
	}

	/// The file name without its extension -- unique across the library,
	/// and what the MCP `write_genotype`/`delete_genotype` tools take.
	public let id: String
	/// The header's `name`, if any.
	public let name: String?
	/// The header's `original_image`: a reference image this expression is
	/// trying to reproduce, as written in the file.
	public let originalImageName: String?
	/// The file body, trimmed. Not parsed here -- that needs the node
	/// registry, and a genotype may use a user node that's fixed later.
	public let expression: String
	public let fileURL: URL
	public let source: Source
	/// The subfolders between the user Genotypes folder and the file, e.g.
	/// `["Hunts", "Spiral"]`; empty at the top level and for bundled files.
	public let folder: [String]

	public var displayName: String {
		name ?? expression
	}

	/// Where `originalImageName` actually lives: next to the genotype file
	/// first (so a user genotype can bring its own image), then the app
	/// bundle's resources.
	public var originalImageURL: URL? {
		guard let originalImageName else { return nil }
		let sibling = fileURL.deletingLastPathComponent().appendingPathComponent(originalImageName)
		if FileManager.default.fileExists(atPath: sibling.path) {
			return sibling
		}
		return Bundle.main.url(forResource: originalImageName, withExtension: nil)
	}
}

/// Something that went wrong loading one `.evolvgenotype` file. Like
/// `DSLLoadIssue`, collected rather than thrown so a bad user file never
/// crashes the app.
public struct GenotypeLoadIssue: Sendable {
	public let fileURL: URL
	public let message: String
}

public enum GenotypeLibrary {
	public static let fileExtension = "evolvgenotype"

	/// Header keys a genotype file may set. Anything else is reported.
	private static let knownKeys: Set<String> = ["name", "original_image"]

	/// Parses one file's text. Throws a message suitable for a load issue.
	/// A file whose only problem is an unknown header key still loads; the
	/// key comes back in `warnings`.
	public static func parse(_ text: String, fileURL: URL, source: Genotype.Source, folder: [String] = []) throws(GenotypeParseError) -> (genotype: Genotype, warnings: [String]) {
		var header: [String: String] = [:]
		var warnings: [String] = []
		var body = Substring(text)

		let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
		if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" {
			guard let closing = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
				throw GenotypeParseError(message: "Header opened with \"---\" but never closed with a second \"---\" line.")
			}
			for (offset, rawLine) in lines[1..<closing].enumerated() {
				let line = rawLine.trimmingCharacters(in: .whitespaces)
				if line.isEmpty || line.hasPrefix("#") { continue }
				guard let colon = line.firstIndex(of: ":") else {
					throw GenotypeParseError(message: "Header line \(offset + 2) (\"\(line)\") isn't \"key: value\".")
				}
				let key = line[..<colon].trimmingCharacters(in: .whitespaces)
				let value = unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
				guard knownKeys.contains(key) else {
					warnings.append("Unknown header key \"\(key)\" ignored (known: \(knownKeys.sorted().joined(separator: ", "))).")
					continue
				}
				if !value.isEmpty {
					header[key] = value
				}
			}
			body = lines[(closing + 1)...].joined(separator: "\n")[...]
		}

		let expression = body.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !expression.isEmpty else {
			throw GenotypeParseError(message: "No expression after the header.")
		}

		let genotype = Genotype(
			id: fileURL.deletingPathExtension().lastPathComponent,
			name: header["name"],
			originalImageName: header["original_image"],
			expression: expression,
			fileURL: fileURL,
			source: source,
			folder: folder
		)
		return (genotype, warnings)
	}

	/// Strips one pair of matching single or double quotes, so a name
	/// containing a colon or leading `#` can still be written.
	private static func unquote(_ value: String) -> String {
		guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
			return value
		}
		return String(value.dropFirst().dropLast())
	}

	/// Scans `roots` in order (bundled first, then user) and returns every
	/// genotype, each root's files sorted by path so bundled files keep the
	/// order their names give them. An id already claimed by an earlier
	/// file -- including a user file named like a bundled one -- is a load
	/// issue and skipped: the bundled one wins, as with nodes.
	///
	/// Takes explicit roots rather than reading `Bundle.main` itself, so
	/// this is testable against a fixture directory -- see `productionRoots`.
	public static func scan(roots: [(url: URL, source: Genotype.Source)]) -> (genotypes: [Genotype], issues: [GenotypeLoadIssue]) {
		var genotypes: [Genotype] = []
		var claimedBy: [String: URL] = [:]
		var issues: [GenotypeLoadIssue] = []

		for root in roots {
			for fileURL in genotypeFiles(under: root.url) {
				let text: String
				do {
					text = try String(contentsOf: fileURL, encoding: .utf8)
				} catch {
					issues.append(GenotypeLoadIssue(fileURL: fileURL, message: "Could not read file: \(error.localizedDescription)"))
					continue
				}

				let parsed: (genotype: Genotype, warnings: [String])
				do {
					let folder = root.source == .user ? relativeFolder(of: fileURL, under: root.url) : []
					parsed = try parse(text, fileURL: fileURL, source: root.source, folder: folder)
				} catch {
					issues.append(GenotypeLoadIssue(fileURL: fileURL, message: error.message))
					continue
				}
				issues.append(contentsOf: parsed.warnings.map { GenotypeLoadIssue(fileURL: fileURL, message: $0) })

				let id = parsed.genotype.id
				if let existing = claimedBy[id] {
					issues.append(GenotypeLoadIssue(fileURL: fileURL, message: "Genotype \"\(id)\" is already defined by \(existing.path); skipped."))
					continue
				}
				claimedBy[id] = fileURL
				genotypes.append(parsed.genotype)
			}
		}
		return (genotypes, issues)
	}

	private static func genotypeFiles(under root: URL) -> [URL] {
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		var result: [URL] = []
		for case let url as URL in enumerator where url.pathExtension == fileExtension {
			result.append(url)
		}
		return result.sorted { $0.path < $1.path }
	}

	/// Every folder under `root` (not `root` itself) as a path relative to
	/// it, empty ones included, so the sidebar can show a folder before
	/// anything is in it. Hidden folders and packages are skipped.
	public static func folders(under root: URL) -> [[String]] {
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles, .skipsPackageDescendants]
		) else {
			return []
		}
		var result: [[String]] = []
		for case let url as URL in enumerator {
			guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
				continue
			}
			result.append(relativeFolder(of: url.appendingPathComponent("_"), under: root))
		}
		return result.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
	}

	/// The folders between `root` and the file at `fileURL`.
	private static func relativeFolder(of fileURL: URL, under root: URL) -> [String] {
		let rootComponents = root.standardizedFileURL.pathComponents
		let parentComponents = fileURL.deletingLastPathComponent().standardizedFileURL.pathComponents
		guard parentComponents.starts(with: rootComponents) else {
			return []
		}
		return Array(parentComponents.dropFirst(rootComponents.count))
	}

	/// Arranges user genotypes and folders (see `folders(under:)`) into a
	/// tree rooted at the Genotypes folder itself. Subfolders sort by name
	/// the way Finder does; genotypes keep the order they're given in.
	public static func outline(of genotypes: [Genotype], folders: [[String]]) -> GenotypeFolder {
		var root = GenotypeFolder(path: [])
		for path in folders {
			root.insertFolder(path[...])
		}
		for genotype in genotypes {
			root.insert(genotype, at: genotype.folder[...])
		}
		root.sortSubfolders()
		return root
	}

	/// The user-editable Genotypes folder, beside the user Nodes folder
	/// (see `DSLLibrary.containerNodesDirectory` and `UserLibrary` for
	/// where that is). Created on first access if missing.
	public static var containerGenotypesDirectory: URL? {
		UserLibrary.directory(named: "Genotypes")
	}

	/// The app bundle's resources (where Xcode flattens
	/// `Evolv.io/Resources/BundledGenotypes/`, as with `BundledNodes` -- see
	/// `DSLLibrary.productionRoots`) and the user Genotypes folder.
	public static var productionRoots: [(url: URL, source: Genotype.Source)] {
		var roots: [(url: URL, source: Genotype.Source)] = []
		if let resourceURL = Bundle.main.resourceURL {
			roots.append((resourceURL, .bundled))
		}
		if let container = containerGenotypesDirectory {
			roots.append((container, .user))
		}
		return roots
	}
}

/// One folder of the user genotype library, see `GenotypeLibrary.outline`.
public struct GenotypeFolder: Hashable, Sendable, Identifiable {
	/// Relative to the Genotypes folder; empty for the Genotypes folder itself.
	public let path: [String]
	public internal(set) var subfolders: [GenotypeFolder] = []
	public internal(set) var genotypes: [Genotype] = []

	public init(path: [String]) {
		self.path = path
	}

	public var id: String { path.joined(separator: "/") }
	public var name: String { path.last ?? "" }

	/// Every genotype in this folder and all of its subfolders.
	public var genotypeCount: Int {
		genotypes.count + subfolders.reduce(0) { $0 + $1.genotypeCount }
	}

	/// This folder and every folder under it, depth first.
	public var allFolders: [GenotypeFolder] {
		[self] + subfolders.flatMap(\.allFolders)
	}

	mutating func insertFolder(_ rest: ArraySlice<String>) {
		guard let first = rest.first else { return }
		let index = subfolderIndex(named: first)
		subfolders[index].insertFolder(rest.dropFirst())
	}

	mutating func insert(_ genotype: Genotype, at rest: ArraySlice<String>) {
		guard let first = rest.first else {
			genotypes.append(genotype)
			return
		}
		let index = subfolderIndex(named: first)
		subfolders[index].insert(genotype, at: rest.dropFirst())
	}

	mutating func sortSubfolders() {
		subfolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		for index in subfolders.indices {
			subfolders[index].sortSubfolders()
		}
	}

	private mutating func subfolderIndex(named name: String) -> Int {
		if let index = subfolders.firstIndex(where: { $0.name == name }) {
			return index
		}
		subfolders.append(GenotypeFolder(path: path + [name]))
		return subfolders.count - 1
	}
}

public struct GenotypeParseError: Error {
	public let message: String
}
