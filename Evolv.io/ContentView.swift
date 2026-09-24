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
		"x": "x",
		"y": "y",
		"(abs x)": "(abs x)",
		"(mod X (abs Y))": "(mod X (abs Y))",
		// DSL-spike versions of "(mod X (abs Y))" above and of a standalone
		// color-grad call below, for side-by-side comparison against their
		// hand-written equivalents -- see ExpressionTree/DSL/DSLSampleDefinitions.swift.
		"(dsl-mod X (abs Y))": "(dsl-mod X (abs Y))",
		"(color-grad ...)":
			"(color-grad (round (+ y (log (invert y) 15.5)) x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)",
		"(dsl-color-grad ...)":
			"(dsl-color-grad (round (+ y (log (invert y) 15.5)) x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)",
		"(and X Y)": "(and X Y)",
		"(bw-noise .2 2)": "(bw-noise .2 2)",
		"(color-noise .1 2)": "(color-noise .1 2)",
		"(grad-direction (bw-noise .15 2) .0 .0)": "(grad-direction (bw-noise .15 2) .0 .0)",
		"(warped-color-noise (* X .2) Y .1 2)": "(warped-color-noise (* X .2) Y .1 2)",
		"Figure 6":
		   """
		   (dissolve (cos (and 0.25 #(0.43 0.73 0.74))) 
		   (log (+ (warped-bw-noise (min z 11.1) (log (rotate-vector (+ 
		   (warped-bw-noise (cos x) (dissolve (cos (and 0.25 
		   #(0.43 0.73 0.74))) (log (+ (warped-bw-noise (max (min z 8.26) 
		   (/ -0.5 #(0.82 0.39 0.19))) (log (+ (warped-bw-noise 
		   (cos x) z -0.04 0.89) #(0.82 0.39 0.19)) 
		   #(0.15 0.34 0.50)) -0.04 -3.0) y) #(0.15 0.34 0.50)) y) -0.04 -3.0)
		   x) z y) #(0.15 0.34 0.5)) -0.02 -1.79) -0.4) #(-0.09 0.34 0.55))
		   -0.7) 
		   """,
		"Figure 9":
		   """
		   (round (log (+ y (color-grad (round (+ (abs (round
		   (log (+ y (color-grad (round (+ y (log (invert y) 15.5))
		   x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)) 0.19) x)) (log (invert
		   y) 15.5)) x) 3.1 1.9 #(0.95 0.7 0.35) 1.35)) 0.19) x)
		   """,
		"Figure 10":
		   """
		   (rotate-vector (log(+ y (color-grad (round(+ (abs (round (log #(0.01 0.67 0.86) 0.19)
		   x)) (hsv-to-rgb (bump (if x 10.7 y) #(0.94 0.01 0.4) 0.78 #(0.18 0.28 0.58) #(0.4 0.92
		   0.58) 10.6 0.23 0.91))) X) 3.1 1.93 #(0.95 0.7 0.35) 3.03)) -0.03) X #(0.76 0.08 0.24))
		   """,
		"Figure 12":
			"""
			(cos (round (atan (log (invert y) (+ (bump (+ (round x y) y) #(0.46 0.82 0.65) 0.02 
			#(0.1 0.06 0.1) #(0.99 0.06 0.41) 1.47 8.7 3.7) (color-grad (round (+ y y) (log 
			(invert x) (+ (invert y) (round (+ y x) (bump (warped-ifs (round y y) y 0.08 0.06
			7.4 1.65 6.1 0.54 3.1 0.26 0.73 15.8 5.7 8.9 0.49 7.2 15.6 0.98) #(0.46 0.82 0.65) 
			0.02 #(0.1 0.06 0.1) #(0.99 0.06 0.41) 0.83 8.7 2.6))))) 3.1 6.8 #(0.95 0.7 0.59) 
			0.57))) #(0.17 0.08 0.75) 0.37) (vector y 0.09 (cos (round y y))))) 
			"""
	]

	@State private var selectedGroup: String? = nil
	@State private var showingTreeVisualizer = false

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
				let node = node(for: ContentView.sampleExpressions[selectedGroup]!)
				let nodeRenderer = NodeRenderer(node: node,
												evaluator: Evaluator(size: CGSize(width: 800, height: 800)))
				RenderedImageView(nodeRenderer: nodeRenderer)
				.id(selectedGroup)
				.contextMenu {
					Button("Copy Image") {
						nodeRenderer.copyImageToPasteboard()
					}
					Button("Show Expression Tree") {
						showingTreeVisualizer = true
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: 12))
				.shadow(radius: 5)
				.navigationTitle(selectedGroup)
				.sheet(isPresented: $showingTreeVisualizer) {
					NavigationStack {
						TreeVisualizerView(evaluator: Evaluator(size: CGSize(width: 64, height: 64)),
										   rootNode: node)
							.toolbar {
								ToolbarItem(placement: .cancellationAction) {
									Button("Done") {
										showingTreeVisualizer = false
									}
								}
							}
					}
#if os(macOS)
					.frame(minWidth: 1000, minHeight: 800)
#endif
					.presentationSizing(.page)
				}
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
