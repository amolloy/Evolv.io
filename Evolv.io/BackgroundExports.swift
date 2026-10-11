//
//  BackgroundExports.swift
//  Evolv.io
//
//  Exports that run after their dialog has closed (Export Image and Export
//  Path, on macOS), and the circular progress that shows them in the
//  toolbar of every window an export can start from: the genotype library,
//  genotype windows and family windows. The progress counts every running
//  export, whichever window started it; its popover lists each one with a
//  Stop button. A failed export is reported in an alert.
//

#if os(macOS)
import SwiftUI
import AppKit

@MainActor
@Observable
final class BackgroundExports {
	static let shared = BackgroundExports()

	struct Job: Identifiable {
		let id = UUID()
		/// What's being written, e.g. "Figure 9.png" or "12 images to Paths".
		let title: String
		var done = 0
		let total: Int
		fileprivate var task: Task<Void, Never>?
	}

	private(set) var jobs: [Job] = []

	var isRunning: Bool { !jobs.isEmpty }

	/// All running exports together, 0...1.
	var fraction: Double {
		let total = jobs.map(\.total).reduce(0, +)
		return total == 0 ? 0 : Double(jobs.map(\.done).reduce(0, +)) / Double(total)
	}

	/// Runs `work` in the background as a job of `total` steps. `work`
	/// reports each finished step through its argument, checks for
	/// cancellation between steps, and returns the files it wrote; with
	/// `revealWhenDone`, Finder then shows them.
	func run(title: String, total: Int, revealWhenDone: Bool,
			 work: @escaping @MainActor (_ stepDone: @escaping @MainActor () -> Void) async throws -> [URL]) {
		let job = Job(title: title, total: total)
		let id = job.id
		jobs.append(job)
		let task = Task { @MainActor in
			do {
				let written = try await work { [weak self] in
					guard let self, let index = self.jobs.firstIndex(where: { $0.id == id }) else { return }
					self.jobs[index].done += 1
				}
				if revealWhenDone && !written.isEmpty {
					NSWorkspace.shared.activateFileViewerSelecting(written)
				}
			} catch is CancellationError {
				// Stopped from the popover: nothing to report.
			} catch {
				let alert = NSAlert()
				alert.messageText = "Couldn't export \(title)"
				alert.informativeText = error.localizedDescription
				alert.runModal()
			}
			jobs.removeAll { $0.id == id }
		}
		if let index = jobs.firstIndex(where: { $0.id == id }) {
			jobs[index].task = task
		}
	}

	func stop(_ id: Job.ID) {
		jobs.first { $0.id == id }?.task?.cancel()
	}
}

/// The toolbar's export progress, shown only while something exports.
struct BackgroundExportsToolbarItem: ToolbarContent {
	@State private var showingDetails = false

	private var exports: BackgroundExports { .shared }

	var body: some ToolbarContent {
		if exports.isRunning {
			ToolbarItem {
				Button {
					showingDetails = true
				} label: {
					ProgressView(value: exports.fraction)
						.progressViewStyle(.circular)
						.controlSize(.small)
				}
				.help(exports.jobs.count == 1 ? "Exporting \(exports.jobs[0].title)" : "\(exports.jobs.count) exports running")
				.popover(isPresented: $showingDetails) {
					BackgroundExportsList()
				}
			}
		}
	}
}

private struct BackgroundExportsList: View {
	private var exports: BackgroundExports { .shared }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			ForEach(exports.jobs) { job in
				VStack(alignment: .leading, spacing: 4) {
					Text("Exporting \(job.title)")
						.font(.headline)
						.lineLimit(1)
					HStack {
						ProgressView(value: Double(job.done), total: Double(max(job.total, 1)))
						Button("Stop") { exports.stop(job.id) }
					}
					if job.total > 1 {
						Text("\(job.done) of \(job.total)")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			if exports.jobs.isEmpty {
				Text("Done")
					.foregroundStyle(.secondary)
			}
		}
		.padding()
		.frame(width: 300)
	}
}
#endif
