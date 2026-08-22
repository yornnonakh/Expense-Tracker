//
//  AccountMapper.swift
//  Data Layer — Mappers
//

import Foundation

enum AccountMapper {

    static func toDomain(_ dto: AccountDTO) throws -> User {
        guard let id = UUID(uuidString: dto.id) else {
            throw AuthError.storageFailure("Account has a malformed id")
        }
        return User(
            id: id,
            name: dto.name,
            email: dto.email,
            createdAt: Date(timeIntervalSince1970: dto.createdAt)
        )
    }

    static func toDTO(_ session: AuthSession) -> SessionDTO {
        SessionDTO(
            token: session.token,
            userId: session.user.id.uuidString,
            name: session.user.name,
            email: session.user.email,
            userCreatedAt: session.user.createdAt.timeIntervalSince1970,
            issuedAt: session.issuedAt.timeIntervalSince1970
        )
    }

    static func toDomain(_ dto: SessionDTO) throws -> AuthSession {
        guard let userId = UUID(uuidString: dto.userId) else {
            throw AuthError.storageFailure("Session has a malformed user id")
        }
        let user = User(
            id: userId,
            name: dto.name,
            email: dto.email,
            createdAt: Date(timeIntervalSince1970: dto.userCreatedAt)
        )
        return AuthSession(
            token: dto.token,
            user: user,
            issuedAt: Date(timeIntervalSince1970: dto.issuedAt)
        )
    }
}
