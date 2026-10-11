//
//  ExportPathTests.swift
//  Evolv.ioTests
//
//  Export Path's file names.
//

import Testing
import ExpressionTree
@testable import Evolv_io

struct ExportPathTests {
	private func item(_ id: String, _ generation: Int) -> ExportPathSheet.Item {
		ExportPathSheet.Item(member: Family.Member(id: id, litter: "L1", index: 0, expression: "x"), generation: generation)
	}

	@Test func namesAreZeroPaddedGenerations() {
		let items = (0...11).map { item("g\($0)", $0) }
		let names = ExportPathSheet.fileNames(for: items, baseName: "Ripples", fileExtension: "png")
		#expect(names.first == "Ripples-gen00.png")
		#expect(names.last == "Ripples-gen11.png")
	}

	@Test func aGenerationWithTwoGenotypesAddsTheirIDs() {
		let items = [item("g2", 0), item("g3", 0), item("g40", 1)]
		#expect(ExportPathSheet.fileNames(for: items, baseName: "Cross", fileExtension: "jpeg")
				== ["Cross-gen00-g2.jpeg", "Cross-gen00-g3.jpeg", "Cross-gen01.jpeg"])
	}
}
