//
//  LocalSessionDataSource.swift
//  Data Layer — Data Sources
//
//  Caches the signed-in user's profile and avatar on device.
//
//  This exists so launching offline still shows the user's name and photo
//  instead of bouncing them to a sign-in screen they cannot complete. It holds
//  no credentials: tokens are in the Keychain and the password never reaches
//  this device.
//

import Foundation

actor LocalSessionDataSource {

    private let store: KeyValueStore
    private let imageStore: ProfileImageStore

    init(store: KeyValueStore, imageStore: ProfileImageStore) {
        self.store = store
        self.imageStore = imageStore
    }

    // MARK: - Cached profile

    func cachedUser() -> CachedUserDTO? {
        guard let data = store.data(forKey: StorageKey.session) else { return nil }
        do {
            return try JSONCoding.decode(CachedUserDTO.self, from: data)
        } catch {
            // A cache we cannot read is a cache worth dropping. The tokens in
            // the Keychain are what actually authenticate; this is only a
            // convenience copy, so losing it costs one network round trip.
            store.removeObject(forKey: StorageKey.session)
            return nil
        }
    }

    func cache(_ dto: CachedUserDTO) throws {
        do {
            let data = try JSONCoding.encode(dto)
            store.set(data, forKey: StorageKey.session)
        } catch {
            throw AuthError.storageFailure("Could not save your profile.")
        }
    }

    func clear() {
        if let existing = cachedUser()?.avatarFileName {
            imageStore.removeImage(named: existing)
        }
        store.removeObject(forKey: StorageKey.session)
    }

    // MARK: - Avatar bytes

    /// Photo bytes for a stored file name, or nil when there is no photo (or
    /// the file has gone missing — a deleted file degrades to initials rather
    /// than failing the sign-in that asked for it).
    func avatarData(fileName: String?) -> Data? {
        fileName.flatMap { imageStore.imageData(named: $0) }
    }

    /// Writes the photo — or deletes it, for nil — and records the change on
    /// the cached profile, returning the updated record.
    ///
    /// The file is written before the profile is re-cached, so a failure
    /// mid-way leaves an orphaned file rather than a profile pointing at
    /// nothing. The orphan is invisible and gets overwritten by the next save;
    /// a dangling reference would show as a broken avatar.
    @discardableResult
    func setAvatar(_ imageData: Data?, hasRemoteAvatar: Bool) throws -> CachedUserDTO {
        guard var user = cachedUser() else { throw AuthError.sessionExpired }

        if let imageData {
            let name = Self.avatarFileName(forUserId: user.id)
            try imageStore.save(imageData, named: name)
            user.avatarFileName = name
        } else {
            if let existing = user.avatarFileName {
                imageStore.removeImage(named: existing)
            }
            user.avatarFileName = nil
        }

        user.hasRemoteAvatar = hasRemoteAvatar
        try cache(user)
        return user
    }

    /// One file per user, always the same name, so replacing a photo
    /// overwrites in place and can't accumulate orphans.
    private static func avatarFileName(forUserId id: String) -> String {
        "avatar-\(id).jpg"
    }
}
