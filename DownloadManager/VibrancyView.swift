import SwiftUI
import AppKit

// MARK: - Paylaşılan renk / materyal sabitleri
// Tüm uygulama bu değerleri kullanır. Opak renkler YOK — sistem vibrancy üstünde çalışır.

let appAccent  = Color(red: 0.36, green: 0.91, blue: 0.76)   // mint / ana vurgu

/// Kart / panel yüzeyi — ultra ince mat cam efekti
let glassSurface = Color.white.opacity(0.07)

/// Daha koyu panel (başlık çubukları, alt barlar)
let glassDeep    = Color.white.opacity(0.04)

/// Kart kenarlığı
let glassBorder  = Color.white.opacity(0.10)

/// Seçili öğe vurgusu
let glassSelected = appAccent.opacity(0.12)

// MARK: - NSVisualEffectView SwiftUI bridge
/// Tüm pencerelerin / sheet'lerin arka planına yerleştirilir.
/// Material: .sidebar → macOS sistem ayarları gibi koyu/açık blur
struct VisualEffectBackground: NSViewRepresentable {
    var material:     NSVisualEffectView.Material     = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state:        NSVisualEffectView.State        = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = state
        v.wantsLayer   = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = state
    }
}

// MARK: - View modifier — tek satırda arka plan uygula
extension View {
    /// Pencere/sheet arka planını vibrancy blur yapar
    func vibrancyBackground(
        material: NSVisualEffectView.Material = .sidebar,
        blending: NSVisualEffectView.BlendingMode = .behindWindow
    ) -> some View {
        self.background(
            VisualEffectBackground(material: material, blendingMode: blending)
                .ignoresSafeArea()
        )
    }

    /// Kart / panel yüzeyini frosted glass yapar
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(glassSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(glassBorder, lineWidth: 0.5))
    }
}

// MARK: - Vibrancy NSWindow yardımcısı
/// Bir NSWindow'u tam şeffaf + vibrancy yapar.
/// contentView'ı NSVisualEffectView içine alır.
func applyVibrancy(to window: NSWindow,
                   material: NSVisualEffectView.Material = .sidebar) {
    window.isOpaque                    = false
    window.backgroundColor             = .clear
    window.titlebarAppearsTransparent  = true
    window.hasShadow                   = true

    // Eğer zaten VibrancyHostingView ise tekrar uygulama
    guard !(window.contentView is VibrancyHostingView) else { return }

    guard let old = window.contentView else { return }

    let vev = VibrancyHostingView(frame: old.bounds)
    vev.material     = material
    vev.blendingMode = .behindWindow
    vev.state        = .active
    vev.autoresizingMask = [.width, .height]

    old.autoresizingMask = [.width, .height]
    vev.addSubview(old)
    window.contentView = vev
}

/// NSVisualEffectView subclass — tip kontrolü için
final class VibrancyHostingView: NSVisualEffectView {}
