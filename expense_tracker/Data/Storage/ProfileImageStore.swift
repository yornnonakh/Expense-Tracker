//
//  ProfileImageStore.swift
//  Data Layer — Storage
//
//  Where profile photos live on disk.
//
//  Deliberately NOT `KeyValueStore`. UserDefaults is a property list that the
//  system reads into memory in full on first touch, so parking a JPEG in it
//  would tax every launch and every unrelated read in the app. Photos are
//  written as files instead, and only the file name is recorded against the
//  account — the same split a real backend would use between a row and a blob.
//

import Foundation

nonisolated protocol ProfileImageStore: Sendable {

    /// Bytes for a previously saved photo, or nil when the file is gone.
    func imageData(named name: String) -> Data?

    /// Writes, or overwrites, one account's photo.
    func save(_ data: Data, named name: String) throws

    func removeImage(named name: String)
}

// MARK: - Files

/// Production store. Photos go in Application Support, which is backed up and
/// never purged behind the app's back the way Caches can be.
nonisolated final class FileProfileImageStore: ProfileImageStore, @unchecked Sendable {

    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default, directoryName: String = "ProfileImages") {
        self.fileManager = fileManager

        // Application Support doesn't exist until something asks for it with
        // `create: true`. The temporary directory is a last resort so a
        // failure here degrades to "the photo doesn't survive relaunch"
        // rather than a crash at the composition root.
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        self.directoryURL = base.appendingPathComponent(directoryName, isDirectory: true)
    }

    func imageData(named name: String) -> Data? {
        try? Data(contentsOf: fileURL(for: name))
    }

    func save(_ data: Data, named name: String) throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            // Atomic: a photo half-written when the app is killed would be
            // decoded as garbage on the next launch.
            try data.write(to: fileURL(for: name), options: .atomic)
        } catch {
            throw AuthError.storageFailure("Could not save the profile photo.")
        }
    }

    func removeImage(named name: String) {
        try? fileManager.removeItem(at: fileURL(for: name))
    }

    /// `lastPathComponent` neutralises any separators that could have crept
    /// into a stored name — this is only ever allowed to name a file inside
    /// our own directory, never a path out of it.
    private func fileURL(for name: String) -> URL {
        directoryURL.appendingPathComponent(
            (name as NSString).lastPathComponent, isDirectory: false
        )
    }
}

// MARK: - In-memory (tests & previews)

/// Keeps photos in RAM, so a preview that picks an image writes nothing to the
/// simulator's container.
nonisolated final class InMemoryProfileImageStore: ProfileImageStore, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    init(seed: [String: Data] = [:]) {
        self.storage = seed
    }

    func imageData(named name: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[name]
    }

    func save(_ data: Data, named name: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[name] = data
    }

    func removeImage(named name: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: name)
    }
}
