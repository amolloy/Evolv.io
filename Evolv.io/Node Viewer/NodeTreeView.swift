//
//  NodeTreeView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import SwiftUI
import ExpressionTree

@MainActor
final class TreeVisualizerViewModel: ObservableObject {
	@Published private(set) var renderedThumbnails: [ObjectIdentifier: CGImage] = [:]

	private let rootNode: any Node
	private let evaluator: Evaluator

	init(rootNode: any Node,
		 evaluator: Evaluator) {
		self.rootNode = rootNode
		self.evaluator = evaluator
	}

	func renderTree() {
		Task {
			await renderNodeAndDependencies(rootNode)
		}
	}

	private func renderNodeAndDependencies(_ node: any Node) async {
		if renderedThumbnails[node.id] != nil {
			return
		}

		await withTaskGroup(of: Void.self) { group in
			for child in node.children {
				group.addTask {
					await self.renderNodeAndDependencies(child)
				}
			}
		}

		let sia = ImageRenderingActor.shared
		if let image = await sia.render(node: node, evaluator: evaluator) {
			renderedThumbnails[node.id] = image
		}
	}
}

actor ImageRenderingActor {
	static let shared = ImageRenderingActor()
	func render(node: any Node,
				evaluator: Evaluator) -> CGImage? {
		return node.rasterize(evaluator: evaluator)
	}
}

final class DisplayNode: ObservableObject, Identifiable {
	let id: ObjectIdentifier
	let node: any Node
	let children: [DisplayNode]
	@Published var isExpanded: Bool = false

	init(node: any Node, isInitiallyExpanded: Bool = false) {
		self.id = node.id
		self.node = node
		self.children = node.children.map { DisplayNode(node: $0) }
		self.isExpanded = isInitiallyExpanded
	}
}

struct TreeVisualizerView: View {
	@StateObject private var viewModel: TreeVisualizerViewModel
	private let rootDisplayNode: DisplayNode

	init(evaluator: Evaluator,
		 rootNode: any Node) {
		self._viewModel = StateObject(wrappedValue: TreeVisualizerViewModel(rootNode: rootNode,
																			evaluator: evaluator))
		self.rootDisplayNode = DisplayNode(node: rootNode, isInitiallyExpanded: true)
	}

	var body: some View {
		ScrollView([.horizontal, .vertical]) {
			VStack {
				RecursiveNodeView(displayNode: rootDisplayNode,
								  viewModel: viewModel)
			}
			.frame(maxHeight: .infinity, alignment: .center)
			.padding()
		}
		.navigationTitle("Expression Tree")
		.onAppear {
			viewModel.renderTree()
		}
	}
}

struct RecursiveNodeView: View {
	@ObservedObject var displayNode: DisplayNode
	@ObservedObject var viewModel: TreeVisualizerViewModel

	var body: some View {
		VStack(alignment: .center, spacing: 0) {
			NodeHeaderView(displayNode: displayNode,
						   thumbnail: viewModel.renderedThumbnails[displayNode.id])
			.fixedSize(horizontal: false, vertical: true)

			if displayNode.isExpanded && !displayNode.children.isEmpty {
				Rectangle().fill(.secondary).frame(width: 2, height: 20)

				HStack(alignment: .top, spacing: 0) {
					ForEach(0..<displayNode.children.count, id: \.self) { index in
						let childNode = displayNode.children[index]

						VStack(spacing: 0) {
							GeometryReader { geometry in
								Path { path in
									let startX = (index == 0) ? geometry.size.width / 2 : 0
									let endX = (index == displayNode.children.count - 1) ? geometry.size.width / 2 : geometry.size.width

									path.move(to: CGPoint(x: startX, y: 1))
									path.addLine(to: CGPoint(x: endX, y: 1))

									path.move(to: CGPoint(x: geometry.size.width / 2, y: 1))
									path.addLine(to: CGPoint(x: geometry.size.width / 2, y: 20))
								}
								.stroke(Color.secondary, lineWidth: 2)
							}
							.frame(height: 20)

							RecursiveNodeView(displayNode: childNode,
											  viewModel: viewModel)
						}
					}
				}
			}
		}
	}
}

struct NodeHeaderView: View {
	@ObservedObject var displayNode: DisplayNode
	let thumbnail: CGImage?

	var body: some View {
		VStack {
			Image(systemName: "chevron.right")
				.font(.caption)
				.rotationEffect(.degrees(displayNode.isExpanded ? 90 : 0))
				.opacity(displayNode.children.isEmpty ? 0 : 1)

			Text(displayNode.node.toString())
				.font(.caption)
				.lineLimit(nil)
				.multilineTextAlignment(.leading)

			Spacer()

			Group {
				if let thumbnail = thumbnail {
					Image(decorative: thumbnail, scale: 1.0)
						.resizable()
						.interpolation(.none)
				} else {
					ProgressView()
				}
			}
			.frame(width: 44, height: 44)
			.background(Color.secondary.opacity(0.1))
			.clipShape(RoundedRectangle(cornerRadius: 4))
		}
		.padding(.vertical, 4)
		.contentShape(Rectangle())
		.onTapGesture {
			withAnimation(.easeInOut(duration: 0.2)) {
				displayNode.isExpanded.toggle()
			}
		}
	}
}

