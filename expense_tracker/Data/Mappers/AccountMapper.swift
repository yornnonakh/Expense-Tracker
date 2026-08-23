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

    static func toDomain(_ dto: AccountDTO, avatarImageData: Data? = nil) throws -> User {
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

    static func toDTO(_ session: AuthSession, avatarFileName: String?) -> SessionDTO {
        SessionDTO(
            token: session.token,
            userId: session.user.id.uuidString,
            name: session.user.name,
            email: session.user.email,
            userCreatedAt: session.user.createdAt.timeIntervalSince1970,
            issuedAt: session.issuedAt.timeIntervalSince1970,
            avatarFileName: avatarFileName
        )
    }

    static func toDomain(_ dto: SessionDTO, avatarImageData: Data? = nil) throws -> AuthSession {
        guard let userId = UUID(uuidString: dto.userId) else {
            throw AuthError.storageFailure("Session has a malformed user id")
        }
        let user = User(
            id: userId,
            name: dto.name,
            email: dto.email,
            createdAt: Date(timeIntervalSince1970: dto.userCreatedAt),
            avatarImageData: avatarImageData
        )
        return AuthSession(
            token: dto.token,
            user: user,
            issuedAt: Date(timeIntervalSince1970: dto.issuedAt)
        )
    }
}
