import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Brightness / contrast / gamma applied to comic pages.
/// Brightness and contrast run as cheap SwiftUI modifiers; gamma needs a
/// Core Image pass, so processed images are cached.
nonisolated struct ImageAdjustments: Equatable {
    var brightness: Double = 0      // -0.5 ... 0.5
    var contrast: Double = 1        //  0.5 ... 1.8
    var gamma: Double = 1           //  0.4 ... 2.2
    var grayscale: Bool = false
    /// Stretches levels — rescues washed-out old scans.
    var autoContrast: Bool = false
    /// Trims uniform scan borders so the art fills more of the window.
    var autoCrop: Bool = false
    /// Quarter turns applied to every page: 0, 1, 2, 3.
    var rotation: Int = 0

    static let neutral = ImageAdjustments()

    var isNeutral: Bool {
        abs(brightness) < 0.001 && abs(contrast - 1) < 0.001 && abs(gamma - 1) < 0.001
            && !grayscale && !autoContrast && !autoCrop && rotation == 0
    }

    /// Anything needing a Core Image / pixel pass rather than a cheap modifier.
    var needsProcessing: Bool {
        abs(gamma - 1) >= 0.001 || autoContrast || autoCrop
    }

    /// Cache key for processed output.
    var processingSignature: String {
        "g\(String(format: "%.2f", gamma))-ac\(autoContrast ? 1 : 0)-cr\(autoCrop ? 1 : 0)"
    }

    var rotationAngle: Angle { .degrees(Double(rotation) * 90) }

    static let brightnessKey = "adjustBrightness"
    static let contrastKey = "adjustContrast"
    static let gammaKey = "adjustGamma"
    static let grayscaleKey = "adjustGrayscale"
    static let autoContrastKey = "adjustAutoContrast"
    static let autoCropKey = "adjustAutoCrop"
    static let rotationKey = "adjustRotation"
}

/// Applies gamma with Core Image and caches the result per image + value.
nonisolated final class GammaProcessor: @unchecked Sendable {
    static let shared = GammaProcessor()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 8
    }

    /// Applies every pixel-level adjustment in one pass.
    func process(_ image: NSImage, with adjustments: ImageAdjustments, key: String) -> NSImage {
        guard adjustments.needsProcessing else { return image }

        let cacheKey = "\(key)#\(adjustments.processingSignature)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        guard let tiff = image.tiffRepresentation,
              var ci = CIImage(data: tiff) else { return image }

        if adjustments.autoContrast {
            // Apple's own analysis pass — reliable on faded scans.
            for filter in ci.autoAdjustmentFilters(options: [.enhance: true, .redEye: false]) {
                filter.setValue(ci, forKey: kCIInputImageKey)
                if let output = filter.outputImage { ci = output }
            }
        }

        if abs(adjustments.gamma - 1) >= 0.001 {
            let filter = CIFilter.gammaAdjust()
            filter.inputImage = ci
            filter.power = Float(adjustments.gamma)
            if let output = filter.outputImage { ci = output }
        }

        if adjustments.autoCrop, let trimmed = cropRect(for: ci) {
            ci = ci.cropped(to: trimmed)
        }

        guard let cgImage = context.createCGImage(ci, from: ci.extent) else { return image }
        let result = NSImage(
            cgImage: cgImage,
            size: NSSize(width: ci.extent.width, height: ci.extent.height)
        )
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    /// Finds the content box by scanning a downscaled copy for rows and columns
    /// that are near-uniform border colour. Cheap enough to run per page.
    private func cropRect(for image: CIImage) -> CGRect? {
        let extent = image.extent
        guard extent.width > 40, extent.height > 40 else { return nil }

        let sampleWidth = 160
        let scale = CGFloat(sampleWidth) / extent.width
        let small = image.transformed(by: .init(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(small, from: small.extent) else { return nil }

        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        func luma(_ x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 4
            return (Int(pixels[i]) * 299 + Int(pixels[i + 1]) * 587 + Int(pixels[i + 2]) * 114) / 1000
        }

        // Border colour taken from the corners.
        let corners = [luma(0, 0), luma(width - 1, 0), luma(0, height - 1), luma(width - 1, height - 1)]
        let border = corners.reduce(0, +) / 4
        let tolerance = 26

        func rowIsBorder(_ y: Int) -> Bool {
            var off = 0
            for x in stride(from: 0, to: width, by: 2) where abs(luma(x, y) - border) > tolerance {
                off += 1
                if off > width / 40 { return false }
            }
            return true
        }
        func columnIsBorder(_ x: Int) -> Bool {
            var off = 0
            for y in stride(from: 0, to: height, by: 2) where abs(luma(x, y) - border) > tolerance {
                off += 1
                if off > height / 40 { return false }
            }
            return true
        }

        var top = 0, bottom = height - 1, left = 0, right = width - 1
        while top < bottom, rowIsBorder(top) { top += 1 }
        while bottom > top, rowIsBorder(bottom) { bottom -= 1 }
        while left < right, columnIsBorder(left) { left += 1 }
        while right > left, columnIsBorder(right) { right -= 1 }

        // Ignore trivial or implausible crops.
        let keptW = CGFloat(right - left) / CGFloat(width)
        let keptH = CGFloat(bottom - top) / CGFloat(height)
        guard keptW < 0.98 || keptH < 0.98, keptW > 0.4, keptH > 0.4 else { return nil }

        let inverseScale = extent.width / CGFloat(width)
        // CIImage's origin is bottom-left; the bitmap scan was top-down.
        return CGRect(
            x: CGFloat(left) * inverseScale,
            y: CGFloat(height - 1 - bottom) * inverseScale,
            width: CGFloat(right - left) * inverseScale,
            height: CGFloat(bottom - top) * inverseScale
        ).intersection(extent)
    }

    func clear() { cache.removeAllObjects() }
}

/// Slider panel shown in the reader.
struct AdjustmentsPanel: View {
    @Binding var adjustments: ImageAdjustments
    var glassEnabled: Bool
    var accent: Color
    /// Name shown on the per-series toggle.
    var seriesName: String = ""
    /// Whether this series has its own saved adjustments.
    var usesSeriesSettings: Bool = false
    var onSeriesScopeChange: (Bool) -> Void = { _ in }
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

            Divider().overlay(CGTheme.surface1)

            Toggle("Grayscale", isOn: $adjustments.grayscale)
                .toggleStyle(.switch)
                .tint(accent)
                .font(.callout)

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Auto contrast", isOn: $adjustments.autoContrast)
                    .toggleStyle(.switch)
                    .tint(accent)
                    .font(.callout)
                Text("Rescues faded or washed-out scans.")
                    .font(.caption2)
                    .foregroundStyle(CGTheme.subtext0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Auto-crop margins", isOn: $adjustments.autoCrop)
                    .toggleStyle(.switch)
                    .tint(accent)
                    .font(.callout)
                Text("Trims uniform scan borders. Off keeps the original scan intact.")
                    .font(.caption2)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Rotation").font(.caption).foregroundStyle(CGTheme.subtext1)
                    Spacer()
                    Text("\(adjustments.rotation * 90)°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
                HStack(spacing: 8) {
                    Button {
                        adjustments.rotation = (adjustments.rotation + 3) % 4
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    Button {
                        adjustments.rotation = (adjustments.rotation + 1) % 4
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    Button("Reset") { adjustments.rotation = 0 }
                        .disabled(adjustments.rotation == 0)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !seriesName.isEmpty {
                Divider().overlay(CGTheme.surface1)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { usesSeriesSettings },
                        set: { onSeriesScopeChange($0) }
                    )) {
                        Text("Save for \(seriesName)")
                            .font(.callout)
                            .foregroundStyle(CGTheme.text)
                    }
                    .toggleStyle(.checkbox)
                    .tint(accent)

                    Text(usesSeriesSettings
                         ? "These settings apply to this series only. Other comics keep the global ones."
                         : "Changes currently apply everywhere. Turn this on to keep them to this series.")
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Reset All") { adjustments = .neutral }
                    .disabled(adjustments.isNeutral)
                Spacer()
                if adjustments.needsProcessing {
                    Text("Re-renders pages")
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
        }
        .padding(20)
        .frame(width: 330)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle, cornerRadius: 14)
        .softGlow(accent, radius: 9)
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
