//
//  AccountMapper.swift
//  Data Layer — Mappers
//
//  Profile photos cross this boundary as two different things: storage knows a
//  file name, the domain knows bytes. The mapper never touches the filesystem
//  itself — the data source reads the bytes and passes them in — so mapping
//  stays a pure, synchronous transformation.
//

import Foundation

nonisolated enum AccountMapper {

    // MARK: - Wire -> cache

    /// The server sends `createdAt` in milliseconds; everything on device
    /// stores seconds. Converting in exactly one place is what stops a
    /// thousand-fold date error from creeping in somewhere else.
    static func toCached(
        _ api: APIUser,
        avatarFileName: String? = nil
    ) -> CachedUserDTO {
        CachedUserDTO(
            id: api.id,
            email: api.email,
            name: api.name,
            createdAt: api.createdAt / 1000,
            avatarFileName: avatarFileName,
            hasRemoteAvatar: api.hasAvatar
        )
    }

    // MARK: - Cache -> domain

    static func toDomain(
        _ dto: CachedUserDTO,
        avatarImageData: Data? = nil
    ) throws -> User {
        guard let id = UUID(uuidString: dto.id) else {
            throw AuthError.storageFailure("Account has a malformed id")
        }
        return User(
            id: id,
            name: dto.name,
            email: dto.email,
            createdAt: Date(timeIntervalSince1970: dto.createdAt),
            avatarImageData: avatarImageData
        )
    }

    /// Wire straight to domain, for the sign-in path where nothing is cached
    /// yet.
    static func toDomain(_ api: APIUser, avatarImageData: Data? = nil) throws -> User {
        try toDomain(toCached(api), avatarImageData: avatarImageData)
    }
}
