import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Brightness / contrast / gamma applied to comic pages.
/// Brightness and contrast run as cheap SwiftUI modifiers; gamma needs a
/// Core Image pass, so processed images are cached.
struct ImageAdjustments: Equatable {
    var brightness: Double = 0      // -0.5 ... 0.5
    var contrast: Double = 1        //  0.5 ... 1.8
    var gamma: Double = 1           //  0.4 ... 2.2

    static let neutral = ImageAdjustments()

    var isNeutral: Bool {
        abs(brightness) < 0.001 && abs(contrast - 1) < 0.001 && abs(gamma - 1) < 0.001
    }

    var needsGammaPass: Bool { abs(gamma - 1) >= 0.001 }

    // Persistence via AppStorage (three doubles, no codable dance needed).
    static let brightnessKey = "adjustBrightness"
    static let contrastKey = "adjustContrast"
    static let gammaKey = "adjustGamma"
}

/// Applies gamma with Core Image and caches the result per image + value.
nonisolated final class GammaProcessor: @unchecked Sendable {
    static let shared = GammaProcessor()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 8
    }

    func apply(gamma: Double, to image: NSImage, key: String) -> NSImage {
        guard abs(gamma - 1) >= 0.001 else { return image }

        let cacheKey = "\(key)#g\(String(format: "%.2f", gamma))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return image }

        let filter = CIFilter.gammaAdjust()
        filter.inputImage = ciImage
        filter.power = Float(gamma)

        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }

        let result = NSImage(cgImage: cgImage, size: image.size)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    func clear() { cache.removeAllObjects() }
}

/// Slider panel shown in the reader.
struct AdjustmentsPanel: View {
    @Binding var adjustments: ImageAdjustments
    var glassEnabled: Bool
    var accent: Color
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Image").font(.headline).foregroundStyle(CGTheme.text)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                }
                .buttonStyle(.plain)
            }

            slider("Brightness", value: $adjustments.brightness,
                   range: -0.5...0.5, neutral: 0, format: "%+.2f")
            slider("Contrast", value: $adjustments.contrast,
                   range: 0.5...1.8, neutral: 1, format: "%.2f")
            slider("Gamma", value: $adjustments.gamma,
                   range: 0.4...2.2, neutral: 1, format: "%.2f")

            HStack {
                Button("Reset") { adjustments = .neutral }
                    .disabled(adjustments.isNeutral)
                Spacer()
                if adjustments.needsGammaPass {
                    Text("Gamma re-renders pages")
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle, cornerRadius: 14)
        .softGlow(accent, radius: 16)
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(CGTheme.subtext1)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CGTheme.subtext0)
                Button {
                    value.wrappedValue = neutral
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                }
                .buttonStyle(.plain)
                .help("Reset \(label.lowercased())")
            }
            Slider(value: value, in: range)
                .tint(accent)
        }
    }
}
