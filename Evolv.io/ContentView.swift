//
//  ContentView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree

struct ContentView: View {
	let tree = Tree(width: 900, height: 900,
					root:
					GradientDirection(children: [
						BWNoise(children: [
							Constant(value: 0.15),
							Constant(value: 2),
						]),
						Constant(value: 0.0),
						Constant(value: 0.0)
					])
	)

	var body: some View {
		VStack {
			RenderedImageView(expressionTree: tree)
		}
		.padding()
	}
}

#Preview {
	ContentView()
}
