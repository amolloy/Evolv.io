//
//  FamilyLayout.swift
//  ExpressionTree
//
//  Where the lineage view draws each member of a family: generations left
//  to right, each litter beside its parent, as a top-aligned tidy tree.
//  A member sits at the top of its band, and the band is as tall as the
//  member or everything bred from it, whichever is taller. Breeding only
//  adds space below and to the right, so nothing above or to the left of
//  the parent moves. Unexplored siblings in a litter someone has moved past
//  shrink to chips. See Documentation/EvolutionUI.md.
//

import CoreGraphics

public struct FamilyLayout: Equatable, Sendable {
	public struct Metrics: Equatable, Sendable {
		/// A full-size member's width and height, and a column's width.
		public var cellSize: CGFloat = 128
		public var chipSize: CGFloat = 40
		public var chipSpacing: CGFloat = 4
		/// Between members (or chip runs) in one litter.
		public var rowSpacing: CGFloat = 8
		/// Between two litters stacked in one column.
		public var litterSpacing: CGFloat = 24
		public var columnSpacing: CGFloat = 48
		/// Between a litter's members and the outline around them. Under
		/// half of `litterSpacing` and `columnSpacing`, so outlines never
		/// touch.
		public var litterPadding: CGFloat = 6

		public init() {}

		var chipsPerRow: Int {
			max(1, Int((cellSize + chipSpacing) / (chipSize + chipSpacing)))
		}
	}

	public struct Cell: Equatable, Sendable {
		public let frame: CGRect
		public let isChip: Bool
	}

	/// A line from a parent to a litter bred from it. A litter is drawn in
	/// its first parent's branch; a second parent (mating) gets a
	/// connector with `isPrimary` false, which the view dashes.
	public struct Connector: Equatable, Sendable {
		public let parent: String
		public let litter: String
		public let from: CGPoint
		public let to: CGPoint
		public let isPrimary: Bool
	}

	/// Visible members by id. Members inside a collapsed branch aren't here.
	public private(set) var cells: [String: Cell] = [:]
	/// Each visible litter's band: its column, from its first member's top
	/// to the bottom of everything bred from its members.
	public private(set) var litterFrames: [String: CGRect] = [:]
	/// The outline grouping each visible litter's members: around just
	/// its own cells, `litterPadding` out. Connectors end on its left edge.
	public private(set) var litterOutlines: [String: CGRect] = [:]
	public private(set) var connectors: [Connector] = []
	/// How many descendants each collapsed member is hiding.
	public private(set) var hiddenDescendants: [String: Int] = [:]
	public private(set) var size: CGSize = .zero

	/// - Parameters:
	///   - expandedLitters: litters to show every member of full size, even
	///     though someone in them has been bred from.
	///   - focus: when set (Show Path), only these members are full size;
	///     everyone else is a chip, `expandedLitters` notwithstanding.
	public init(family: Family, metrics: Metrics = Metrics(), expandedLitters: Set<String> = [], focus: Set<String>? = nil) {
		var builder = Builder(family: family, metrics: metrics, expandedLitters: expandedLitters, focus: focus)
		var y: CGFloat = 0
		for litter in family.litters where litter.parents.isEmpty {
			if y > 0 { y += metrics.litterSpacing }
			y = builder.place(litter, top: y)
		}
		builder.addSecondaryConnectors()
		cells = builder.cells
		litterFrames = builder.litterFrames
		litterOutlines = builder.litterOutlines
		connectors = builder.connectors
		hiddenDescendants = builder.hiddenDescendants
		let width = cells.values.map(\.frame.maxX).max() ?? 0
		let padding = family.litters.isEmpty ? 0 : metrics.litterPadding
		size = CGSize(width: width + padding, height: y + padding)
	}

	private struct Builder {
		let family: Family
		let metrics: Metrics
		let expandedLitters: Set<String>
		let focus: Set<String>?
		let generations: [String: Int]
		/// Litters by their first parent, in the order they were made.
		let littersByPrimaryParent: [String: [Family.Litter]]
		let bredFrom: Set<String>
		let membersByLitter: [String: [Family.Member]]

		var cells: [String: Cell] = [:]
		var litterFrames: [String: CGRect] = [:]
		var litterOutlines: [String: CGRect] = [:]
		var connectors: [Connector] = []
		var hiddenDescendants: [String: Int] = [:]

		init(family: Family, metrics: Metrics, expandedLitters: Set<String>, focus: Set<String>?) {
			self.family = family
			self.metrics = metrics
			self.expandedLitters = expandedLitters
			self.focus = focus
			generations = family.generations()
			littersByPrimaryParent = Dictionary(grouping: family.litters.filter { !$0.parents.isEmpty }, by: { $0.parents[0] })
			bredFrom = Set(family.litters.flatMap(\.parents))
			membersByLitter = Dictionary(grouping: family.members, by: \.litter).mapValues { $0.sorted { $0.index < $1.index } }
		}

		/// Lays out `litter` and everything bred from its members, starting
		/// at `top`. Returns the bottom of the lowest thing placed.
		mutating func place(_ litter: Family.Litter, top: CGFloat) -> CGFloat {
			let column = litter.parents.map { (generations[$0] ?? -1) + 1 }.max() ?? 0
			let x = CGFloat(column) * (metrics.cellSize + metrics.columnSpacing)
			let members = membersByLitter[litter.id] ?? []
			let showAll = expandedLitters.contains(litter.id) || !members.contains { bredFrom.contains($0.id) }

			var y = top
			var first = true
			var chipRun: [Family.Member] = []

			func startItem() {
				if !first { y += metrics.rowSpacing }
				first = false
			}

			for member in members {
				let isFull = focus.map { $0.contains(member.id) } ?? (showAll || bredFrom.contains(member.id) || member.starred)
				// Off the focused path, a member someone bred from is a chip
				// of its own, still at the top of its branch.
				let isBranchChip = !isFull && littersByPrimaryParent[member.id] != nil
				if isFull || isBranchChip {
					if !chipRun.isEmpty {
						startItem()
						y = placeChips(chipRun, x: x, top: y)
						chipRun = []
					}
					startItem()
					y = placeBranch(member, isChip: isBranchChip, x: x, top: y)
				} else {
					chipRun.append(member)
				}
			}
			if !chipRun.isEmpty {
				startItem()
				y = placeChips(chipRun, x: x, top: y)
			}

			litterFrames[litter.id] = CGRect(x: x, y: top, width: metrics.cellSize, height: y - top)
			let ownCells = members.compactMap { cells[$0.id]?.frame }
			if let first = ownCells.first {
				litterOutlines[litter.id] = ownCells.dropFirst().reduce(first) { $0.union($1) }
					.insetBy(dx: -metrics.litterPadding, dy: -metrics.litterPadding)
			}
			if let parent = litter.parents.first, let parentCell = cells[parent] {
				connectors.append(connector(from: parentCell.frame, parent: parent, to: litter.id, isPrimary: true))
			}
			return y
		}

		/// A member (full size, or a chip) at the top of its band, with its
		/// litters stacked beside it. Returns the band's bottom.
		private mutating func placeBranch(_ member: Family.Member, isChip: Bool, x: CGFloat, top: CGFloat) -> CGFloat {
			let size = isChip ? metrics.chipSize : metrics.cellSize
			cells[member.id] = Cell(frame: CGRect(x: x, y: top, width: size, height: size), isChip: isChip)
			var bottom = top + size
			let childLitters = littersByPrimaryParent[member.id] ?? []
			guard !childLitters.isEmpty else { return bottom }
			if member.collapsed {
				hiddenDescendants[member.id] = family.descendants(of: [member.id]).count
				return bottom
			}
			var childTop = top
			for litter in childLitters {
				let litterBottom = place(litter, top: childTop)
				bottom = max(bottom, litterBottom)
				childTop = litterBottom + metrics.litterSpacing
			}
			return bottom
		}

		/// Unexplored siblings as a wrapped grid of chips. Returns its bottom.
		private mutating func placeChips(_ members: [Family.Member], x: CGFloat, top: CGFloat) -> CGFloat {
			let perRow = metrics.chipsPerRow
			let step = metrics.chipSize + metrics.chipSpacing
			for (index, member) in members.enumerated() {
				let frame = CGRect(x: x + CGFloat(index % perRow) * step, y: top + CGFloat(index / perRow) * step,
								   width: metrics.chipSize, height: metrics.chipSize)
				cells[member.id] = Cell(frame: frame, isChip: true)
			}
			let rows = (members.count + perRow - 1) / perRow
			return top + CGFloat(rows) * step - metrics.chipSpacing
		}

		/// Dashed lines from second parents, once everything is placed.
		mutating func addSecondaryConnectors() {
			for litter in family.litters where litter.parents.count > 1 && litterFrames[litter.id] != nil {
				for parent in litter.parents.dropFirst() {
					if let parentCell = cells[parent] {
						connectors.append(connector(from: parentCell.frame, parent: parent, to: litter.id, isPrimary: false))
					}
				}
			}
		}

		private func connector(from parentFrame: CGRect, parent: String, to litterID: String, isPrimary: Bool) -> Connector {
			let litterFrame = litterFrames[litterID]!
			let outline = litterOutlines[litterID] ?? litterFrame
			return Connector(parent: parent, litter: litterID,
							 from: CGPoint(x: parentFrame.maxX, y: parentFrame.midY),
							 to: CGPoint(x: outline.minX, y: litterFrame.minY + min(metrics.cellSize, litterFrame.height) / 2),
							 isPrimary: isPrimary)
		}
	}
}
