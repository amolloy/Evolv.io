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
	/// Each visible litter's block.
	public private(set) var litterFrames: [String: CGRect] = [:]
	public private(set) var connectors: [Connector] = []
	/// How many descendants each collapsed member is hiding.
	public private(set) var hiddenDescendants: [String: Int] = [:]
	public private(set) var size: CGSize = .zero

	/// - Parameter expandedLitters: litters to show every member of full
	///   size, even though someone in them has been bred from.
	public init(family: Family, metrics: Metrics = Metrics(), expandedLitters: Set<String> = []) {
		var builder = Builder(family: family, metrics: metrics, expandedLitters: expandedLitters)
		var y: CGFloat = 0
		for litter in family.litters where litter.parents.isEmpty {
			if y > 0 { y += metrics.litterSpacing }
			y = builder.place(litter, top: y)
		}
		builder.addSecondaryConnectors()
		cells = builder.cells
		litterFrames = builder.litterFrames
		connectors = builder.connectors
		hiddenDescendants = builder.hiddenDescendants
		let width = cells.values.map(\.frame.maxX).max() ?? 0
		size = CGSize(width: width, height: y)
	}

	private struct Builder {
		let family: Family
		let metrics: Metrics
		let expandedLitters: Set<String>
		let generations: [String: Int]
		/// Litters by their first parent, in the order they were made.
		let littersByPrimaryParent: [String: [Family.Litter]]
		let bredFrom: Set<String>

		var cells: [String: Cell] = [:]
		var litterFrames: [String: CGRect] = [:]
		var connectors: [Connector] = []
		var hiddenDescendants: [String: Int] = [:]

		init(family: Family, metrics: Metrics, expandedLitters: Set<String>) {
			self.family = family
			self.metrics = metrics
			self.expandedLitters = expandedLitters
			generations = family.generations()
			littersByPrimaryParent = Dictionary(grouping: family.litters.filter { !$0.parents.isEmpty }, by: { $0.parents[0] })
			bredFrom = Set(family.litters.flatMap(\.parents))
		}

		/// Lays out `litter` and everything bred from its members, starting
		/// at `top`. Returns the bottom of the lowest thing placed.
		mutating func place(_ litter: Family.Litter, top: CGFloat) -> CGFloat {
			let column = family.generation(ofLitter: litter.id, generations: generations)
			let x = CGFloat(column) * (metrics.cellSize + metrics.columnSpacing)
			let members = family.members(ofLitter: litter.id)
			let showAll = expandedLitters.contains(litter.id) || !members.contains { bredFrom.contains($0.id) }

			var y = top
			var first = true
			var chipRun: [Family.Member] = []

			func startItem() {
				if !first { y += metrics.rowSpacing }
				first = false
			}

			for member in members {
				if showAll || bredFrom.contains(member.id) || member.starred {
					if !chipRun.isEmpty {
						startItem()
						y = placeChips(chipRun, x: x, top: y)
						chipRun = []
					}
					startItem()
					y = placeFull(member, x: x, top: y)
				} else {
					chipRun.append(member)
				}
			}
			if !chipRun.isEmpty {
				startItem()
				y = placeChips(chipRun, x: x, top: y)
			}

			litterFrames[litter.id] = CGRect(x: x, y: top, width: metrics.cellSize, height: y - top)
			if let parent = litter.parents.first, let parentCell = cells[parent] {
				connectors.append(connector(from: parentCell.frame, parent: parent, to: litter.id, isPrimary: true))
			}
			return y
		}

		/// A full-size member at the top of its band, with its litters
		/// stacked beside it. Returns the band's bottom.
		private mutating func placeFull(_ member: Family.Member, x: CGFloat, top: CGFloat) -> CGFloat {
			cells[member.id] = Cell(frame: CGRect(x: x, y: top, width: metrics.cellSize, height: metrics.cellSize), isChip: false)
			var bottom = top + metrics.cellSize
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
			return Connector(parent: parent, litter: litterID,
							 from: CGPoint(x: parentFrame.maxX, y: parentFrame.midY),
							 to: CGPoint(x: litterFrame.minX, y: litterFrame.minY + min(metrics.cellSize, litterFrame.height) / 2),
							 isPrimary: isPrimary)
		}
	}
}
