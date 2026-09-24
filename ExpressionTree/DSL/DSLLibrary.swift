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
//  Namespacing convention: a file named exactly `Package.evolvnode`
//  (containing just `package "name"`) at a folder's top level namespaces
//  every other .evolvnode file anywhere beneath that folder within the
//  same root -- registered as `name.localName` instead of the bare
//  `localName`. A deeper folder's own `Package.evolvnode` takes over for
//  its own subtree instead of stacking with the outer one. Loose files
//  with no enclosing manifest register under their bare declared name.
//

import Foundation

/// Something that went wrong loading one `.evolvnode` file -- a parse
/// failure, a name collision, or an unresolved `requires()`. Collected
/// rather than thrown/fatalError'd: a bad or colliding file dropped in by
/// a user must never crash the app, unlike `DSLSampleDefinitions`'s fixed,
/// developer-controlled source text.
public struct DSLLoadIssue: Sendable {
	public let fileURL: URL
	public let message: String
}

public enum DSLLibrary {
	/// Recursively scans `roots` (in order) for `.evolvnode` files, resolves
	/// `Package.evolvnode` namespaces and `module` files, and builds a
	/// NodeRegistry constructor for every `node` file. A name already in
	/// `reservedNames` (a built-in Swift node, or an earlier file in this
	/// same scan) is a load issue, not a silent override -- the first
	/// successfully parsed claim on a name wins; everything else claiming
	/// that name is skipped and reported. Likewise, a node `requires()`ing
	/// a module that isn't found (in its own namespace, falling back to
	/// unnamespaced) is reported and that node is skipped, not crashed.
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
			let files = evolvNodeFiles(under: root)
			print("DSL scan: \(files.count) .evolvnode file(s) under \(root.path)")

			// Parse everything once. A parse failure here is reported and
			// that file just doesn't appear in `parsed` -- module/package
			// resolution below only ever sees successfully parsed files.
			var parsed: [URL: DSLFile] = [:]
			for fileURL in files {
				do {
					let source = try String(contentsOf: fileURL, encoding: .utf8)
					parsed[fileURL] = try DSLParser(source).parseFile()
				} catch {
					issues.append(DSLLoadIssue(fileURL: fileURL, message: "\(error)"))
				}
			}

			var namespaceByFolder: [String: String] = [:]
			for (fileURL, file) in parsed {
				if case .package(let name) = file {
					namespaceByFolder[fileURL.deletingLastPathComponent().path] = name
				}
			}

			func namespace(for fileURL: URL) -> String? {
				var folder = fileURL.deletingLastPathComponent()
				while true {
					if let name = namespaceByFolder[folder.path] { return name }
					if folder.path == root.path || folder.pathComponents.count <= 1 { return nil }
					folder = folder.deletingLastPathComponent()
				}
			}
			func qualify(_ bareName: String, fileURL: URL) -> String {
				guard let ns = namespace(for: fileURL) else { return bareName }
				return "\(ns).\(bareName)"
			}

			var modulesByQualifiedName: [String: DSLModule] = [:]
			for (fileURL, file) in parsed {
				guard case .module(let module) = file else { continue }
				let qualifiedName = qualify(module.name, fileURL: fileURL)
				modulesByQualifiedName[qualifiedName] = module
				let funcNames = module.funcs.map(\.name).joined(separator: ", ")
				print("DSL module loaded: '\(qualifiedName)' (funcs: \(funcNames)) from \(fileURL.lastPathComponent)")
			}

			for fileURL in files {
				guard case .node(let template)? = parsed[fileURL] else { continue }
				let name = qualify(template.name, fileURL: fileURL)

				if claimed.contains(name) {
					let owner = claimedBy[name]?.path ?? "a built-in node"
					issues.append(DSLLoadIssue(fileURL: fileURL, message: "node name '\(name)' is already used by \(owner); skipped"))
					continue
				}

				// `perlin` is a reserved intrinsic (see DSLCodegenNode);
				// everything else must resolve to a scanned module, tried
				// first in this node's own namespace, then unnamespaced.
				var resolvedModules: [String: DSLModule] = [:]
				var requiresFailed = false
				for requirement in template.requires where requirement != "perlin" {
					let qualifiedRequirement = qualify(requirement, fileURL: fileURL)
					guard let module = modulesByQualifiedName[qualifiedRequirement] ?? modulesByQualifiedName[requirement] else {
						issues.append(DSLLoadIssue(fileURL: fileURL, message: "requires(\(requirement)): no such module"))
						requiresFailed = true
						break
					}
					resolvedModules[requirement] = module
				}
				guard !requiresFailed else { continue }

				claimed.insert(name)
				claimedBy[name] = fileURL
				constructors[name] = { children in
					DSLCodegenNode(template: template, modules: resolvedModules, children: children)
				}

				let argList = template.params.map { $0.isFunction ? "\($0.name):fn" : $0.name }.joined(separator: ", ")
				let requiresSuffix = template.requires.isEmpty ? "" : " requires(\(template.requires.joined(separator: ", ")))"
				print("DSL node loaded: '\(name)' (\(template.params.count) args: \(argList))\(requiresSuffix) from \(fileURL.lastPathComponent)")
			}
		}

		print("DSL scan complete: \(constructors.count) node(s) registered, \(issues.count) issue(s)")
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

	/// The real roots used in production: the app-bundled node library and
	/// the user's container Nodes folder below. Despite living under
	/// `Evolv.io/Resources/BundledNodes/` in the source tree, the bundled
	/// `.evolvnode` files land directly in `Contents/Resources/` in the
	/// *built* app -- confirmed via the Phase 0 smoke test that Xcode's
	/// synchronized-group resource copying flattens subfolders rather than
	/// preserving them, and (re-)confirmed the hard way when this scanned
	/// `Resources/BundledNodes/` (which never exists) instead of
	/// `Resources/` itself, silently finding zero files. `resourceURL`
	/// itself is not recursed into subfolders the way the container root
	/// is -- there's no bundled subfolder to recurse into now that this
	/// points at the flattened location, consistent with the "bundled
	/// content stays flat" decision.
	public static var productionRoots: [URL] {
		var roots: [URL] = []
		if let resourceURL = Bundle.main.resourceURL {
			roots.append(resourceURL)
		}
		if let container = containerNodesDirectory {
			roots.append(container)
		}
		return roots
	}
}
