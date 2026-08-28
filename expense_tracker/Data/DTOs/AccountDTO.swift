//
//  AccountDTO.swift
//  Data Layer — DTOs
//
//  The cached copy of the signed-in user.
//
//  WHAT IS NO LONGER HERE, and why it matters: this file used to hold an
//  `AccountDTO` with a salted password digest, because the app verified
//  sign-ins itself. Authentication now happens on the server, so the device
//  never sees, hashes or stores password material at all. The strongest
//  version of "don't leak the user's password" is not having it.
//
//  What remains is a profile cache: enough to render the account screen and
//  restore a session at launch without a network round trip. Tokens are NOT
//  here either — they live in the Keychain, via `KeychainTokenStore`.
//

import Foundation

nonisolated struct CachedUserDTO: Codable, Equatable {

    let id: String
    /// Always stored lowercased.
    let email: String
    let name: String
    /// Epoch seconds.
    let createdAt: Double

    /// Name of this user's photo in `ProfileImageStore`, or nil when the
    /// avatar falls back to initials. Only the reference lives here — the
    /// bytes are a file, not a defaults entry.
    ///
    /// Optional, and therefore absent-tolerant when decoding, so records
    /// written before profile photos existed still load.
    var avatarFileName: String?

    /// True when the server says this account has a photo. Lets the app tell
    /// "no photo" apart from "photo not downloaded to this device yet".
    var hasRemoteAvatar: Bool

    init(
        id: String,
        email: String,
        name: String,
        createdAt: Double,
        avatarFileName: String? = nil,
        hasRemoteAvatar: Bool = false
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.avatarFileName = avatarFileName
        self.hasRemoteAvatar = hasRemoteAvatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.email = try container.decode(String.self, forKey: .email)
        self.name = try container.decode(String.self, forKey: .name)
        self.createdAt = try container.decode(Double.self, forKey: .createdAt)
        self.avatarFileName = try container.decodeIfPresent(String.self, forKey: .avatarFileName)
        self.hasRemoteAvatar =
            try container.decodeIfPresent(Bool.self, forKey: .hasRemoteAvatar) ?? false
    }
}
