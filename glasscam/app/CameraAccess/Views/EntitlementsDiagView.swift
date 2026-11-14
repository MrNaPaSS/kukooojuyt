//
// EntitlementsDiagView.swift
//
// GlassCam: shows which entitlements survived re-signing (AltStore, free Apple ID).
// Streaming over Wi-Fi needs HotspotConfiguration; without it the SDK falls back to BLE only.
//

import SwiftUI

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
