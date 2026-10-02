//
//  UserLibrary.swift
//  ExpressionTree
//
//  Where the user-editable Nodes and Genotypes folders live: the app's
//  iCloud Drive container (the "Evolv.io" folder in iCloud Drive) when
//  iCloud is available, so both are shared between Macs signed into the
//  same Apple ID, otherwise the sandbox container's own Documents as
//  before.
//

import Foundation

public enum UserLibrary {
	public static let iCloudContainerIdentifier = "iCloud.com.amolloy.Evolv-io"

	/// The folders moved into iCloud on first launch with iCloud available.
	private static let folderNames = ["Nodes", "Genotypes"]

	/// The Documents folder the user Nodes and Genotypes folders live in.
	/// Resolved once, on first access: `url(forUbiquityContainerIdentifier:)`
	/// can block while iCloud sets the container up, and switching folders
	/// mid-run would leave the node registry and genotype store looking at
	/// different places. `Evolv_ioApp.init` touches this before anything
	/// else so that cost lands at launch.
	public static var documentsDirectory: URL? { resolved.documents }

	/// Whether `documentsDirectory` is the iCloud container rather than
	/// the local fallback.
	public static var isUsingICloud: Bool { resolved.isICloud }

	private static let resolved: (documents: URL?, isICloud: Bool) = resolveDocumentsDirectory()

	/// `name` inside `documentsDirectory`, created if missing.
	public static func directory(named name: String) -> URL? {
		guard let documents = documentsDirectory else {
			return nil
		}
		let directory = documents.appendingPathComponent(name, isDirectory: true)
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private static var localDocumentsDirectory: URL? {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
	}

	private static func resolveDocumentsDirectory() -> (documents: URL?, isICloud: Bool) {
		guard let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerIdentifier) else {
			print("User library: iCloud unavailable, using local Documents")
			return (localDocumentsDirectory, false)
		}
		let documents = ubiquity.appendingPathComponent("Documents", isDirectory: true)
		try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
		print("User library: using iCloud Drive at \(documents.path)")

		for name in folderNames {
			let iCloudFolder = documents.appendingPathComponent(name, isDirectory: true)
			if let local = localDocumentsDirectory?.appendingPathComponent(name, isDirectory: true) {
				moveLocalFiles(from: local, into: iCloudFolder)
			}
			startDownloads(in: iCloudFolder)
		}
		return (documents, true)
	}

	/// Moves every file under the local `source` folder to the same
	/// relative path under `destination`. A file whose name is already
	/// taken in iCloud is left where it is rather than overwriting the
	/// iCloud copy, and reported. Runs every launch with iCloud available,
	/// so anything saved locally while iCloud was off moves over the next
	/// time it's on.
	private static func moveLocalFiles(from source: URL, into destination: URL) {
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(
			at: source,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else {
			return
		}
		let sourcePath = source.standardizedFileURL.path
		for case let url as URL in enumerator {
			guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
				continue
			}
			let relativePath = String(url.standardizedFileURL.path.dropFirst(sourcePath.count + 1))
			let target = destination.appendingPathComponent(relativePath)
			if fileManager.fileExists(atPath: target.path) {
				print("User library: \(relativePath) already exists in iCloud; left the local copy at \(url.path)")
				continue
			}
			do {
				try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
				try fileManager.moveItem(at: url, to: target)
				print("User library: moved \(relativePath) into iCloud")
			} catch {
				print("User library: couldn't move \(url.path) into iCloud: \(error.localizedDescription)")
			}
		}
	}

	/// Asks iCloud to fetch everything under `folder` now, so files saved
	/// on the other Mac (or evicted to save space) are local before the
	/// node registry and genotype store read them, rather than each read
	/// waiting on its own download.
	private static func startDownloads(in folder: URL) {
		guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
			return
		}
		for case let url as URL in enumerator {
			try? FileManager.default.startDownloadingUbiquitousItem(at: url)
		}
	}
}
