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
	let simpleXSample = Tree(width: width,
							 height: height,
							 root: VariableX())

	let simpleYSample = Tree(width: width,
							 height: height,
							 root: VariableY())

	let absXSample = Tree(width: width,
						  height: height,
						  root: Abs([VariableX()]))

	let modSample = Tree(width: width,
						 height: height,
						 root: Mod([
							VariableX(),
							Abs([
								VariableY()
							])
						 ]))

	let andSample = Tree(width: width,
						 height: height,
						 root: And([
							VariableX(),
							VariableY()
						 ]))

	let bwNoiseSample = Tree(width: width,
							 height: height,
							 root: BWNoise([
								Constant(0.2),
								Constant(2.0)
							 ]))

	let colorNoiseSample = Tree(width: width,
								height: height,
								root: ColorNoise([
									Constant(0.1),
									Constant(2.0)
								]))

	let gradDirSample = Tree(width: 900, height: 900,
							 root:
								GradientDirection([
									BWNoise([
										Constant(0.15),
										Constant(2),
									]),
									Constant(0.0),
									Constant(0.0)
								]))

	let warpedColorNoiseSample = Tree(width: width,
									  height: height,
									  root: WarpedColorNoise([
										Mult([
											VariableX(),
											Constant(0.2)
										]),
										VariableY(),
										Constant(0.1),
										Constant(2.0)
									  ]))

	var body: some View {
		Grid {
			GridRow {
				RenderedImageView(expressionTree: simpleXSample)
				RenderedImageView(expressionTree: simpleYSample)
				RenderedImageView(expressionTree: absXSample)
			}
			GridRow {
				RenderedImageView(expressionTree: modSample)
				RenderedImageView(expressionTree: andSample)
				RenderedImageView(expressionTree: bwNoiseSample)
			}
			GridRow {
				RenderedImageView(expressionTree: colorNoiseSample)
				RenderedImageView(expressionTree: gradDirSample)
				RenderedImageView(expressionTree: warpedColorNoiseSample)
			}
		}
		.padding()
	}
}

#Preview {
	ContentView()
}
