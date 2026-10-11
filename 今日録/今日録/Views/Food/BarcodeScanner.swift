import SwiftUI
import VisionKit

struct BarcodeScannerScreen: View {
    let onBarcode: (String) -> Void
    @State private var scannerError: String?

    var body: some View {
        Group {
            if !DataScannerViewController.isSupported {
                ContentUnavailableView(
                    "この端末では読み取れません",
                    systemImage: "barcode.viewfinder",
                    description: Text("バーコード読み取りは対応するiPhoneの実機でお試しください。商品名検索または手動入力も利用できます。")
                )
            } else if let scannerError {
                ContentUnavailableView(
                    "カメラを利用できません",
                    systemImage: "camera.fill",
                    description: Text(scannerError)
                )
            } else {
                BarcodeScannerController(onBarcode: onBarcode, scannerError: $scannerError)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("商品のバーコードを枠内に合わせてください")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 24)
                    }
            }
        }
    }
}

struct BarcodeScannerController: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    @Binding var scannerError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        guard DataScannerViewController.isAvailable else {
            scannerError = "カメラが使えないか、カメラへのアクセスが許可されていません。iPhoneの設定で今日録のカメラ利用を許可してください。"
            return scanner
        }
        do {
            try scanner.startScanning()
        } catch {
            scannerError = "カメラを起動できませんでした。カメラのアクセス許可をご確認ください。"
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onBarcode: (String) -> Void
        private var didReturnBarcode = false

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didReturnBarcode else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue,
                   !value.isEmpty {
                    didReturnBarcode = true
                    onBarcode(value)
                    return
                }
            }
        }
    }
}
