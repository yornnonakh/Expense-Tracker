//
//  AccountDTO.swift
//  Data Layer — DTOs
//
//  Stored account record and session envelope.
//
//  SECURITY NOTE: this is a local demo with no backend. Passwords are stored
//  as a salted SHA-256 digest rather than plaintext, so a casual look at the
//  app container doesn't hand over credentials. That is NOT production-grade
//  auth — a shipping app would authenticate against a server, never persist a
//  password on device, and keep the session token in the Keychain rather than
//  UserDefaults. Marked clearly so this never gets mistaken for the real thing.
//

import Foundation

struct AccountDTO: Codable, Equatable {

    let id: String
    let name: String
    /// Always stored lowercased; used as the unique key for an account.
    let email: String
    /// Hex-encoded SHA-256 of (salt + password).
    let passwordHash: String
    /// Random per-account salt, hex-encoded.
    let salt: String
    let createdAt: Double
}

struct SessionDTO: Codable, Equatable {
    let token: String
    let userId: String
    let name: String
    let email: String
    let userCreatedAt: Double
    let issuedAt: Double
}
