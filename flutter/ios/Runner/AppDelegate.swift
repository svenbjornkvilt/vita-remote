import UIKit
import Flutter
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    dummyMethodToEnforceBundling();
    if let controller = window?.rootViewController as? FlutterViewController {
      registerBroadcastChannel(controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }

  private func registerBroadcastChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "fo.vita.remote/broadcast",
                                       binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "appGroupDir":
        result(FileManager.default
          .containerURL(forSecurityApplicationGroupIdentifier: "group.fo.vita.remote")?.path)
      case "start":
        self.showBroadcastPicker(in: controller.view)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // iOS has no API to start a broadcast directly; tapping the system picker's button is the accepted workaround.
  private func showBroadcastPicker(in view: UIView) {
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    picker.preferredExtension = "fo.vita.remote.broadcast"
    picker.showsMicrophoneButton = false
    picker.isHidden = true
    view.addSubview(picker)
    for case let button as UIButton in picker.subviews {
      button.sendActions(for: .touchUpInside)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { picker.removeFromSuperview() }
  }
}
