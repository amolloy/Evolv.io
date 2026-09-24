//
//  DSLLibrary.swift
//  Evolv.io
//
//  Scans one or more root folders for `.evolvnode` files and turns them
//  into NodeRegistry constructors -- the file-based counterpart to the
//  hardcoded `DSLSampleDefinitions.swift` spike registrations this
//  replaces. See the "file-based, hot-reloadable DSL node library" plan for
//  the full design (bundled vs. user roots, namespacing, modules).
//
//  Phase 1 scope: every `.evolvnode` file is a `node` (no `module`/`package`
//  parsing yet -- see DSLParser.parseTemplate, which only understands the
//  `node "name"(...) { ... }` form so far), and a bare declared name is
//  always the registry name (no namespace prefixing yet).
//

import Foundation

/// Something that went wrong loading one `.evolvnode` file -- a parse
/// failure or a name collision. Collected rather than thrown/fatalError'd:
/// a bad or colliding file dropped in by a user must never crash the app,
/// unlike `DSLSampleDefinitions`'s fixed, developer-controlled source text.
public struct DSLLoadIssue: Sendable {
	public let fileURL: URL
	public let message: String
}

public enum DSLLibrary {
	/// Recursively scans `roots` (in order) for `.evolvnode` files and
	/// parses each as a node definition. A name already in `reservedNames`
	/// (whether a built-in Swift node or an earlier file in this same scan)
	/// is a load issue, not a silent override -- the first successfully
	/// parsed claim on a name wins; everything else claiming that name is
	/// skipped and reported.
	///
	/// Takes explicit root `URL`s rather than reading `Bundle.main`/the
	/// container Documents folder itself, so this is testable against a
	/// fixture directory -- see `productionRoots` for the real roots.
	public static func scan(roots: [URL], reservedNames: Set<String>) -> (constructors: [String: NodeRegistry.NodeConstructor], issues: [DSLLoadIssue]) {
		var constructors: [String: NodeRegistry.NodeConstructor] = [:]
		var claimedBy: [String: URL] = [:]
		var claimed = reservedNames
		var issues: [DSLLoadIssue] = []

		for root in roots {
			for fileURL in evolvNodeFiles(under: root) {
				do {
					let source = try String(contentsOf: fileURL, encoding: .utf8)
					let template = try DSLParser(source).parseTemplate()
					let name = template.name

					if claimed.contains(name) {
						let owner = claimedBy[name]?.path ?? "a built-in node"
						issues.append(DSLLoadIssue(fileURL: fileURL, message: "node name '\(name)' is already used by \(owner); skipped"))
						continue
					}

					claimed.insert(name)
					claimedBy[name] = fileURL
					constructors[name] = { children in
						DSLCodegenNode(template: template, children: children)
					}
				} catch {
					issues.append(DSLLoadIssue(fileURL: fileURL, message: "\(error)"))
				}
			}
		}

		return (constructors, issues)
	}

	private static func evolvNodeFiles(under root: URL) -> [URL] {
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		var result: [URL] = []
		for case let url as URL in enumerator where url.pathExtension == "evolvnode" {
			result.append(url)
		}
		// Deterministic order so collisions between two loose files always
		// resolve the same way from one launch to the next.
		return result.sorted { $0.path < $1.path }
	}

	/// The user-editable Nodes folder inside this sandboxed app's own
	/// container Documents -- created on first access if missing. This
	/// app's entitlements (app-sandbox + files.user-selected.read-only
	/// only, see Evolv_io.entitlements) can't watch an arbitrary
	/// user-chosen folder without a one-time picker + security-scoped
	/// bookmark, so the container's own Documents (always readable/
	/// writable by a sandboxed app, no extra permission) is the folder --
	/// reachable via the "Reveal Nodes Folder" menu item.
	public static var containerNodesDirectory: URL? {
		guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
			return nil
		}
		let nodesDirectory = documents.appendingPathComponent("Nodes")
		try? FileManager.default.createDirectory(at: nodesDirectory, withIntermediateDirectories: true)
		return nodesDirectory
	}

	/// The real roots used in production: the app-bundled node library
	/// (flat -- see the plan's Phase 0 finding on why bundled resources
	/// can't have subfolders) and the user's container Nodes folder above
	/// (genuinely recursive, since it's scanned straight off the real
	/// filesystem rather than through Xcode's resource-copying pipeline).
	public static var productionRoots: [URL] {
		var roots: [URL] = []
		if let bundled = Bundle.main.resourceURL?.appendingPathComponent("BundledNodes") {
			roots.append(bundled)
		}
		if let container = containerNodesDirectory {
			roots.append(container)
		}
		return roots
	}
}
