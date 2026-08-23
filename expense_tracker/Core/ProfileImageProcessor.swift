//
//  ProfileImageProcessor.swift
//  Core
//
//  Turns whatever the photo picker hands over into something worth storing.
//
//  A photo straight off the camera roll is a 12-megapixel HEIC — several MB
//  for something the app never draws larger than 84pt. Every image is
//  downscaled and re-encoded as JPEG before it goes anywhere near storage.
//
//  Uses ImageIO rather than UIKit: `CGImageSourceCreateThumbnailAtIndex`
//  produces the small version without ever decoding the full-size bitmap into
//  memory, and applies the EXIF orientation on the way out — so a photo taken
//  in portrait doesn't come back on its side.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProfileImageProcessor {

    /// Cap on the long edge, in pixels. The biggest an avatar is ever drawn is
    /// 84pt, which is 252px on a 3x screen — 512 leaves room for a larger
    /// avatar later without a re-encode, and still lands around 40–80 KB.
    nonisolated static let maximumPixelSize = 512

    nonisolated static let compressionQuality = 0.82

    /// Downscaled JPEG bytes, or nil when the input isn't an image we can read.
    ///
    /// Safe to call off the main actor, and worth doing: decoding a large HEIC
    /// is tens of milliseconds that shouldn't land in the frame loop.
    nonisolated static func prepare(_ data: Data) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions
        ) else {
            return nil
        }

        return encodeJPEG(thumbnail)
    }

    private nonisolated static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
