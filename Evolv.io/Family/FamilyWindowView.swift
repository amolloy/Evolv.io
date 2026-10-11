//
//  FamilyWindowView.swift
//  Evolv.io
//
//  A family document's window: the lineage view, generations left to
//  right, laid out by FamilyLayout. Click selects (Command-click and
//  Shift-click add), Return breeds a litter from each selected member,
//  Delete rejects, double-click shows full size. A first cut: thumbnails
//  are cached in memory only and everything visible or not is rendered.
//  See Documentation/EvolutionUI.md.
//

import SwiftUI
import ExpressionTree

struct FamilyWindowView: View {
	@ObservedObject var document: FamilyDocument

	@Environment(\.undoManager) private var undoManager
	@AppStorage("familyThumbnailSize") private var thumbnailSize: Double = 128
	@State private var selection: Set<String> = []
	@State private var expandedLitters: Set<String> = []
	@State private var fullSize: RandomGenotype?
	@State private var pendingReject: PendingReject?
	@State private var errorMessage: String?
	@State private var scrollTarget: String?
	@FocusState private var isFocused: Bool

	private static let margin: CGFloat = 20

	private struct PendingReject: Identifiable {
		let id = UUID()
		let members: Set<String>
		let descendants: Int
	}

	private var family: Family { document.family }

	var body: some View {
		Group {
			if family.members.isEmpty {
				emptyState
			} else {
				lineage
			}
		}
		.frame(minWidth: 480, minHeight: 360)
#if os(macOS)
		.navigationSubtitle(family.members.isEmpty ? "" : "\(family.members.count) genotypes")
#endif
		.toolbar { toolbar }
		.sheet(item: $fullSize) { genotype in
			NavigationStack {
				FullSizeGenotypeView(genotype: genotype)
					.navigationTitle(genotype.name ?? "Full Size")
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Done") { fullSize = nil }
						}
					}
			}
		}
		.confirmationDialog(rejectTitle, isPresented: Binding(get: { pendingReject != nil }, set: { if !$0 { pendingReject = nil } }),
							presenting: pendingReject) { pending in
			Button("Reject \(pending.members.count + pending.descendants)", role: .destructive) {
				reject(pending.members, includingDescendants: true)
			}
		} message: { _ in
			Text("Rejected genotypes are removed from the family. You can undo this until you close the window.")
		}
		.alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
			Button("OK") { errorMessage = nil }
		} message: {
			Text(errorMessage ?? "")
		}
	}

	private var emptyState: some View {
		VStack(spacing: 12) {
			Text("This family is empty")
				.font(.title2)
			Text("Start it with a litter of \(family.settings.litterSize) random genotypes.")
				.foregroundStyle(.secondary)
			Button("New Random Litter") { addRandomLitter() }
				.keyboardShortcut(.defaultAction)
		}
		.padding()
	}

	// MARK: - Lineage

	private var lineage: some View {
		let metrics = metrics
		let layout = FamilyLayout(family: family, metrics: metrics, expandedLitters: expandedLitters)
		let byID = Dictionary(uniqueKeysWithValues: family.members.map { ($0.id, $0) })
		return ScrollViewReader { proxy in
			ScrollView([.horizontal, .vertical]) {
				ZStack(alignment: .topLeading) {
					connectors(layout)
					ForEach(Array(layout.cells.keys.sorted()), id: \.self) { id in
						if let cell = layout.cells[id], let member = byID[id] {
							cellView(member, cell: cell, hidden: layout.hiddenDescendants[id])
								.position(x: cell.frame.midX, y: cell.frame.midY)
								.id(id)
						}
					}
				}
				.frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
				.padding(Self.margin)
				.contentShape(Rectangle())
				.onTapGesture { selection = [] }
			}
			.onChange(of: scrollTarget) { _, target in
				guard let target else { return }
				withAnimation { proxy.scrollTo(target, anchor: .leading) }
				scrollTarget = nil
			}
		}
		.focusable()
		.focused($isFocused)
		.focusEffectDisabled()
		.onAppear { isFocused = true }
		.onKeyPress(.return) {
			breedSelection()
			return .handled
		}
#if os(macOS)
		.onDeleteCommand { rejectSelection() }
#endif
	}

	private var metrics: FamilyLayout.Metrics {
		var metrics = FamilyLayout.Metrics()
		metrics.cellSize = thumbnailSize
		metrics.chipSize = max(24, (thumbnailSize - 2 * metrics.chipSpacing) / 3)
		metrics.columnSpacing = max(32, thumbnailSize / 3)
		return metrics
	}

	private func connectors(_ layout: FamilyLayout) -> some View {
		Canvas { context, _ in
			for connector in layout.connectors {
				var path = Path()
				path.move(to: connector.from)
				let midX = (connector.from.x + connector.to.x) / 2
				path.addCurve(to: connector.to,
							  control1: CGPoint(x: midX, y: connector.from.y),
							  control2: CGPoint(x: midX, y: connector.to.y))
				context.stroke(path, with: .color(.secondary),
							   style: StrokeStyle(lineWidth: 1.5, dash: connector.isPrimary ? [] : [5, 4]))
			}
		}
		.frame(width: layout.size.width, height: layout.size.height)
		.allowsHitTesting(false)
	}

	private func cellView(_ member: Family.Member, cell: FamilyLayout.Cell, hidden: Int?) -> some View {
		let isSelected = selection.contains(member.id)
		let radius: CGFloat = cell.isChip ? 4 : 8
		return FamilyThumbnail(expression: member.expression, size: cell.frame.width)
			.frame(width: cell.frame.width, height: cell.frame.height)
			.clipShape(RoundedRectangle(cornerRadius: radius))
			.overlay {
				RoundedRectangle(cornerRadius: radius)
					.stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
			}
			.overlay(alignment: .topTrailing) {
				if member.starred && !cell.isChip {
					Image(systemName: "star.fill")
						.foregroundStyle(.yellow)
						.shadow(radius: 2)
						.padding(4)
				}
			}
			.overlay(alignment: .trailing) {
				if let hidden {
					Text("+\(hidden)")
						.font(.caption.bold())
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(.thinMaterial, in: Capsule())
						.offset(x: 24)
				}
			}
			.contentShape(Rectangle())
			.help(member.name.map { "\($0)\n\(member.expression)" } ?? member.expression)
			.onTapGesture(count: 2) { showFullSize(member) }
			.onTapGesture { select(member.id) }
			.contextMenu { contextMenu(for: member) }
	}

	@ViewBuilder
	private func contextMenu(for member: Family.Member) -> some View {
		let targets = selection.contains(member.id) ? selection : [member.id]
		Button(targets.count == 1 ? "Breed" : "Breed \(targets.count)") { breed(targets) }
		Button(member.starred ? "Unstar" : "Star") {
			document.setStarred(!member.starred, for: targets, undoManager: undoManager)
		}
		if family.hasBeenBredFrom(member.id) {
			Button(member.collapsed ? "Expand Branch" : "Collapse Branch") {
				document.setCollapsed(!member.collapsed, for: member.id, undoManager: undoManager)
			}
		}
		if expandedLitters.contains(member.litter) {
			Button("Shrink Unexplored Siblings") { expandedLitters.remove(member.litter) }
		} else if family.members(ofLitter: member.litter).contains(where: { family.hasBeenBredFrom($0.id) }) {
			Button("Show Siblings Full Size") { expandedLitters.insert(member.litter) }
		}
		Divider()
		Button("Show Full Size") { showFullSize(member) }
#if os(macOS)
		Button("Copy Expression") {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(member.expression, forType: .string)
		}
		Button("Save to Library…") {
			if let genotype = randomGenotype(member) { GenotypeFilePanels.save(genotype) }
		}
#endif
		Divider()
		Button(targets.count == 1 ? "Reject" : "Reject \(targets.count)", role: .destructive) { requestReject(targets) }
	}

	@ToolbarContentBuilder
	private var toolbar: some ToolbarContent {
		ToolbarItem {
			Slider(value: $thumbnailSize, in: 64...256) {
				Text("Size")
			}
			.frame(width: 120)
			.help("Thumbnail size")
		}
		ToolbarItem {
			Button("New Random Litter", systemImage: "dice") { addRandomLitter() }
				.help("Add a litter of random genotypes in the first column")
		}
		ToolbarItem {
			Button("Breed", systemImage: "arrow.triangle.branch") { breedSelection() }
				.disabled(selection.isEmpty)
				.help("Breed a litter from each selected genotype (Return)")
		}
		ToolbarItem {
			Button("Reject", systemImage: "trash") { rejectSelection() }
				.disabled(selection.isEmpty)
				.help("Remove the selected genotypes from the family (Delete)")
		}
	}

	// MARK: - Actions

	private func select(_ id: String) {
#if os(macOS)
		let modifiers = NSEvent.modifierFlags
		if modifiers.contains(.command) || modifiers.contains(.shift) {
			if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
			return
		}
#endif
		selection = [id]
	}

	private func addRandomLitter() {
		let litter = document.addRandomLitter(undoManager: undoManager)
		scrollTarget = family.members(ofLitter: litter.id).first?.id
	}

	private func breedSelection() {
		breed(selection)
	}

	private func breed(_ parents: Set<String>) {
		guard !parents.isEmpty else { return }
		do {
			let litters = try document.breed(parents, undoManager: undoManager)
			if let first = litters.first {
				scrollTarget = family.members(ofLitter: first.id).first?.id
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func rejectSelection() {
		requestReject(selection)
	}

	/// Rejects straight away, or asks first when that would take
	/// descendants with it.
	private func requestReject(_ members: Set<String>) {
		guard !members.isEmpty else { return }
		let descendants = family.descendants(of: members).count
		if descendants > 0 {
			pendingReject = PendingReject(members: members, descendants: descendants)
		} else {
			reject(members, includingDescendants: false)
		}
	}

	private var rejectTitle: String {
		guard let pendingReject else { return "" }
		let what = pendingReject.members.count == 1 ? "this genotype" : "these \(pendingReject.members.count) genotypes"
		return "Reject \(what) and \(pendingReject.descendants) descendant\(pendingReject.descendants == 1 ? "" : "s")?"
	}

	private func reject(_ members: Set<String>, includingDescendants: Bool) {
		do {
			let removed = try document.reject(members, includingDescendants: includingDescendants, undoManager: undoManager)
			selection.subtract(removed)
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func randomGenotype(_ member: Family.Member) -> RandomGenotype? {
		guard let node = try? ContentView.parser.parse(member.expression) else { return nil }
		return RandomGenotype(text: member.expression, node: node, name: member.name ?? member.id)
	}

	private func showFullSize(_ member: Family.Member) {
		if let genotype = randomGenotype(member) {
			fullSize = genotype
		} else {
			errorMessage = "\(member.id) doesn't parse with the nodes that are loaded now."
		}
	}
}

/// One member's render. Thumbnails are kept in memory by expression and
/// size, so relayout and scrolling don't re-render.
private struct FamilyThumbnail: View {
	let expression: String
	let size: CGFloat

	@State private var image: CGImage?
	@State private var failed = false

	@MainActor private static var cache: [String: CGImage] = [:]

	var body: some View {
		ZStack {
			Rectangle().fill(.quaternary)
			if let image {
				Image(decorative: image, scale: 1, orientation: .up)
					.resizable()
			} else if failed {
				Image(systemName: "exclamationmark.triangle")
					.foregroundStyle(.secondary)
			} else if size >= 64 {
				ProgressView().controlSize(.small)
			}
		}
		.task(id: key) { await render() }
	}

	/// Renders at the nearest of a few sizes, so dragging the size slider
	/// doesn't render every step.
	private var renderSize: Int {
		[48, 96, 160, 256].first { CGFloat($0) >= size } ?? 256
	}

	private var key: String { "\(renderSize) \(expression)" }

	private func render() async {
		if let cached = Self.cache[key] {
			image = cached
			return
		}
		guard let node = try? ContentView.parser.parse(expression) else {
			failed = true
			return
		}
		let renderer = NodeRenderer(node: node, evaluator: Evaluator(size: CGSize(width: renderSize, height: renderSize)))
		await renderer.render()
		guard !Task.isCancelled, let rendered = renderer.cgImage() else { return }
		Self.cache[key] = rendered
		image = rendered
	}
}
