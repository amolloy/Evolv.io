//
//  ContentView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree

struct ContentView: View {
	static let parser = Parser()

	static let sampleExpressions = [
		"(color-grad x 3.1 1.93 #(0.95 0.7 0.35) 3.03))": "(color-grad x 3.1 1.93 #(0.95 0.7 0.35) 3.03))",
		"Test 1":
   """
   (color-grad (round(+ (abs (round (log #(0.01 0.67 0.86) 0.19)
   x)) (hsv-to-rgb (bump (if x 10.7 y) #(0.94 0.01 0.4) 0.78 #(0.18 0.28 0.58) #(0.4 0.92
   0.58) 10.6 0.23 0.91))) X) 3.1 1.93 #(0.95 0.7 0.35) 3.03)
   """,
		"Test 2":
   """
   (bump (if x 10.7 y) #(0.94 0.01 0.4) 0.78 #(0.18 0.28 0.58) #(0.4 0.92
   0.58) 10.6 0.23 0.91)
   """,
		"x": "x",
		"y": "y",
		"(abs x)": "(abs x)",
		"(mod X (abs Y))": "(mod X (abs Y))",
		"(and X Y)": "(and X Y)",
		"(bw-noise .2 2)": "(bw-noise .2 2)",
		"(color-noise .1 2)": "(color-noise .1 2)",
		"(grad-direction (bw-noise .15 2) .0 .0)": "(grad-direction (bw-noise .15 2) .0 .0)",
		"(warped-color-noise (* X .2) Y .1 2)": "(warped-color-noise (* X .2) Y .1 2)",
		"Figure 9":
		   """
		   (round (log (+ y (color-grad (round (+ (abs (round 
		   (log (+ y (color-grad (round (+ y (log (invert y) 15.5)) 
		   x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)) 0.19) x)) (log (invert
		   y) 15.5)) x) 3.1 1.9 #(0.95 0.7 0.35) 1.35)) 0.19) x)
		   """,
		"Figure 9 (sub)":
			"""
			(+ y (color-grad (round (+ (abs (round (log (+ y (color-grad (round (+ y (log (invert y) 15.5)) x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)) 0.19) x)) (log (invert y) 15.5)) x) 3.1 1.9 #(0.95 0.7 0.35) 1.35))
			""",
		"Figure 10":
		   """
		   (rotate-vector (log(+ y (color-grad (round(+ (abs (round (log #(0.01 0.67 0.86) 0.19)
		   x)) (hsv-to-rgb (bump (if x 10.7 y) #(0.94 0.01 0.4) 0.78 #(0.18 0.28 0.58) #(0.4 0.92
		   0.58) 10.6 0.23 0.91))) X) 3.1 1.93 #(0.95 0.7 0.35) 3.03)) -0.03) X #(0.76 0.08 0.24))
		   """,
	]

	@State private var selectedGroup: String? = nil

	var body: some View {
		NavigationSplitView {
			List(selection: $selectedGroup) {
				ForEach(ContentView.sampleExpressions.sorted(by: >), id:\.key) { key, value in
					Text(key)
						.tag(key)
				}
			}
			.frame(minWidth: 200)
		} detail: {
			if let selectedGroup {
				VStack {
					let node = node(for: ContentView.sampleExpressions[selectedGroup]!)
					let nodeRenderer = NodeRenderer(node: node,
													evaluator: Evaluator(size: CGSize(width: 800, height: 800)))
					RenderedImageView(nodeRenderer: nodeRenderer)
					.id(selectedGroup)
					.contextMenu {
						Button("Copy Image") {
							nodeRenderer.copyImageToPasteboard()
						}
					}
					.clipShape(RoundedRectangle(cornerRadius: 12))
					.shadow(radius: 5)

					TreeVisualizerView(evaluator: Evaluator(size: CGSize(width: 44, height: 44)),
									   rootNode: node)
				}
				.navigationTitle(selectedGroup)
			} else {
				Text("Select an expression group")
			}
		}
	}

	func node(for expression: String) -> any Node {
		do {
			return try ContentView.parser.parse(expression)
		} catch {
			print("Error parsing expression:", expression)
			return Constant(0)
		}
	}
}
