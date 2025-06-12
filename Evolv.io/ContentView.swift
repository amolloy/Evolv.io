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

	static let figure9 = [
	"""
	(round (log (+ y (color-grad (round (+ (abs (round 
		(log (+ y (color-grad (round (+ y (log (invert y) 15.5)) 
		x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)) 0.19) x)) (log (invert
		y) 15.5)) x) 3.1 1.9 #(0.95 0.7 0.35) 1.35)) 0.19) x)
	"""
	]

	static let figure10 = [
	"""
		(rotate-vector (log(+ y (color-grad (round(+ (abs (round (log #(0.01 0.67 0.86) 0.19)
		x)) (hsv-to-rgb (bump (if x 10.7 y) #(0.94 0.01 0.4) 0.78 #(0.18 0.28 0.58) #(0.4 0.92
		0.58) 10.6 0.23 0.91))) X) 3.1 1.93 #(0.95 0.7 0.35) 3.03)) -0.03) X #(0.76 0.08 0.24))
	"""
	]

	static let test = [
		"x",
		"(bump (+ (round x y) y) #(0.46 0.82 0.65) 0.02 #(0.1 0.06 0.1) #(0.99 0.06 0.41) 1.47 8.7 3.7)",
	]

	let expressions = ContentView.test

	var body: some View {
		Grid {
			ForEach(Array(stride(from: 0, to: expressions.count, by: 3)), id: \.self) { row in
				ImageRowView(expressions: expressions[(row)..<(min(row + 3, expressions.count))])
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
			print("Error parsing")
			print(expression)
			let desc: String
			if let error = error as? ParseError {
				desc = error.errorDescription ?? error.localizedDescription
			} else {
				desc = error.localizedDescription
			}
			print(desc)

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
