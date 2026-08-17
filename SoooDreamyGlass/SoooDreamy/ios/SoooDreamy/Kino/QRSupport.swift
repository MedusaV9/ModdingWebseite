import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import VisionKit

/// QR payload that carries server + couple code in one scan.
struct PairQRPayload: Codable {
    var v: Int = 1
    var server: String
    var code: String

    static func encode(server: String, code: String) -> String {
        let payload = PairQRPayload(server: server, code: code)
        if let data = try? JSONEncoder().encode(payload),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return code
    }

    static func decode(_ text: String) -> PairQRPayload? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PairQRPayload.self, from: data)
    }
}

// NOTE: PendingInvite (the page-1 invite hand-over slot) moved to
// Core/PendingInvite.swift — Foundation-only, with a 15-minute shelf life
// so an abandoned setup flow never leaks a stale code into a later pairing.

enum QRGenerator {
    static func image(for text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The one QR scanner the app presents: VisionKit's DataScanner (ML-assisted
/// focus, highlight overlay, low-light guidance) wherever the hardware
/// supports it, with the plain AVFoundation scanner as fallback (Simulator,
/// devices without scanner support). `onFound` fires exactly once.
struct QRCodeScanner: View {
    let onFound: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported {
            DataScannerQRView(onFound: onFound)
        } else {
            QRScannerView(onFound: onFound)
        }
    }
}

/// VisionKit DataScanner wrapped for SwiftUI, restricted to QR symbology.
private struct DataScannerQRView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        // Called right after presentation (and on state changes) — start the
        // camera once; throws only when scanning is unavailable (permission
        // denied / restricted), which leaves the system's own explanation UI.
        guard !context.coordinator.finished, !controller.isScanning else { return }
        try? controller.startScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        var finished = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let text = barcode.payloadStringValue, !text.isEmpty {
                    finished = true
                    dataScanner.stopScanning()
                    onFound(text)
                    return
                }
            }
        }
    }
}

/// AVFoundation QR scanner — fallback used where DataScanner is unsupported.
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onFound = onFound
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var found = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                let session = self.session
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                session.stopRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !found,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let text = object.stringValue else { return }
            found = true
            session.stopRunning()
            onFound?(text)
        }
    }
}
