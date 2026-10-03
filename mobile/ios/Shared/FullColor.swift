import UIKit
import SwiftUI
import WidgetKit

/// Духи и цветные имена в виджетах новой iOS (владелец 03.10.2026). В режимах «Прозрачный» и
/// «Тонированный» iOS красит всё содержимое виджета в один цвет; цвет сохраняется только у
/// картинок с fullColor - поэтому там дух с именем рисуем картинкой. В обычном режиме и в
/// приложении - как есть.
struct FullColor<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.displayScale) private var scale
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if mode != .fullColor, let image = rendered() {
            Image(uiImage: image).widgetAccentedRenderingMode(.fullColor)
        } else {
            content
        }
    }

    @MainActor private func rendered() -> UIImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark))
        renderer.scale = scale
        return renderer.uiImage
    }
}
