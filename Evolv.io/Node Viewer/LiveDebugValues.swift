//
//  LiveDebugValues.swift
//  Evolv.io
//

import ExpressionTree
import Metal
import SwiftUI

/// The actual "live, no recompile" mechanism behind `NodeDebuggingView`'s
/// toggle/slider controls: owns the `MTLBuffer` a compiled tree's kernel
/// reads its `debug`-annotated `$param`s from (buffer index 2, see
/// `MetalRenderContext`/`MSLTreeEvaluator`). Writing a new value mutates
/// that buffer's shared-storage memory directly -- the next render just
/// re-dispatches the *same, already-compiled* pipeline, so dragging a
/// slider never triggers a shader recompile.
///
/// `@MainActor` because it's only ever constructed/mutated from SwiftUI
/// bindings (matching `NodeRenderer`'s own `@MainActor`); `NodeRenderer`
/// reads just the `buffer` property (a plain `MTLBuffer`, safe to hand to a
/// background render task) before crossing off-actor.
@MainActor
final class LiveDebugValues: ObservableObject {
	let slots: [DebugControlSlot]
	let buffer: MTLBuffer
	@Published private(set) var values: [Float]

	/// `nil` if `slots` is empty (nothing to control) or the buffer couldn't
	/// be allocated -- callers should only construct this once a tree's
	/// manifest (`MetalRenderContext.debugControls(for:)`) is known to be
	/// non-empty.
	init?(slots: [DebugControlSlot], device: MTLDevice) {
		guard !slots.isEmpty,
			  let buffer = device.makeBuffer(length: slots.count * MemoryLayout<Float>.stride, options: .storageModeShared) else {
			return nil
		}
		self.slots = slots
		self.buffer = buffer
		let initialValues = slots.map { Float($0.defaultValue) }
		self.values = initialValues
		let ptr = buffer.contents().bindMemory(to: Float.self, capacity: slots.count)
		for (i, v) in initialValues.enumerated() {
			ptr[i] = v
		}
	}

	func setValue(_ newValue: Float, at index: Int) {
		values[index] = newValue
		buffer.contents().bindMemory(to: Float.self, capacity: slots.count)[index] = newValue
	}

	/// For a `.slider(min:max:)` slot.
	func floatBinding(at index: Int) -> Binding<Float> {
		Binding(
			get: { self.values[index] },
			set: { self.setValue($0, at: index) }
		)
	}

	/// For a `.toggle` slot -- backed by the same float storage (0.0/1.0)
	/// as a slider; MSL already treats a non-zero scalar as true, so the
	/// `.evolvnode` body needs no separate bool representation.
	func toggleBinding(at index: Int) -> Binding<Bool> {
		Binding(
			get: { self.values[index] != 0 },
			set: { self.setValue($0 ? 1 : 0, at: index) }
		)
	}
}
