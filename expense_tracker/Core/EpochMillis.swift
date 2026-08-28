//
//  EpochMillis.swift
//  Core
//
//  Whole epoch milliseconds.
//
//  `Date().timeIntervalSince1970 * 1000` carries sub-millisecond precision, so
//  it lands on the wire as `1787744118838.855`. The server validates every
//  millisecond field as an integer and rejects a float outright, which failed
//  the entire sync push — one bad timestamp 400s the whole batch, so a single
//  record kept the rest of the device's data from ever reaching the server.
//
//  Truncating here rather than at the wire boundary is deliberate. The stored
//  value and the pushed value have to be byte-identical: sync compares the
//  local `updatedAt` against the copy the server echoes back, so a local
//  1787744118838.855 against a returned 1787744118838 would read as "the local
//  row is newer" forever, leaving the record permanently pending and re-pushed
//  on every cycle.
//
//  Sub-millisecond resolution buys nothing here — it only ever feeds
//  last-write-wins comparisons between devices whose clocks differ by far more
//  than a millisecond.
//

import Foundation

/// `nonisolated` for the reason spelled out in `JSONCoding`: the project
/// compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and these are
/// read from the data layer's actors, off the main actor.
nonisolated extension Date {

    /// Epoch milliseconds, truncated to a whole number.
    ///
    /// The unit the server's `epochMillisSchema` accepts, and the unit every
    /// `updatedAt` / `deletedAt` in this app is stored in.
    var epochMillis: Double {
        (timeIntervalSince1970 * 1000).wholeEpochMillis
    }
}

nonisolated extension Double {

    /// This value, already in epoch milliseconds, truncated to a whole number.
    ///
    /// Applied on decode as well as on generation. Rows written before this
    /// fix still hold a fractional value on disk, and one of them is enough to
    /// 400 the batch that carries every other record with it.
    var wholeEpochMillis: Double {
        rounded(.down)
    }
}

nonisolated enum EpochMillis {

    /// The stamp for a local write to a record that currently reads `previous`.
    ///
    /// Never equal to `previous`, and never behind it. The server settles a
    /// push with `incoming.updatedAt <= existing` -> conflict, so a stamp that
    /// merely ties loses and the client is handed back the copy it was trying
    /// to replace. Truncating to whole milliseconds is what makes that
    /// reachable: the clock now only advances once per millisecond, and two
    /// writes to the same record can land inside one — edit then delete, and
    /// the delete ties, loses, and the expense comes back.
    ///
    /// The `previous + 1` branch also covers a record last written by a device
    /// whose clock runs ahead of this one. Without it this device could not
    /// win an edit until the clocks converged.
    static func stamp(after previous: Double, now: Date = Date()) -> Double {
        max(now.epochMillis, previous + 1)
    }
}
