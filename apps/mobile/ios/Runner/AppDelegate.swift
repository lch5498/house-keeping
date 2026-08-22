import ContactsUI
import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CNContactPickerDelegate {
  let pendingDeepLinkKey = "checky.pendingDeepLink"
  var initialDeepLink: String?
  var latestDeepLink: String?
  var deepLinkChannel: FlutterMethodChannel?
  var pendingContactResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      handleDeepLink(url, isInitial: true)
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      configureShareChannel(controller: controller)
      configurePhoneChannel(controller: controller)
      configureContactChannel(controller: controller)
      configureHomeWidgetChannel(controller: controller)
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

  func configureHomeWidgetChannel(controller: FlutterViewController) {
    let homeWidgetChannel = FlutterMethodChannel(
      name: "checky/home_widget",
      binaryMessenger: controller.binaryMessenger
    )

    homeWidgetChannel.setMethodCallHandler { call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let values = call.arguments as? [String: Any],
        let defaults = UserDefaults(suiteName: "group.com.family.checky.mobile")
      else {
        result(
          FlutterError(
            code: "home_widget_unavailable",
            message: "Home widget shared storage is unavailable",
            details: nil
          )
        )
        return
      }

      let schedule = values["schedule"] as? [String: Any]
      let rawItems = schedule?["items"] as? [Any] ?? []
      let items = rawItems.compactMap { $0 as? [String: Any] }
      let displayedItems = Array(items.prefix(5))
      let sourceMoreCount = schedule?["moreCount"] as? Int ?? 0
      defaults.set(schedule?["title"] as? String ?? "체키 오늘 일정", forKey: "schedule.title")
      defaults.set(schedule?["weekday"] as? String ?? "오늘", forKey: "schedule.weekday")
      defaults.set(schedule?["day"] as? String ?? "", forKey: "schedule.day")
      defaults.set(schedule?["fullDate"] as? String ?? "오늘", forKey: "schedule.fullDate")
      defaults.set(displayedItems.count, forKey: "schedule.itemCount")
      defaults.set(sourceMoreCount + max(items.count - displayedItems.count, 0), forKey: "schedule.moreCount")

      for index in 0..<5 {
        let item = index < displayedItems.count ? displayedItems[index] : nil
        defaults.set(item?["startsAt"] as? String ?? "", forKey: "schedule.item.\(index).startsAt")
        defaults.set(item?["endsAt"] as? String ?? "", forKey: "schedule.item.\(index).endsAt")
        defaults.set(item?["title"] as? String ?? "", forKey: "schedule.item.\(index).title")
        defaults.set(item?["memberName"] as? String ?? "", forKey: "schedule.item.\(index).memberName")
      }

      WidgetCenter.shared.reloadAllTimelines()
      result(nil)
    }
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
  }
}
