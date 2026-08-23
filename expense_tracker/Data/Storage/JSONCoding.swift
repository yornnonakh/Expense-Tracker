//
//  JSONCoding.swift
//  Data Layer — Storage
//
//  Shared encoder/decoder configuration.
//
//  Both sides must agree on date strategy or every round-trip silently shifts
//  timestamps. Defining them together, once, is what guarantees that.
//

import Foundation

/// `nonisolated` because the whole data layer runs off the main actor. The
/// project compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
/// without this every `encode`/`decode` call from a data-source actor is an
/// isolation violation — a warning today, an error in Swift 6 language mode.
nonisolated enum JSONCoding {

    /// ISO-8601 rather than the default `timeIntervalSinceReferenceDate`:
    /// stored data stays human-readable and portable if it ever moves to a
    /// real backend.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Encodes, translating any failure into a domain error so the data
    /// layer's `EncodingError` never reaches the UI.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw ExpenseError.encodingFailed(String(describing: error))
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ExpenseError.decodingFailed(String(describing: error))
        }
    }
}
