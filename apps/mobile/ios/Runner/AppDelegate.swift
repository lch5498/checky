import ContactsUI
import BackgroundTasks
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CNContactPickerDelegate {
  let pendingDeepLinkKey = "checky.pendingDeepLink"
  var initialDeepLink: String?
  var latestDeepLink: String?
  var deepLinkChannel: FlutterMethodChannel?
  var pendingContactResult: FlutterResult?
  private var widgetRefreshChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    CheckyWidgetRefreshScheduler.register()

    if let url = launchOptions?[.url] as? URL {
      handleDeepLink(url, isInitial: true)
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      configureWidgetRefreshChannel(messenger: controller.binaryMessenger)
      configureShareChannel(controller: controller)
      configurePhoneChannel(controller: controller)
      configureContactChannel(controller: controller)
      let preferencesChannel = FlutterMethodChannel(
        name: "checky/preferences",
        binaryMessenger: controller.binaryMessenger
      )

      preferencesChannel.setMethodCallHandler { call, result in
        guard
          let arguments = call.arguments as? [String: Any],
          let key = arguments["key"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "key is required",
              details: nil
            )
          )
          return
        }

        switch call.method {
        case "getString":
          result(UserDefaults.standard.string(forKey: key))
        case "setString":
          guard let value = arguments["value"] as? String else {
            result(
              FlutterError(
                code: "invalid_arguments",
                message: "value is required",
                details: nil
              )
            )
            return
          }
          UserDefaults.standard.set(value, forKey: key)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      deepLinkChannel = FlutterMethodChannel(
        name: "checky/deep_links",
        binaryMessenger: controller.binaryMessenger
      )

      deepLinkChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "getInitialLink":
          result(self?.consumeDeepLink(preferred: self?.initialDeepLink))
          self?.initialDeepLink = nil
        case "getLatestLink":
          result(self?.consumeDeepLink(preferred: self?.latestDeepLink))
          self?.latestDeepLink = nil
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func configureShareChannel(controller: FlutterViewController) {
    let shareChannel = FlutterMethodChannel(
      name: "checky/share",
      binaryMessenger: controller.binaryMessenger
    )

    shareChannel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard call.method == "shareText" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let self, let controller else {
        result(
          FlutterError(
            code: "view_controller_unavailable",
            message: "Flutter view controller is unavailable",
            details: nil
          )
        )
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let text = arguments["text"] as? String,
        !text.isEmpty
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "text is required",
            details: nil
          )
        )
        return
      }

      let subject = arguments["subject"] as? String ?? "체키 그룹 초대"
      let presenter = self.topViewController(from: controller)

      let activityController = UIActivityViewController(
        activityItems: [text],
        applicationActivities: nil
      )
      activityController.setValue(subject, forKey: "subject")

      if let popover = activityController.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 0,
          height: 0
        )
        popover.permittedArrowDirections = []
      }

      presenter.present(activityController, animated: true) {
        result(nil)
      }
    }
  }

  func configurePhoneChannel(controller: FlutterViewController) {
    let phoneChannel = FlutterMethodChannel(
      name: "checky/phone",
      binaryMessenger: controller.binaryMessenger
    )

    phoneChannel.setMethodCallHandler { call, result in
      guard call.method == "dial" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let phoneNumber = arguments["phoneNumber"] as? String,
        !phoneNumber.isEmpty,
        let encoded = phoneNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
        let url = URL(string: "tel://\(encoded)")
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "phoneNumber is required",
            details: nil
          )
        )
        return
      }

      UIApplication.shared.open(url, options: [:]) { success in
        if success {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "dial_failed",
              message: "Could not open phone app",
              details: nil
            )
          )
        }
      }
    }
  }

  func configureContactChannel(controller: FlutterViewController) {
    let contactChannel = FlutterMethodChannel(
      name: "checky/contacts",
      binaryMessenger: controller.binaryMessenger
    )

    contactChannel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard call.method == "pickPhoneContact" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let self, let controller else {
        result(
          FlutterError(
            code: "view_controller_unavailable",
            message: "Flutter view controller is unavailable",
            details: nil
          )
        )
        return
      }

      guard self.pendingContactResult == nil else {
        result(
          FlutterError(
            code: "pick_in_progress",
            message: "Contact picker is already open",
            details: nil
          )
        )
        return
      }

      self.pendingContactResult = result
      let picker = CNContactPickerViewController()
      picker.delegate = self
      picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
      self.topViewController(from: controller).present(picker, animated: true)
    }
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    guard let phoneNumber = contact.phoneNumbers.first?.value.stringValue, !phoneNumber.isEmpty else {
      finishContactPick(errorCode: "phone_number_unavailable")
      return
    }

    finishContactPick(name: CNContactFormatter.string(from: contact, style: .fullName) ?? "", phoneNumber: phoneNumber)
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
    guard let phoneNumber = contactProperty.value as? CNPhoneNumber else {
      finishContactPick(errorCode: "phone_number_unavailable")
      return
    }

    let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? ""
    finishContactPick(name: name, phoneNumber: phoneNumber.stringValue)
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    finishContactPick(errorCode: "cancelled")
  }

  private func finishContactPick(name: String, phoneNumber: String) {
    pendingContactResult?([
      "name": name,
      "phoneNumber": phoneNumber,
    ])
    pendingContactResult = nil
  }

  private func finishContactPick(errorCode: String) {
    pendingContactResult?(
      FlutterError(
        code: errorCode,
        message: "Contact pick failed",
        details: nil
      )
    )
    pendingContactResult = nil
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if handleDeepLink(url, isInitial: false) {
      return true
    }

    return super.application(app, open: url, options: options)
  }

  @discardableResult
  func handleDeepLink(_ url: URL, isInitial: Bool) -> Bool {
    guard
      let scheme = url.scheme,
      let host = url.host,
      (scheme == "checky" || scheme == "favis"),
      host == "family-invite"
    else {
      return false
    }

    let value = url.absoluteString
    latestDeepLink = value
    UserDefaults.standard.set(value, forKey: pendingDeepLinkKey)
    if isInitial && initialDeepLink == nil {
      initialDeepLink = value
    }

    DispatchQueue.main.async { [weak self] in
      self?.deepLinkChannel?.invokeMethod("onLink", arguments: value)
    }

    return true
  }

  func consumeDeepLink(preferred: String?) -> String? {
    if let preferred, !preferred.isEmpty {
      UserDefaults.standard.removeObject(forKey: pendingDeepLinkKey)
      return preferred
    }

    guard let pending = UserDefaults.standard.string(forKey: pendingDeepLinkKey), !pending.isEmpty else {
      return nil
    }

    UserDefaults.standard.removeObject(forKey: pendingDeepLinkKey)
    return pending
  }

  func topViewController(from controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController {
      return topViewController(from: presented)
    }

    if let navigation = controller as? UINavigationController,
       let visible = navigation.visibleViewController {
      return topViewController(from: visible)
    }

    if let tab = controller as? UITabBarController,
       let selected = tab.selectedViewController {
      return topViewController(from: selected)
    }

    return controller
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureWidgetRefreshChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  func configureWidgetRefreshChannel(messenger: FlutterBinaryMessenger) {
    widgetRefreshChannel = FlutterMethodChannel(name: "checky/widget_refresh", binaryMessenger: messenger)
    widgetRefreshChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "schedule":
        guard let args = call.arguments as? [String: Any], let handle = args["callbackHandle"] as? NSNumber else {
          result(FlutterError(code: "missing_callback", message: "Background callback missing", details: nil))
          return
        }
        UserDefaults.standard.set(handle, forKey: "checky.widgetRefresh.callback")
        UserDefaults.standard.set(true, forKey: "checky.widgetRefresh.initialized")
        CheckyWidgetRefreshScheduler.ensureScheduled(result: result)
      case "status":
        CheckyWidgetRefreshScheduler.status(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// iOS owns scheduling and waits for the headless Dart engine's ready signal.
// Android continues to use WorkManager.
enum CheckyWidgetRefreshScheduler {
  // Separate identifier prevents the legacy plugin from registering a second
  // handler for the new job when upgrading an already installed app.
  static let identifier = "com.family.checky.mobile.widgetRefresh.v2"
  private static var scheduling = false
  private static var waiting: [FlutterResult] = []
  private static var worker: CheckyWidgetRefreshWorker?

  static func register() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.family.checky.mobile.homeWidgetRefresh")
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let task = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      DispatchQueue.main.async {
        ensureScheduled { _ in }
        guard worker == nil else {
          task.setTaskCompleted(success: false)
          return
        }
        let next = CheckyWidgetRefreshWorker(task: task) { worker = nil }
        worker = next
        next.start()
      }
    }
    if !registered {
      UserDefaults.standard.set("handler_registration_failed", forKey: "checky.widgetRefresh.scheduleError")
    }
  }

  static func ensureScheduled(result: @escaping FlutterResult) {
    waiting.append(result)
    guard !scheduling else { return }
    scheduling = true
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      DispatchQueue.main.async {
        let outcome: Any
        if requests.contains(where: { $0.identifier == identifier }) {
          // Keep the existing earliest date; repeated app opens must not defer it.
          outcome = true
          UserDefaults.standard.removeObject(forKey: "checky.widgetRefresh.scheduleError")
        } else {
          let request = BGAppRefreshTaskRequest(identifier: identifier)
          request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
          do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.removeObject(forKey: "checky.widgetRefresh.scheduleError")
            outcome = true
          } catch {
            let error = error as NSError
            let code = "\(error.domain):\(error.code)"
            UserDefaults.standard.set(code, forKey: "checky.widgetRefresh.scheduleError")
            outcome = FlutterError(code: "schedule_failed", message: code, details: nil)
          }
        }
        let callbacks = waiting
        waiting = []
        scheduling = false
        callbacks.forEach { $0(outcome) }
      }
    }
  }

  static func restoreIfNeeded() {
    guard UserDefaults.standard.bool(forKey: "checky.widgetRefresh.initialized") else { return }
    ensureScheduled { _ in }
  }

  static func status(result: @escaping FlutterResult) {
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      DispatchQueue.main.async {
        let request = requests.first { $0.identifier == identifier }
        let refreshStatus: String
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: refreshStatus = "available"
        case .denied: refreshStatus = "denied"
        case .restricted: refreshStatus = "restricted"
        @unknown default: refreshStatus = "unknown"
        }
        var values: [String: Any] = [
          "pending": request != nil,
          "backgroundRefresh": refreshStatus,
          "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ]
        if let date = request?.earliestBeginDate {
          values["earliestBeginAt"] = ISO8601DateFormatter().string(from: date)
        }
        values["scheduleError"] = UserDefaults.standard.string(forKey: "checky.widgetRefresh.scheduleError")
        values["nativeStage"] = UserDefaults.standard.string(forKey: "checky.widgetRefresh.nativeStage")
        values["nativeStartedAt"] = UserDefaults.standard.string(forKey: "checky.widgetRefresh.nativeStartedAt")
        values["nativeFinishedAt"] = UserDefaults.standard.string(forKey: "checky.widgetRefresh.nativeFinishedAt")
        result(values)
      }
    }
  }
}

private final class CheckyWidgetRefreshWorker {
  private let task: BGAppRefreshTask
  private let onFinish: () -> Void
  private var engine: FlutterEngine?
  private var channel: FlutterMethodChannel?
  private var watchdog: Timer?
  private var finished = false
  private var ready = false

  init(task: BGAppRefreshTask, onFinish: @escaping () -> Void) {
    self.task = task
    self.onFinish = onFinish
  }

  func start() {
    let defaults = UserDefaults.standard
    defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "checky.widgetRefresh.nativeStartedAt")
    stage("started")
    guard let handle = defaults.object(forKey: "checky.widgetRefresh.callback") as? NSNumber,
          let info = FlutterCallbackCache.lookupCallbackInformation(handle.int64Value) else {
      finish(success: false, stage: "callback_missing")
      return
    }
    let engine = FlutterEngine(name: "checky.widget.refresh", project: nil, allowHeadlessExecution: true)
    self.engine = engine
    let channel = FlutterMethodChannel(name: "checky/widget_worker", binaryMessenger: engine.binaryMessenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.finished else { result(false); return }
      guard call.method == "ready" else { result(FlutterMethodNotImplemented); return }
      result(true)
      guard !self.ready else { return }
      self.ready = true
      self.stage("dart_ready")
      // Dart installs its handler before sending ready. No startup race.
      self.channel?.invokeMethod("refresh", arguments: nil) { [weak self] value in
        guard let self = self else { return }
        let success = (value as? Bool) == true
        self.finish(success: success, stage: success ? "completed" : "refresh_failed")
      }
    }
    task.expirationHandler = { [weak self] in
      DispatchQueue.main.async { self?.finish(success: false, stage: "expired") }
    }
    watchdog = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
      self?.finish(success: false, stage: "timeout")
    }
    guard engine.run(withEntrypoint: info.callbackName, libraryURI: info.callbackLibraryPath) else {
      finish(success: false, stage: "engine_failed")
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
  }

  private func stage(_ value: String) {
    UserDefaults.standard.set(value, forKey: "checky.widgetRefresh.nativeStage")
  }

  private func finish(success: Bool, stage value: String) {
    guard !finished else { return }
    finished = true
    stage(value)
    UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: "checky.widgetRefresh.nativeFinishedAt")
    watchdog?.invalidate()
    watchdog = nil
    channel?.setMethodCallHandler(nil)
    channel = nil
    engine?.destroyContext()
    engine = nil
    task.setTaskCompleted(success: success)
    onFinish()
  }
}
