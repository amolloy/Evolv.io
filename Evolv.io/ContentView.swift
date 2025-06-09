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
					root:And(children: [
						VariableX(),
						VariableY()])
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
