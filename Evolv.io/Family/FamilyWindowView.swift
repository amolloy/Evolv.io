//
//  FamilyWindowView.swift
//  Evolv.io
//
//  A family document's window: the lineage view, generations left to
//  right, laid out by FamilyLayout. Click selects (Command-click and
//  Shift-click add), Return breeds a litter from each selected member,
//  Delete rejects, double-click shows full size. Only cells near the
//  visible area exist, so only they render (see FamilyThumbnails). See
//  Documentation/EvolutionUI.md.
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
	@State private var savingMember: Family.Member?
	@State private var showingSettings = false
	@State private var scrollPosition = ScrollPosition()
	/// The visible part of the scroll view's content, padding included,
	/// updated only every quarter screen of scrolling, since it decides
	/// which cells exist.
	@State private var visibleRect = CGRect.zero
	/// The exact visible rect, which changes every frame of a scroll
	/// without redrawing anything.
	@State private var scrollTracker = ScrollTracker()

	private final class ScrollTracker {
		var visibleRect = CGRect.zero
	}
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
		.sheet(item: $savingMember) { member in
			SaveGenotypeSheet(expression: member.expression)
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
		let layout = FamilyLayout(family: family, metrics: metrics, expandedLitters: expandedLitters)
		let byID = Dictionary(uniqueKeysWithValues: family.members.map { ($0.id, $0) })
		// Cells within a screen of the visible area, in content coordinates
		// (the layout's, offset by the margin).
		let margin = Self.margin
		let nearby = visibleRect.isEmpty ? CGRect(origin: .zero, size: CGSize(width: 2000, height: 2000))
			: visibleRect.insetBy(dx: -visibleRect.width / 2, dy: -visibleRect.height / 2)
		let shown = layout.cells.filter { nearby.intersects($0.value.frame.offsetBy(dx: margin, dy: margin)) }
		return ScrollView([.horizontal, .vertical]) {
			ZStack(alignment: .topLeading) {
				connectors(layout)
				ForEach(Array(shown.keys.sorted()), id: \.self) { id in
					if let cell = shown[id], let member = byID[id] {
						cellView(member, cell: cell, hidden: layout.hiddenDescendants[id])
							.position(x: cell.frame.midX, y: cell.frame.midY)
					}
				}
			}
			.frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
			.padding(margin)
			.contentShape(Rectangle())
			.onTapGesture { selection = [] }
		}
		.scrollPosition($scrollPosition)
		.onScrollGeometryChange(for: CGRect.self, of: \.visibleRect) { _, rect in
			scrollTracker.visibleRect = rect
			if abs(rect.minX - visibleRect.minX) > rect.width / 4 || abs(rect.minY - visibleRect.minY) > rect.height / 4
				|| rect.size != visibleRect.size {
				visibleRect = rect
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

	/// Litter outlines and the lines from parents to litters, behind the
	/// cells.
	private func connectors(_ layout: FamilyLayout) -> some View {
		Canvas { context, _ in
			for outline in layout.litterOutlines.values {
				let shape = Path(roundedRect: outline, cornerRadius: 10)
				context.fill(shape, with: .color(.primary.opacity(0.05)))
				context.stroke(shape, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
			}
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
#else
		Button("Save to Library…") { savingMember = member }
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
			Button("Family Settings", systemImage: "slider.horizontal.3") { showingSettings = true }
				.help("Litter size, mutation rate and depth for new litters")
				.popover(isPresented: $showingSettings) {
					FamilySettingsView(document: document)
				}
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
		// Root litters go at the bottom of the first column.
		let layout = FamilyLayout(family: family, metrics: metrics, expandedLitters: expandedLitters)
		if let frame = layout.litterFrames[litter.id] {
			scrollPosition.scrollTo(point: CGPoint(x: 0, y: max(0, frame.minY)))
		}
	}

	private func breedSelection() {
		breed(selection)
	}

	/// Breeds, keeping the first parent where it was on screen (the first
	/// breed from a litter shrinks its siblings, which moves the parent),
	/// then scrolling right if the new litter is off screen.
	private func breed(_ parents: Set<String>) {
		guard !parents.isEmpty else { return }
		let anchor = family.members.map(\.id).first(where: parents.contains)
		let before = FamilyLayout(family: family, metrics: metrics, expandedLitters: expandedLitters)
		let litters: [Family.Litter]
		do {
			litters = try document.breed(parents, undoManager: undoManager)
		} catch {
			errorMessage = error.localizedDescription
			return
		}
		let after = FamilyLayout(family: family, metrics: metrics, expandedLitters: expandedLitters)
		let visibleRect = scrollTracker.visibleRect
		guard !visibleRect.isEmpty, let anchor, let old = before.cells[anchor]?.frame, let new = after.cells[anchor]?.frame else { return }
		var offset = CGPoint(x: visibleRect.minX, y: visibleRect.minY + new.minY - old.minY)
		if let first = litters.first, let litterFrame = after.litterFrames[first.id] {
			let right = litterFrame.maxX + 2 * Self.margin
			if right > offset.x + visibleRect.width {
				offset.x = right - visibleRect.width
			}
		}
		offset.x = max(0, offset.x)
		offset.y = max(0, offset.y)
		scrollPosition.scrollTo(point: offset)
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

/// One member's render, from FamilyThumbnails.
private struct FamilyThumbnail: View {
	let expression: String
	let size: CGFloat

	@State private var image: CGImage?
	@State private var failed = false

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
		.task(id: key) {
			switch await FamilyThumbnails.shared.thumbnail(for: expression, size: renderSize) {
				case .image(let rendered) where !Task.isCancelled:
					image = rendered
				case .unreadable where !Task.isCancelled:
					failed = true
				default:
					break
			}
		}
	}

	/// Renders at the nearest of a few sizes, so dragging the size slider
	/// doesn't render every step.
	private var renderSize: Int {
		[48, 96, 160, 256].first { CGFloat($0) >= size } ?? 256
	}

	private var key: String { "\(renderSize) \(expression)" }
}

/// The family's defaults for new litters. Changes are undoable and don't
/// touch litters already made.
private struct FamilySettingsView: View {
	@ObservedObject var document: FamilyDocument

	@Environment(\.undoManager) private var undoManager

	var body: some View {
		Form {
			Stepper("Litter size: \(document.family.settings.litterSize)",
					value: binding(\.litterSize, "Change Litter Size"), in: 1...60)
			Stepper("Mutations per child: \(document.family.settings.mutationsPerChild.formatted())",
					value: binding(\.mutationsPerChild, "Change Mutation Rate"), in: 0.25...8, step: 0.25)
			Stepper("Depth of new material: \(document.family.settings.maxDepth)",
					value: binding(\.maxDepth, "Change Depth"), in: 1...20)
		}
		.padding()
		.frame(width: 300)
	}

	private func binding<Value>(_ keyPath: WritableKeyPath<Family.Settings, Value>, _ actionName: String) -> Binding<Value> {
		Binding {
			document.family.settings[keyPath: keyPath]
		} set: { newValue in
			document.change(actionName, undoManager: undoManager) { $0.settings[keyPath: keyPath] = newValue }
		}
	}
}
