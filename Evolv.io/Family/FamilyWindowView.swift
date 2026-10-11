//
//  FamilyWindowView.swift
//  Evolv.io
//
//  A family document's window: the lineage view, generations left to
//  right, laid out by FamilyLayout. Click selects (Command-click and
//  Shift-click add), Return breeds a litter from each selected member,
//  Shift-Return mates two (graft; crossover is on the menus),
//  Delete rejects, double-click shows full size, Show Path highlights a
//  member's ancestors (Escape clears it). Only cells near the
//  visible area exist, so only they render (see FamilyThumbnails). See
//  Documentation/EvolutionUI.md.
//

import SwiftUI
import ExpressionTree

struct FamilyWindowView: View {
	@ObservedObject var document: FamilyDocument
	/// Where it's saved, for the MCP family tools; nil until first saved.
	let fileURL: URL?

	@Environment(\.undoManager) private var undoManager
	@AppStorage("familyThumbnailSize") private var thumbnailSize: Double = 128
	/// Generations left to right, or top to bottom. For every family window.
	@AppStorage("familyOrientation") private var orientation = FamilyLayout.Orientation.horizontal
	@State private var selection: Set<String> = []
	/// The order members were added to the selection, so the first of two
	/// picked for mating is the primary parent.
	@State private var selectionOrder: [String] = []
	@State private var fullSize: RandomGenotype?
	@State private var pendingReject: PendingReject?
	@State private var errorMessage: String?
	@State private var savingMember: Family.Member?
	@State private var exportingImage: RandomGenotype?
	/// The member whose path the Export Path dialog is for.
	@State private var exportingPath: Family.Member?
#if os(macOS)
	@State private var pathExport = PathExport()
	@State private var showingExportProgress = false
#endif
	@State private var showingSettings = false
	/// The member whose line back to the roots is highlighted.
	@State private var pathMember: String?
	@State private var renaming: Family.Member?
	@State private var renameText = ""
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
		.onAppear { OpenFamilies.shared.register(document, fileURL: fileURL, undoManager: undoManager) }
		.onChange(of: fileURL) { _, url in OpenFamilies.shared.register(document, fileURL: url, undoManager: undoManager) }
		.onDisappear { OpenFamilies.shared.unregister(document) }
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
		.sheet(item: $exportingImage) { genotype in
			ExportImageSheet(genotype: genotype)
		}
#if os(macOS)
		.sheet(item: $exportingPath) { member in
			ExportPathSheet(items: pathItems(to: member.id),
							defaultBaseName: member.name ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Path",
							export: pathExport)
		}
		.onChange(of: pathExport.errorMessage) { _, message in
			if let message {
				errorMessage = message
				pathExport.errorMessage = nil
			}
		}
#endif
		.confirmationDialog(rejectTitle, isPresented: Binding(get: { pendingReject != nil }, set: { if !$0 { pendingReject = nil } }),
							presenting: pendingReject) { pending in
			Button("Reject \(pending.members.count + pending.descendants)", role: .destructive) {
				reject(pending.members, includingDescendants: true)
			}
		} message: { _ in
			Text("Rejected genotypes are removed from the family. You can undo this until you close the window.")
		}
		.alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { member in
			TextField("Name", text: $renameText)
			Button("Rename") {
				document.rename(member.id, to: renameText, undoManager: undoManager)
				renaming = nil
			}
			Button("Cancel", role: .cancel) { renaming = nil }
		} message: { _ in
			Text("Leave it empty to remove the name.")
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
			Text("Start it with a litter of \(family.settings.litterSize) random genotypes, or with genotypes from files or the clipboard.")
				.foregroundStyle(.secondary)
			HStack {
				Button("Paste Genotype") { pasteGenotype() }
#if os(macOS)
				Button("Open Genotype Files…") { openGenotypeFiles() }
#endif
				Button("New Random Litter") { addRandomLitter() }
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
	}

	// MARK: - Lineage

	private var lineage: some View {
		let path = highlightedPath
		let layout = FamilyLayout(family: family, metrics: metrics, focus: path, orientation: orientation)
		let byID = Dictionary(uniqueKeysWithValues: family.members.map { ($0.id, $0) })
		// Cells within a screen of the visible area, in content coordinates
		// (the layout's, offset by the margin).
		let margin = Self.margin
		let nearby = visibleRect.isEmpty ? CGRect(origin: .zero, size: CGSize(width: 2000, height: 2000))
			: visibleRect.insetBy(dx: -visibleRect.width / 2, dy: -visibleRect.height / 2)
		let shown = layout.cells.filter { nearby.intersects($0.value.frame.offsetBy(dx: margin, dy: margin)) }
		return ScrollView([.horizontal, .vertical]) {
			ZStack(alignment: .topLeading) {
				connectors(layout, path: path)
				ForEach(Array(shown.keys.sorted()), id: \.self) { id in
					if let cell = shown[id], let member = byID[id] {
						cellView(member, cell: cell, hidden: layout.hiddenDescendants[id])
							.opacity(path == nil || path!.contains(id) ? 1 : 0.5)
							.position(x: cell.frame.midX, y: cell.frame.midY)
					}
				}
				if path == nil {
					ForEach(family.litters.filter { layout.litterOutlines[$0.id] != nil && canShrink($0) }, id: \.id) { litter in
						siblingToggle(litter, outline: layout.litterOutlines[litter.id]!)
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
		.onKeyPress(.return, phases: .down) { press in
			if press.modifiers.contains(.shift) {
				mateSelection(.graft)
			} else {
				breedSelection()
			}
			return .handled
		}
		.onKeyPress(.escape) {
			guard pathMember != nil else { return .ignored }
			setPath(nil)
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

	/// Switching keeps the first selected member (or the first member) in
	/// place on screen.
	private var orientationBinding: Binding<FamilyLayout.Orientation> {
		Binding {
			orientation
		} set: { newValue in
			let before = currentLayout()
			orientation = newValue
			if let anchor = orderedSelection.first ?? family.members.first?.id {
				keepInPlace(anchor, before: before, revealing: nil)
			}
		}
	}

	/// Whether a litter has siblings that shrink to chips: someone in it
	/// has been bred from, and someone else hasn't (and isn't starred).
	private func canShrink(_ litter: Family.Litter) -> Bool {
		let members = family.members(ofLitter: litter.id)
		let bred = members.filter { family.hasBeenBredFrom($0.id) }
		return !bred.isEmpty && members.contains { !family.hasBeenBredFrom($0.id) && !$0.starred }
	}

	/// The expand/shrink button on a litter's outline, at its top right.
	private func siblingToggle(_ litter: Family.Litter, outline: CGRect) -> some View {
		Button {
			toggleExpanded(litter)
		} label: {
			Image(systemName: litter.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
				.font(.system(size: 10, weight: .semibold))
				.frame(width: 20, height: 20)
				.background(.regularMaterial, in: Circle())
				.overlay(Circle().stroke(.secondary.opacity(0.6), lineWidth: 1))
		}
		.buttonStyle(.plain)
		.help(litter.expanded ? "Shrink the unexplored siblings" : "Show every sibling full size")
		.position(x: outline.maxX, y: outline.minY)
	}

	/// Expands or shrinks a litter's siblings, keeping its first member in
	/// place on screen.
	private func toggleExpanded(_ litter: Family.Litter) {
		let before = currentLayout()
		document.setExpanded(!litter.expanded, litter: litter.id, undoManager: undoManager)
		if let anchor = family.members(ofLitter: litter.id).first?.id {
			keepInPlace(anchor, before: before, revealing: nil)
		}
	}

	/// The highlighted member and its ancestors, or nil when no path is
	/// shown.
	private var highlightedPath: Set<String>? {
		guard let pathMember, family.member(id: pathMember) != nil else { return nil }
		return family.ancestors(of: pathMember).union([pathMember])
	}

	/// Litter outlines and the lines from parents to litters, behind the
	/// cells. With a path shown, its litters and lines are drawn in the
	/// accent colour and the rest fade.
	private func connectors(_ layout: FamilyLayout, path: Set<String>?) -> some View {
		let pathLitters = path.map { ids in Set(family.members.filter { ids.contains($0.id) }.map(\.litter)) }
		return Canvas { context, _ in
			for (litter, outline) in layout.litterOutlines {
				let shape = Path(roundedRect: outline, cornerRadius: 10)
				let faded = pathLitters.map { !$0.contains(litter) } ?? false
				context.fill(shape, with: .color(.primary.opacity(faded ? 0.02 : 0.05)))
				context.stroke(shape, with: .color(.secondary.opacity(faded ? 0.25 : 0.6)), lineWidth: 1)
			}
			for connector in layout.connectors {
				var line = Path()
				line.move(to: connector.from)
				if layout.orientation == .vertical {
					let midY = (connector.from.y + connector.to.y) / 2
					line.addCurve(to: connector.to,
								  control1: CGPoint(x: connector.from.x, y: midY),
								  control2: CGPoint(x: connector.to.x, y: midY))
				} else {
					let midX = (connector.from.x + connector.to.x) / 2
					line.addCurve(to: connector.to,
								  control1: CGPoint(x: midX, y: connector.from.y),
								  control2: CGPoint(x: midX, y: connector.to.y))
				}
				let onPath = path.map { $0.contains(connector.parent) && pathLitters!.contains(connector.litter) }
				let isMating = family.litter(id: connector.litter)?.parents.count == 2
				let lineColor: Color = isMating ? Self.parentColor(connector.isPrimary ? 0 : 1) : .secondary
				let color: Color = onPath == true ? (isMating ? lineColor : .accentColor) : lineColor.opacity(onPath == false ? 0.3 : 1)
				context.stroke(line, with: .color(color),
							   style: StrokeStyle(lineWidth: onPath == true ? 2.5 : 1.5, dash: connector.isPrimary ? [] : [5, 4]))
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
			.overlay(alignment: .topLeading) {
				if let base = baseParentPosition(member) {
					Circle()
						.fill(Self.parentColor(base))
						.overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
						.frame(width: cell.isChip ? 7 : 11, height: cell.isChip ? 7 : 11)
						.padding(cell.isChip ? 2 : 5)
						.help(base == 0 ? "Built on the first parent" : "Built on the second parent")
				}
			}
			.overlay(alignment: .topTrailing) {
				if member.starred && !cell.isChip {
					Image(systemName: "star.fill")
						.foregroundStyle(.yellow)
						.shadow(radius: 2)
						.padding(4)
				}
			}
			.overlay(alignment: .bottom) {
				if let name = member.name, !cell.isChip {
					Text(name)
						.font(.caption)
						.lineLimit(1)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.frame(maxWidth: .infinity)
						.background(.thinMaterial)
						.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
				}
			}
			.overlay(alignment: orientation == .vertical ? .bottom : .trailing) {
				if let hidden {
					Text("+\(hidden)")
						.font(.caption.bold())
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(.thinMaterial, in: Capsule())
						.offset(x: orientation == .vertical ? 0 : 24, y: orientation == .vertical ? 14 : 0)
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
		if targets.count == 2 {
			Button("Mate (Graft)") { mateSelection(.graft) }
			Button("Mate (Crossover)") { mateSelection(.crossover) }
		}
		Button(member.starred ? "Unstar" : "Star") {
			document.setStarred(!member.starred, for: targets, undoManager: undoManager)
		}
		Button("Rename…") {
			renameText = member.name ?? ""
			renaming = member
		}
		if pathMember == member.id {
			Button("Hide Path") { setPath(nil) }
		} else {
			Button("Show Path") { setPath(member.id) }
		}
		if family.hasBeenBredFrom(member.id) {
			Button(member.collapsed ? "Expand Branch" : "Collapse Branch") {
				document.setCollapsed(!member.collapsed, for: member.id, undoManager: undoManager)
			}
		}
		if let litter = family.litter(id: member.litter), canShrink(litter) {
			Button(litter.expanded ? "Shrink Siblings" : "Show Siblings Full Size") { toggleExpanded(litter) }
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
		Button("Export Image…") {
			if let genotype = randomGenotype(member) { exportingImage = genotype }
		}
		Button("Export Path…") { exportingPath = member }
			.disabled(pathExport.isRunning)
#else
		Button("Save to Library…") { savingMember = member }
#endif
		Divider()
		Button(targets.count == 1 ? "Reject" : "Reject \(targets.count)", role: .destructive) { requestReject(targets) }
	}

	@ToolbarContentBuilder
	private var toolbar: some ToolbarContent {
#if os(macOS)
		if pathExport.isRunning {
			ToolbarItem {
				Button {
					showingExportProgress = true
				} label: {
					ProgressView(value: pathExport.fraction)
						.progressViewStyle(.circular)
						.controlSize(.small)
				}
				.help("Exporting path: \(pathExport.done) of \(pathExport.total)")
				.popover(isPresented: $showingExportProgress) {
					VStack(alignment: .leading, spacing: 8) {
						Text("Exporting path to \(pathExport.folderName)")
							.font(.headline)
						ProgressView(value: pathExport.fraction) {
							Text("\(pathExport.done) of \(pathExport.total) images")
						}
						HStack {
							Spacer()
							Button("Stop") { pathExport.stop() }
						}
					}
					.padding()
					.frame(width: 280)
				}
			}
		}
#endif
		ToolbarItem {
			Slider(value: $thumbnailSize, in: 64...256) {
				Text("Size")
			}
			.frame(width: 120)
			.help("Thumbnail size")
		}
		ToolbarItem {
			Picker("Orientation", selection: orientationBinding) {
				Label("Generations Left to Right", systemImage: "arrow.right.square").tag(FamilyLayout.Orientation.horizontal)
				Label("Generations Top to Bottom", systemImage: "arrow.down.square").tag(FamilyLayout.Orientation.vertical)
			}
			.pickerStyle(.segmented)
			.labelStyle(.iconOnly)
			.help("Run generations left to right or top to bottom")
		}
		ToolbarItem {
			Button("Family Settings", systemImage: "slider.horizontal.3") { showingSettings = true }
				.help("Litter size, mutation rate and depth for new litters")
				.popover(isPresented: $showingSettings) {
					FamilySettingsView(document: document)
				}
		}
		ToolbarItem {
			Menu("Add Roots", systemImage: "plus") {
				Button("New Random Litter") { addRandomLitter() }
				Button("Paste Genotype") { pasteGenotype() }
#if os(macOS)
				Button("Open Genotype Files…") { openGenotypeFiles() }
#endif
			} primaryAction: {
				addRandomLitter()
			}
			.help("Add a litter of random genotypes, genotype files or a copied genotype in the first column")
		}
		ToolbarItem {
			Button("Breed", systemImage: "arrow.triangle.branch") { breedSelection() }
				.disabled(selection.isEmpty)
				.help("Breed a litter from each selected genotype (Return)")
		}
		ToolbarItem {
			Menu("Mate", systemImage: "arrow.triangle.merge") {
				Button("Graft") { mateSelection(.graft) }
				Button("Crossover") { mateSelection(.crossover) }
			} primaryAction: {
				mateSelection(.graft)
			}
			.disabled(selection.count != 2)
			.help("Mate the two selected genotypes (Shift-Return grafts; crossover is in the menu)")
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
			if selection.contains(id) {
				selection.remove(id)
			} else {
				selection.insert(id)
				selectionOrder.removeAll { $0 == id }
				selectionOrder.append(id)
			}
			return
		}
#endif
		selection = [id]
		selectionOrder = [id]
	}

	/// The selection in the order it was made.
	private var orderedSelection: [String] {
		selectionOrder.filter(selection.contains) + selection.subtracting(selectionOrder).sorted()
	}

	/// The two parents' colours in a mating litter: lines from the first
	/// and second parent, and the dot on each child showing which one it's
	/// built on.
	static func parentColor(_ position: Int) -> Color {
		position == 0 ? .blue : .orange
	}

	/// 0 or 1 for a mating child built on its litter's first or second
	/// parent, nil for anyone else.
	private func baseParentPosition(_ member: Family.Member) -> Int? {
		guard let base = member.base, let litter = family.litter(id: member.litter), litter.parents.count == 2 else { return nil }
		return litter.parents.firstIndex(of: base)
	}

	/// Mates the two selected members, the first selected as the primary
	/// parent, keeping it in place on screen like breeding does.
	private func mateSelection(_ method: MatingMethod) {
		let parents = orderedSelection
		guard parents.count == 2 else {
			errorMessage = "Select exactly two genotypes to mate."
			return
		}
		let before = currentLayout()
		do {
			let litter = try document.mate(parents[0], parents[1], method: method, undoManager: undoManager)
			keepInPlace(parents[0], before: before, revealing: litter.id)
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func addRandomLitter() {
		let litter = document.addRandomLitter(undoManager: undoManager)
		// Root litters go at the bottom of the first column.
		let layout = currentLayout()
		if let frame = layout.litterFrames[litter.id] {
			scrollPosition.scrollTo(point: CGPoint(x: max(0, frame.minX), y: max(0, frame.minY)))
		}
	}

#if os(macOS)
	/// `memberID` and its ancestors, oldest generation first, then in
	/// family order.
	private func pathItems(to memberID: String) -> [ExportPathSheet.Item] {
		let ids = family.ancestors(of: memberID).union([memberID])
		let generations = family.generations()
		return family.members
			.filter { ids.contains($0.id) }
			.map { ExportPathSheet.Item(member: $0, generation: generations[$0.id] ?? 0) }
			.enumerated()
			.sorted { ($0.element.generation, $0.offset) < ($1.element.generation, $1.offset) }
			.map(\.element)
	}
#endif

	private func currentLayout() -> FamilyLayout {
		FamilyLayout(family: family, metrics: metrics, focus: highlightedPath, orientation: orientation)
	}

	/// Shows (or with nil, hides) the path to `memberID`. Everything off
	/// the path changes size, so the member keeps its place on screen.
	private func setPath(_ memberID: String?) {
		let anchor = memberID ?? pathMember
		let before = currentLayout()
		pathMember = memberID
		if let anchor {
			keepInPlace(anchor, before: before, revealing: nil)
		}
	}

#if os(macOS)
	/// Adds `.evolvgenotype` files, or images exported with their genotype,
	/// as one root litter, each member named for its file.
	private func openGenotypeFiles() {
		GenotypeFilePanels.openSeveral(title: "Add Genotypes to Family") { opened, urls in
			let source = urls.count == 1 ? "file:\(urls[0].lastPathComponent)" : "files"
			addRoots(expressions: opened.map(\.expression), names: opened.map(\.name), source: source)
		}
	}
#endif

	/// A root litter of `expressions`, scrolled to and selected.
	private func addRoots(expressions: [String], names: [String?] = [], source: String) {
		do {
			let litter = try document.addSeedLitter(expressions: expressions, names: names, source: source, undoManager: undoManager)
			let layout = currentLayout()
			if let frame = layout.litterFrames[litter.id] {
				scrollPosition.scrollTo(point: CGPoint(x: max(0, frame.minX), y: max(0, frame.minY)))
			}
			let ids = family.members(ofLitter: litter.id).map(\.id)
			selection = Set(ids)
			selectionOrder = ids
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Adds the genotype on the clipboard as a root of its own.
	private func pasteGenotype() {
#if os(macOS)
		let text = NSPasteboard.general.string(forType: .string)
#else
		let text = UIPasteboard.general.string
#endif
		let expression = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard !expression.isEmpty else {
			errorMessage = "There's no text on the clipboard."
			return
		}
		do {
			_ = try ContentView.parser.parse(expression)
		} catch {
			errorMessage = "The clipboard doesn't hold a genotype the loaded nodes can read: \(error.localizedDescription)"
			return
		}
		addRoots(expressions: [expression], source: "pasted")
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
		let before = currentLayout()
		let litters: [Family.Litter]
		do {
			litters = try document.breed(parents, undoManager: undoManager)
		} catch {
			errorMessage = error.localizedDescription
			return
		}
		if let anchor {
			keepInPlace(anchor, before: before, revealing: litters.first?.id)
		}
	}

	/// Scrolls so `anchor` is where it was in `before`, then right if the
	/// litter `revealing` is off screen.
	private func keepInPlace(_ anchor: String, before: FamilyLayout, revealing litterID: String?) {
		let after = currentLayout()
		let visibleRect = scrollTracker.visibleRect
		guard !visibleRect.isEmpty, let old = before.cells[anchor]?.frame, let new = after.cells[anchor]?.frame else { return }
		var offset = CGPoint(x: visibleRect.minX + new.minX - old.minX, y: visibleRect.minY + new.minY - old.minY)
		// The next generation is to the right, or below.
		if let litterID, let litterFrame = after.litterOutlines[litterID] ?? after.litterFrames[litterID] {
			if after.orientation == .vertical {
				let bottom = litterFrame.maxY + 2 * Self.margin
				if bottom > offset.y + visibleRect.height {
					offset.y = bottom - visibleRect.height
				}
			} else {
				let right = litterFrame.maxX + 2 * Self.margin
				if right > offset.x + visibleRect.width {
					offset.x = right - visibleRect.width
				}
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

/// One member's render, from FamilyThumbnails, scaled to the cell.
private struct FamilyThumbnail: View {
	let expression: String
	let size: CGFloat

	@State private var image: CGImage?
	@State private var failed = false

	init(expression: String, size: CGFloat) {
		self.expression = expression
		self.size = size
		_image = State(initialValue: FamilyThumbnails.shared.memoryThumbnail(for: expression))
	}

	var body: some View {
		ZStack {
			Rectangle().fill(.quaternary)
			if let image {
				Image(decorative: image, scale: 1, orientation: .up)
					.resizable()
					.interpolation(.high)
			} else if failed {
				Image(systemName: "exclamationmark.triangle")
					.foregroundStyle(.secondary)
			} else if size >= 64 {
				ProgressView().controlSize(.small)
			}
		}
		.task(id: expression) {
			guard image == nil else { return }
			switch await FamilyThumbnails.shared.thumbnail(for: expression) {
				case .image(let rendered) where !Task.isCancelled:
					image = rendered
				case .unreadable where !Task.isCancelled:
					failed = true
				default:
					break
			}
		}
	}
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
