//
//  ContentView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree

let width = 900
let height = 900

struct ContentView: View {
	static let parser = Parser()

	static let sampleGridExpressions = [
		"x",
		"y",
		"(abs x)",
		"(mod X (abs Y))",
		"(and X Y)",
		"(bw-noise .2 2)",
		"(color-noise .1 2)",
		"(grad-direction (bw-noise .15 2) .0 .0)",
		"(warped-color-noise (* X .2) Y .1 2)",
	]

	let expressions = ContentView.sampleGridExpressions

	var body: some View {
		Grid {
			ForEach(Array(stride(from: 0, to: expressions.count, by: 3)), id: \.self) { row in
				ImageRowView(expressions: expressions[(row)..<(row + 3)])
			}
		}
		.padding()
	}
}

struct ImageRowView<C: RandomAccessCollection>: View where C.Element == String, C.Index == Int {
	let expressions: C
	private let parser = Parser()

	func node(for expression: String) -> Node {
		do {
			return try parser.parse(expression)
		} catch {
			print("Parser error processing '\(expression)': \(error.localizedDescription)")
			return Constant(0)
		}
	}

	var body: some View {
		GridRow {
			ForEach(expressions, id:\.self) { expression in
				let node = node(for: expression)
				RenderedImageView(expressionTree: Tree(width: 900, height: 900, root: node))
			}
		}
	}
}

#Preview {
	ContentView()
}
