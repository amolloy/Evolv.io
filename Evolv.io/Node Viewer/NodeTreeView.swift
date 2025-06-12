//
//  NodeTreeView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import SwiftUI
import ExpressionTree

struct NodeTreeView: View {
	let node: Node
	private let thumbnailSize = 100.0

	var body: some View {
		VStack(spacing: 0) {
			VStack(spacing: 4) {
				Text(node.toString())
					.font(.caption.bold())
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(.background, in: Capsule())

				RenderedImageView(size: CGSize(width: thumbnailSize, height: thumbnailSize),
								  expressionTree: node)
			}
			.padding()

			if !node.children.isEmpty {
				Rectangle().fill(.secondary).frame(width: 2, height: 20)

				Rectangle().fill(.secondary).frame(height: 2)

				HStack(alignment: .top, spacing: 0) {
					ForEach(0..<node.children.count, id: \.self) { index in
						NodeTreeView(node: node.children[index])
					}
				}
			}
		}
	}
}
