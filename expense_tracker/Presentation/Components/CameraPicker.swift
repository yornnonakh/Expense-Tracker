//
//  CameraPicker.swift
//  Presentation Layer — Components
//
//  "Take Photo" for the profile screen.
//
//  WHY UIKIT: `PhotosPicker` covers the library and needs no permission
//  prompt, but it deliberately cannot open the camera. Capturing still means
//  `UIImagePickerController`, so it is wrapped here and nowhere else —
//  alongside `Haptics`, this is the app's only other UIKit touchpoint.
//
//  The camera needs `NSCameraUsageDescription`, which is set in the target's
//  build settings (`INFOPLIST_KEY_NSCameraUsageDescription`).
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {

    /// JPEG bytes of the captured photo, before downscaling.
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False on Simulator and on any device without a camera, which is what
    /// the Take Photo option keys off — an unavailable source type presents an
    /// empty black sheet rather than failing loudly.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraDevice = .front
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {

        private let onCapture: (Data) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (Data) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // The edited image is the square crop the user just confirmed;
            // fall back to the original if editing was skipped.
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage

            // Encoded at full quality here — `ProfileImageProcessor` does the
            // real downscale, and compressing twice only loses detail.
            if let data = image?.jpegData(compressionQuality: 1) {
                onCapture(data)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
