/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Welcome screen that guides users through the DAT SDK registration process.
// This view is displayed when the app is not yet registered.
//

import ExternalAccessory
import MWDATCore
import NetworkExtension
import ObjectiveC
import OSLog
import SwiftUI
import UIKit

struct HomeScreenView: View {
  var viewModel: WearablesViewModel

  var body: some View {
    ZStack {
      Color.white.edgesIgnoringSafeArea(.all)

      VStack(spacing: 12) {
        EntitlementsDiagView()

        Spacer()

        Image(.cameraAccessIcon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120)

        VStack(spacing: 12) {
          TipRow(
            resource: .smartGlassesIcon,
            title: "Start a session",
            text: "Connect to your glasses to get started."
          )
          TipRow(
            resource: .videoIcon,
            title: "Start preview",
            text: "See the live camera feed from your glasses."
          )
          TipRow(
            resource: .tapIcon,
            title: "Capture",
            text: "Take photos and record video with audio from your glasses' microphone."
          )
        }

        Spacer()

        VStack(spacing: 20) {
          Text("You'll be redirected to the Meta AI app to confirm your connection.")
            .font(.system(size: 14))
            .foregroundStyle(.gray)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)

          CustomButton(
            title: viewModel.registrationState == .registering ? "Connecting…" : "Connect my glasses",
            style: .primary,
            isDisabled: viewModel.registrationState == .registering
          ) {
            viewModel.connectGlasses()
          }
        }
      }
      .padding(.all, 24)
    }
  }
}


enum EntitlementsDiag {
  static let required = [
    "com.apple.developer.networking.HotspotConfiguration",
    "com.apple.developer.networking.wifi-info",
  ]

  /// Entitlements from embedded.mobileprovision, or nil when the profile is missing or unreadable.
  static func profileEntitlements() -> [String: Any]? {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
    else { return nil }
    let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
    guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    else { return nil }
    return plist["Entitlements"] as? [String: Any]
  }

  static func report() -> [(String, Bool)] {
    let ents = profileEntitlements() ?? [:]
    return required.map { ($0, ents[$0] != nil) }
  }
}

struct EntitlementsDiagView: View {
  private let rows = EntitlementsDiag.report()
  private let hasProfile = EntitlementsDiag.profileEntitlements() != nil

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(hasProfile ? "Разрешения подписи" : "Профиль подписи не найден")
        .font(.system(size: 13, weight: .semibold))
      ForEach(rows, id: \.0) { name, ok in
        Text("\(ok ? "OK" : "НЕТ")  \(name.replacingOccurrences(of: "com.apple.developer.networking.", with: ""))")
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(ok ? .green : .red)
      }
      Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "-")")
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.gray)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.black.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

/// GlassCam: Bluetooth accessories visible to the app and the recent log of this process
/// (SDK messages included), so a failed preview can be diagnosed on the phone.
enum DiagLog {
  static func accessories() -> String {
    let list = EAAccessoryManager.shared().connectedAccessories
    if list.isEmpty { return "EA: нет аксессуаров" }
    return list.map { "EA: \($0.name) [\($0.protocolStrings.joined(separator: ","))] conn=\($0.isConnected)" }
      .joined(separator: "\n")
  }

  static func recent(minutes: Double = 10, limit: Int = 400) -> String {
    do {
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let pos = store.position(date: Date().addingTimeInterval(-minutes * 60))
      let lines = try store.getEntries(at: pos)
        .compactMap { $0 as? OSLogEntryLog }
        .map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.category)] \($0.composedMessage)" }
      return lines.suffix(limit).joined(separator: "\n")
    } catch {
      return "Лог недоступен: \(error.localizedDescription)"
    }
  }
}

struct DiagLogView: View {
  @State private var text = "Загрузка..."
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(text)
          .font(.system(size: 10, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
      }
      .navigationTitle("Лог")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Копировать") { UIPasteboard.general.string = text }
        }
      }
      .task { text = DiagLog.accessories() + "\n\n" + DiagLog.recent() }
    }
  }
}

// MARK: - GlassCam: manual Wi-Fi join instead of the Hotspot entitlement

/// Box for a completion handler crossing threads (Swift 6 strict concurrency).
struct HotspotCompletion: @unchecked Sendable {
  let call: (Error?) -> Void
}

/// The SDK asks NEHotspotConfigurationManager to join the glasses' SoftAP; a free Apple ID
/// has no Hotspot entitlement, so that call fails. We swap the method: show SSID and password,
/// the user joins in Settings by hand, then "Я подключился" reports success to the SDK.
@MainActor @Observable
final class HotspotBridge {
  static let shared = HotspotBridge()

  var ssid: String?
  var passphrase: String?
  var details: String = ""
  var waiting = false
  @ObservationIgnored private var completion: HotspotCompletion?

  nonisolated static func install() {
    swap(NEHotspotConfigurationManager.self,
         #selector(NEHotspotConfigurationManager.apply(_:completionHandler:)),
         #selector(NEHotspotConfigurationManager.gc_apply(_:completionHandler:)))
    swap(NEHotspotConfigurationManager.self,
         #selector(NEHotspotConfigurationManager.getConfiguredSSIDs(completionHandler:)),
         #selector(NEHotspotConfigurationManager.gc_getConfiguredSSIDs(completionHandler:)))
  }

  nonisolated private static func swap(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
    guard let a = class_getInstanceMethod(cls, original),
      let b = class_getInstanceMethod(cls, replacement)
    else {
      NSLog("[GlassCam] swizzle failed for \(original)")
      return
    }
    method_exchangeImplementations(a, b)
    NSLog("[GlassCam] swizzled \(original)")
  }

  /// String ivars of the configuration (passphrase is not public API).
  nonisolated static func stringIvars(of object: AnyObject) -> [String: String] {
    var result: [String: String] = [:]
    var count: UInt32 = 0
    guard let ivars = class_copyIvarList(type(of: object), &count) else { return result }
    defer { free(ivars) }
    for i in 0..<Int(count) {
      let ivar = ivars[i]
      guard let cname = ivar_getName(ivar), let enc = ivar_getTypeEncoding(ivar),
        String(cString: enc).hasPrefix("@")
      else { continue }
      if let value = object_getIvar(object, ivar) as? String {
        result[String(cString: cname)] = value
      }
    }
    return result
  }

  /// Called from the swizzled apply on any thread; only Sendable values cross into the main actor.
  nonisolated static func intercept(_ configuration: NEHotspotConfiguration, completion: HotspotCompletion?) {
    let fields = stringIvars(of: configuration)
    let pass = fields.first { $0.key.lowercased().contains("pass") }?.value
    let ssid = configuration.ssid
    let details = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
    NSLog("[GlassCam] hotspot apply ssid=\(ssid) fields=\(fields.keys.sorted())")
    Task { @MainActor in
      let bridge = HotspotBridge.shared
      bridge.ssid = ssid
      bridge.passphrase = pass
      bridge.details = details
      bridge.completion = completion
      bridge.waiting = true
    }
  }

  func confirmJoined() {
    waiting = false
    completion?.call(nil)
    completion = nil
  }

  func cancel() {
    waiting = false
    completion?.call(NSError(domain: NEHotspotConfigurationErrorDomain, code: NEHotspotConfigurationError.userDenied.rawValue, userInfo: nil))
    completion = nil
  }

}

extension NEHotspotConfigurationManager {
  @objc dynamic func gc_apply(_ configuration: NEHotspotConfiguration, completionHandler: ((Error?) -> Void)?) {
    HotspotBridge.intercept(configuration, completion: completionHandler.map { HotspotCompletion(call: $0) })
  }

  @objc dynamic func gc_getConfiguredSSIDs(completionHandler: @escaping ([String]) -> Void) {
    let handler = SSIDHandler(call: completionHandler)
    Task { @MainActor in handler.call(HotspotBridge.shared.ssid.map { [$0] } ?? []) }
  }
}

struct SSIDHandler: @unchecked Sendable {
  let call: ([String]) -> Void
}

struct HotspotPromptView: View {
  @State private var bridge = HotspotBridge.shared

  var body: some View {
    if bridge.waiting {
      VStack(alignment: .leading, spacing: 10) {
        Text("Подключи iPhone к Wi-Fi очков")
          .font(.headline)
        Text("Настройки → Wi-Fi → эта сеть (если её нет в списке - «Другая»).")
          .font(.subheadline)
        Group {
          Text("Сеть: \(bridge.ssid ?? "-")")
          Text("Пароль: \(bridge.passphrase ?? "не найден")")
        }
        .font(.system(size: 15, design: .monospaced))
        .textSelection(.enabled)
        HStack {
          Button("Копировать пароль") { UIPasteboard.general.string = bridge.passphrase }
            .buttonStyle(.bordered)
          Button("Я подключился") { bridge.confirmJoined() }
            .buttonStyle(.borderedProminent)
        }
        Button("Отмена", role: .cancel) { bridge.cancel() }
        Text(bridge.details)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      .padding(16)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .padding(16)
    }
  }
}
