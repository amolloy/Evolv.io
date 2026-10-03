//
//  GenotypeSidebar.swift
//  Evolv.io
//
//  The genotype library's sidebar: the bundled genotypes as one flat
//  group, then the user's genotypes as a collapsible outline of the real
//  folders inside the user Genotypes folder (see GenotypeStore.userOutline).
//  Folders can be created, renamed and trashed from their context menus,
//  and genotypes and folders moved by dragging them onto a folder (or with
//  Move To). A .evolvgenotype dragged in from Finder is copied in.
//

import SwiftUI
import ExpressionTree
#if os(macOS)
import AppKit
#endif

struct GenotypeSidebar: View {
	@Binding var selectedID: String?

	private let store = GenotypeStore.shared
	@State private var model = GenotypeSidebarModel()

	var body: some View {
		List(selection: $selectedID) {
			Section("Bundled", isExpanded: $model.bundledExpanded) {
				ForEach(store.genotypes.filter { $0.source == .bundled }, id: \.id) { genotype in
					GenotypeRow(genotype: genotype, model: model)
				}
			}
			Section(isExpanded: $model.userExpanded) {
				GenotypeFolderContents(folder: store.userOutline, model: model)
			} header: {
				Text("My Genotypes")
					.dropDestination(for: URL.self) { urls, _ in
						model.drop(urls, into: [])
					}
					.contextMenu {
						Button("New Folder…") { model.promptForNewFolder(in: []) }
					}
			}
		}
		.contextMenu {
			Button("New Folder…") { model.promptForNewFolder(in: []) }
		}
		.alert(model.prompt?.title ?? "", isPresented: model.isPromptingBinding) {
			TextField("Name", text: $model.promptName)
			Button(model.prompt?.confirmTitle ?? "OK") { model.confirmPrompt() }
				.disabled(GenotypeStore.folderNameProblem(model.promptName) != nil)
			Button("Cancel", role: .cancel) { model.prompt = nil }
		}
		.confirmationDialog(
			"Move \"\(model.trashing?.name ?? "")\" to the Trash?",
			isPresented: model.isConfirmingTrashBinding
		) {
			Button("Move to Trash", role: .destructive) { model.confirmTrash() }
			Button("Cancel", role: .cancel) { model.trashing = nil }
		} message: {
			let count = model.trashing?.genotypeCount ?? 0
			Text("It holds \(count) genotype\(count == 1 ? "" : "s").")
		}
		.alert("Couldn't Change the Library", isPresented: model.isShowingErrorBinding) {
			Button("OK") { model.errorMessage = nil }
		} message: {
			Text(model.errorMessage ?? "")
		}
	}
}

/// A folder's subfolders (each a disclosure group) and then its genotypes.
private struct GenotypeFolderContents: View {
	let folder: GenotypeFolder
	let model: GenotypeSidebarModel

	var body: some View {
		ForEach(folder.subfolders) { subfolder in
			DisclosureGroup(isExpanded: model.expansionBinding(for: subfolder.path)) {
				GenotypeFolderContents(folder: subfolder, model: model)
			} label: {
				Label(subfolder.name, systemImage: "folder")
					.badge(subfolder.genotypeCount)
					.draggable(Self.url(of: subfolder))
					.dropDestination(for: URL.self) { urls, _ in
						model.drop(urls, into: subfolder.path)
					}
					.contextMenu {
						Button("New Folder…") { model.promptForNewFolder(in: subfolder.path) }
						Button("Rename…") { model.promptForRename(of: subfolder.path) }
						MoveToMenu(excluding: subfolder.path) { destination in
							model.perform { try GenotypeStore.shared.moveFolder(subfolder.path, into: destination) }
						}
#if os(macOS)
						Button("Show in Finder") {
							NSWorkspace.shared.activateFileViewerSelecting([Self.url(of: subfolder)])
						}
#endif
						Divider()
						Button("Move to Trash", role: .destructive) { model.requestTrash(of: subfolder) }
					}
			}
		}
		ForEach(folder.genotypes, id: \.id) { genotype in
			GenotypeRow(genotype: genotype, model: model)
		}
	}

	/// Only nil-safe for show: with no Genotypes folder there are no
	/// folders to show either.
	private static func url(of folder: GenotypeFolder) -> URL {
		(try? GenotypeStore.shared.folderURL(folder.path)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
	}
}

private struct GenotypeRow: View {
	let genotype: Genotype
	let model: GenotypeSidebarModel

	var body: some View {
		Text(genotype.displayName)
			.tag(genotype.id)
			.draggable(genotype.fileURL)
			.contextMenu {
				if genotype.source == .user {
					MoveToMenu(current: genotype.folder) { destination in
						model.perform { try GenotypeStore.shared.move(genotype, to: destination) }
					}
				}
#if os(macOS)
				Button("Show in Finder") {
					NSWorkspace.shared.activateFileViewerSelecting([genotype.fileURL])
				}
#endif
			}
	}
}

/// A "Move To" submenu listing every user folder (and the top level),
/// minus `excluding` and everything inside it, and minus `current`.
private struct MoveToMenu: View {
	var excluding: [String]? = nil
	var current: [String]? = nil
	let action: ([String]) -> Void

	var body: some View {
		let destinations = GenotypeStore.shared.userOutline.allFolders
			.map(\.path)
			.filter { path in
				if let excluding, path.starts(with: excluding) || path == Array(excluding.dropLast()) { return false }
				return path != current
			}
		Menu("Move To") {
			ForEach(destinations, id: \.self) { path in
				Button(path.isEmpty ? "My Genotypes" : path.joined(separator: " ▸ ")) { action(path) }
			}
		}
		.disabled(destinations.isEmpty)
	}
}

/// The sidebar's prompts, confirmations and folder expansion state.
@MainActor
@Observable
final class GenotypeSidebarModel {
	enum Prompt {
		case newFolder(parent: [String])
		case rename(path: [String])

		var title: String {
			switch self {
			case .newFolder: "New Folder"
			case .rename: "Rename Folder"
			}
		}

		var confirmTitle: String {
			switch self {
			case .newFolder: "Create"
			case .rename: "Rename"
			}
		}
	}

	private static let expandedFoldersKey = "GenotypeSidebar.expandedFolders"
	private static let bundledExpandedKey = "GenotypeSidebar.bundledExpanded"
	private static let userExpandedKey = "GenotypeSidebar.userExpanded"

	var prompt: Prompt?
	var promptName = ""
	var trashing: GenotypeFolder?
	var errorMessage: String?

	var bundledExpanded: Bool {
		didSet { UserDefaults.standard.set(bundledExpanded, forKey: Self.bundledExpandedKey) }
	}
	var userExpanded: Bool {
		didSet { UserDefaults.standard.set(userExpanded, forKey: Self.userExpandedKey) }
	}

	/// Expanded folders, by path joined with "/". Remembered across launches.
	private var expandedFolders: Set<String> {
		didSet { UserDefaults.standard.set(Array(expandedFolders).sorted(), forKey: Self.expandedFoldersKey) }
	}

	init() {
		let defaults = UserDefaults.standard
		bundledExpanded = defaults.object(forKey: Self.bundledExpandedKey) as? Bool ?? true
		userExpanded = defaults.object(forKey: Self.userExpandedKey) as? Bool ?? true
		expandedFolders = Set(defaults.stringArray(forKey: Self.expandedFoldersKey) ?? [])
	}

	func expansionBinding(for path: [String]) -> Binding<Bool> {
		let key = path.joined(separator: "/")
		return Binding(
			get: { self.expandedFolders.contains(key) },
			set: { expanded in
				if expanded {
					self.expandedFolders.insert(key)
				} else {
					self.expandedFolders.remove(key)
				}
			}
		)
	}

	var isPromptingBinding: Binding<Bool> {
		Binding(get: { self.prompt != nil }, set: { if !$0 { self.prompt = nil } })
	}

	var isConfirmingTrashBinding: Binding<Bool> {
		Binding(get: { self.trashing != nil }, set: { if !$0 { self.trashing = nil } })
	}

	var isShowingErrorBinding: Binding<Bool> {
		Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
	}

	func promptForNewFolder(in parent: [String]) {
		promptName = ""
		prompt = .newFolder(parent: parent)
	}

	func promptForRename(of path: [String]) {
		promptName = path.last ?? ""
		prompt = .rename(path: path)
	}

	func confirmPrompt() {
		guard let prompt else { return }
		self.prompt = nil
		let name = promptName
		switch prompt {
		case .newFolder(let parent):
			perform {
				try GenotypeStore.shared.createFolder(named: name, in: parent)
				if !parent.isEmpty {
					expandedFolders.insert(parent.joined(separator: "/"))
				}
			}
		case .rename(let path):
			perform {
				let newPath = try GenotypeStore.shared.renameFolder(path, to: name)
				renameExpansion(from: path, to: newPath)
			}
		}
	}

	/// Trashes an empty folder straight away; asks first if it holds
	/// anything.
	func requestTrash(of folder: GenotypeFolder) {
		if folder.genotypeCount == 0 {
			perform { try GenotypeStore.shared.trashFolder(folder.path) }
		} else {
			trashing = folder
		}
	}

	func confirmTrash() {
		guard let folder = trashing else { return }
		trashing = nil
		perform { try GenotypeStore.shared.trashFolder(folder.path) }
	}

	func drop(_ urls: [URL], into folder: [String]) -> Bool {
		var changed = false
		perform {
			changed = try GenotypeStore.shared.handleDrop(of: urls, into: folder)
		}
		if changed, !folder.isEmpty {
			expandedFolders.insert(folder.joined(separator: "/"))
		}
		return changed
	}

	func perform(_ body: () throws -> Void) {
		do {
			try body()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Keeps a renamed folder (and the folders inside it) expanded.
	private func renameExpansion(from oldPath: [String], to newPath: [String]) {
		let oldKey = oldPath.joined(separator: "/")
		let newKey = newPath.joined(separator: "/")
		expandedFolders = Set(expandedFolders.map { key in
			if key == oldKey { return newKey }
			if key.hasPrefix(oldKey + "/") { return newKey + key.dropFirst(oldKey.count) }
			return key
		})
	}
}
