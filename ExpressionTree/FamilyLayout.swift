//
//  FamilyLayout.swift
//  ExpressionTree
//
//  Where the lineage view draws each member of a family: generations left
//  to right, as a tidy tree. Each litter is centred on its parent, and
//  branches are packed by their outlines column by column (Reingold and
//  Tilford's idea): two branches only push apart where they'd overlap in
//  the same column, so a tall litter far to the right doesn't push down
//  siblings near the roots, and a chain of single picks stays level
//  instead of drifting. Unexplored siblings in a litter someone has moved
//  past shrink to chips, in place. With `.vertical` orientation everything
//  is transposed: generations top to bottom, siblings side by side. See
//  Documentation/EvolutionUI.md.
//

import CoreGraphics

public struct FamilyLayout: Equatable, Sendable {
	/// Which way generations run.
	public enum Orientation: String, CaseIterable, Sendable {
		/// Left to right, siblings stacked vertically.
		case horizontal
		/// Top to bottom, siblings side by side.
		case vertical
	}

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
	/// Each visible litter's own cells, bounded.
	public private(set) var litterFrames: [String: CGRect] = [:]
	/// The outline grouping each visible litter's members: around just
	/// its own cells, `litterPadding` out. Connectors end on its left edge,
	/// level with the parent where they can.
	public private(set) var litterOutlines: [String: CGRect] = [:]
	public private(set) var connectors: [Connector] = []
	/// How many descendants each collapsed member is hiding.
	public private(set) var hiddenDescendants: [String: Int] = [:]
	public private(set) var size: CGSize = .zero
	public private(set) var orientation: Orientation = .horizontal

	/// - Parameters:
	///   - expandedLitters: more litters to show every member of full size,
	///     even though someone in them has been bred from, besides those
	///     marked `expanded` in the family.
	///   - focus: when set (Show Path), only these members are full size;
	///     everyone else is a chip, `expandedLitters` notwithstanding.
	///   - orientation: `.vertical` transposes the whole layout. Connectors
	///     then run from a parent's bottom edge to the top of its litter.
	public init(family: Family, metrics: Metrics = Metrics(), expandedLitters: Set<String> = [], focus: Set<String>? = nil,
				orientation: Orientation = .horizontal) {
		let builder = Builder(family: family, metrics: metrics, expandedLitters: expandedLitters, focus: focus)
		var roots = Subtree()
		for litter in family.litters where litter.parents.isEmpty {
			roots.stack(builder.layout(litter), separation: { _ in metrics.litterSpacing })
		}
		// The topmost cell at y = 0.
		roots.shift(-(roots.cells.map(\.frame.minY).min() ?? 0))

		var ownCells: [String: [CGRect]] = [:]
		for cell in roots.cells {
			cells[cell.id] = Cell(frame: cell.frame, isChip: cell.isChip)
			ownCells[cell.litter, default: []].append(cell.frame)
		}
		for (litter, frames) in ownCells {
			let bounds = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
			litterFrames[litter] = bounds
			litterOutlines[litter] = bounds.insetBy(dx: -metrics.litterPadding, dy: -metrics.litterPadding)
		}
		hiddenDescendants = roots.hidden
		for litter in family.litters where litterOutlines[litter.id] != nil {
			for (position, parent) in litter.parents.enumerated() {
				guard let parentFrame = cells[parent]?.frame, let outline = litterOutlines[litter.id] else { continue }
				let inset = min(metrics.litterPadding + metrics.chipSize / 2, outline.height / 2)
				let y = min(max(parentFrame.midY, outline.minY + inset), outline.maxY - inset)
				connectors.append(Connector(parent: parent, litter: litter.id,
											from: CGPoint(x: parentFrame.maxX, y: parentFrame.midY),
											to: CGPoint(x: outline.minX, y: y), isPrimary: position == 0))
			}
		}
		let padding = family.litters.isEmpty ? 0 : metrics.litterPadding
		size = CGSize(width: (cells.values.map(\.frame.maxX).max() ?? 0) + padding,
					  height: (cells.values.map(\.frame.maxY).max() ?? 0) + padding)
		if orientation == .vertical {
			transpose()
		}
	}

	/// Swaps x and y everywhere. Cells are square, so a member's frame
	/// keeps its size; a chip grid's rows become columns.
	private mutating func transpose() {
		func flip(_ rect: CGRect) -> CGRect { CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width) }
		func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.y, y: point.x) }
		cells = cells.mapValues { Cell(frame: flip($0.frame), isChip: $0.isChip) }
		litterFrames = litterFrames.mapValues(flip)
		litterOutlines = litterOutlines.mapValues(flip)
		connectors = connectors.map {
			Connector(parent: $0.parent, litter: $0.litter, from: flip($0.from), to: flip($0.to), isPrimary: $0.isPrimary)
		}
		size = CGSize(width: size.height, height: size.width)
		orientation = orientation == .horizontal ? .vertical : .horizontal
	}

	/// A laid-out piece of the tree (a litter, a member and its branch, a
	/// run of chips) in its own coordinates, with its contour: the top and
	/// bottom of its cells in each column it reaches.
	private struct Subtree {
		struct PlacedCell {
			let id: String
			let litter: String
			var frame: CGRect
			let isChip: Bool
		}

		var cells: [PlacedCell] = []
		var contour: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
		var hidden: [String: Int] = [:]

		var isEmpty: Bool { cells.isEmpty }

		mutating func add(_ cell: PlacedCell, column: Int) {
			cells.append(cell)
			let extent = contour[column]
			contour[column] = (min(extent?.top ?? cell.frame.minY, cell.frame.minY),
							   max(extent?.bottom ?? cell.frame.maxY, cell.frame.maxY))
		}

		mutating func shift(_ dy: CGFloat) {
			guard dy != 0 else { return }
			for index in cells.indices {
				cells[index].frame.origin.y += dy
			}
			contour = contour.mapValues { ($0.top + dy, $0.bottom + dy) }
		}

		mutating func merge(_ other: Subtree) {
			cells += other.cells
			for (column, extent) in other.contour {
				let mine = contour[column]
				contour[column] = (min(mine?.top ?? extent.top, extent.top), max(mine?.bottom ?? extent.bottom, extent.bottom))
			}
			hidden.merge(other.hidden) { first, _ in first }
		}

		/// Moves `next` as high as it can go below everything here, keeping
		/// `separation(column)` between them in every column they share, and
		/// merges it in.
		mutating func stack(_ next: Subtree, separation: (Int) -> CGFloat) {
			var next = next
			guard !isEmpty else {
				merge(next)
				return
			}
			let shared = Set(contour.keys).intersection(next.contour.keys)
			let offset: CGFloat
			if shared.isEmpty {
				// Nothing to pack against: below everything.
				let bottom = contour.values.map(\.bottom).max()!
				let top = next.contour.values.map(\.top).min() ?? 0
				offset = bottom + separation(-1) - top
			} else {
				offset = shared.map { contour[$0]!.bottom + separation($0) - next.contour[$0]!.top }.max()!
			}
			next.shift(offset)
			merge(next)
		}
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

		private func x(ofColumn column: Int) -> CGFloat {
			CGFloat(column) * (metrics.cellSize + metrics.columnSpacing)
		}

		/// A litter and everything bred from its members: its members in
		/// litter order down its column, each member's branch packed
		/// against the ones above.
		func layout(_ litter: Family.Litter) -> Subtree {
			let column = litter.parents.map { (generations[$0] ?? -1) + 1 }.max() ?? 0
			let members = membersByLitter[litter.id] ?? []
			let showAll = litter.expanded || expandedLitters.contains(litter.id) || !members.contains { bredFrom.contains($0.id) }
			// Members of one litter sit `rowSpacing` apart in its column;
			// their branches are other litters, `litterSpacing` apart.
			let separation: (Int) -> CGFloat = { $0 == column ? metrics.rowSpacing : metrics.litterSpacing }

			var result = Subtree()
			var chipRun: [Family.Member] = []
			func flushChips() {
				guard !chipRun.isEmpty else { return }
				result.stack(chips(chipRun, litter: litter.id, column: column), separation: separation)
				chipRun = []
			}
			for member in members {
				let isFull = focus.map { $0.contains(member.id) } ?? (showAll || bredFrom.contains(member.id) || member.starred)
				// Off the focused path, a member someone bred from is a chip
				// of its own, still with its branch beside it.
				let isBranchChip = !isFull && littersByPrimaryParent[member.id] != nil
				if isFull || isBranchChip {
					flushChips()
					result.stack(branch(member, isChip: isBranchChip, column: column), separation: separation)
				} else {
					chipRun.append(member)
				}
			}
			flushChips()
			return result
		}

		/// A member and its litters, which are stacked and then centred
		/// on it.
		private func branch(_ member: Family.Member, isChip: Bool, column: Int) -> Subtree {
			let size = isChip ? metrics.chipSize : metrics.cellSize
			var result = Subtree()
			result.add(Subtree.PlacedCell(id: member.id, litter: member.litter,
										  frame: CGRect(x: x(ofColumn: column), y: 0, width: size, height: size), isChip: isChip),
					   column: column)
			let childLitters = littersByPrimaryParent[member.id] ?? []
			guard !childLitters.isEmpty else { return result }
			if member.collapsed {
				result.hidden[member.id] = family.descendants(of: [member.id]).count
				return result
			}
			var group = Subtree()
			for litter in childLitters {
				group.stack(layout(litter), separation: { _ in metrics.litterSpacing })
			}
			// Centre the litters' own members (not their branches) on the
			// member.
			let childIDs = Set(childLitters.map(\.id))
			let own = group.cells.filter { childIDs.contains($0.litter) }.map(\.frame)
			if let top = own.map(\.minY).min(), let bottom = own.map(\.maxY).max() {
				group.shift(size / 2 - (top + bottom) / 2)
			}
			result.merge(group)
			return result
		}

		/// Unexplored siblings as a wrapped grid of chips.
		private func chips(_ members: [Family.Member], litter: String, column: Int) -> Subtree {
			let perRow = metrics.chipsPerRow
			let step = metrics.chipSize + metrics.chipSpacing
			var result = Subtree()
			for (index, member) in members.enumerated() {
				let frame = CGRect(x: x(ofColumn: column) + CGFloat(index % perRow) * step, y: CGFloat(index / perRow) * step,
								   width: metrics.chipSize, height: metrics.chipSize)
				result.add(Subtree.PlacedCell(id: member.id, litter: litter, frame: frame, isChip: true), column: column)
			}
			return result
		}
	}
}
