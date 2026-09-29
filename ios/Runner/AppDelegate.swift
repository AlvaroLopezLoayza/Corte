import Flutter
import ImageIO
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CorteJpeg") else { return }
    // JPEG con el codificador del sistema (ImageIO): RGBA crudo -> CGImage -> JPEG, fuera del hilo principal.
    FlutterMethodChannel(name: "corte/jpeg", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
      guard let a = call.arguments as? [String: Any], let w = a["w"] as? Int, let h = a["h"] as? Int,
        let px = a["px"] as? FlutterStandardTypedData, let q = a["q"] as? Int
      else {
        result(FlutterError(code: "jpeg", message: "argumentos inválidos", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let jpg = AppDelegate.jpeg(px.data, w, h, CGFloat(q) / 100)
        DispatchQueue.main.async {
          if let jpg = jpg {
            result(FlutterStandardTypedData(bytes: jpg))
          } else {
            result(FlutterError(code: "jpeg", message: "no se pudo codificar", details: nil))
          }
        }
      }
    }
  }

  static func jpeg(_ px: Data, _ w: Int, _ h: Int, _ quality: CGFloat) -> Data? {
    guard let provider = CGDataProvider(data: px as CFData),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let img = CGImage(
        width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(dest) ? out as Data : nil
  }
}
