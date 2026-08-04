import SwiftUI

/// The Comic Ghost mascot, drawn in SwiftUI for empty states.
struct GhostMascot: View {
    var size: CGFloat = 120
    var accent: Color = CGTheme.lavender
    var holdingBook: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: size * 0.25)

            ghostShape
                .fill(accent)
                .overlay {
                    ghostShape.stroke(CGTheme.lavender.opacity(0.9), lineWidth: 2)
                }
                .frame(width: size, height: size * 1.15)
                .overlay(alignment: .top) {
                    HStack(spacing: size * 0.16) {
                        eye
                        eye
                    }
                    .padding(.top, size * 0.34)
                }
                .overlay(alignment: .bottom) {
                    if holdingBook {
                        book
                            .padding(.bottom, size * 0.14)
                    }
                }
        }
        .frame(width: size * 1.5, height: size * 1.5)
    }

    private var eye: some View {
        Circle()
            .fill(CGTheme.crust)
            .frame(width: size * 0.13, height: size * 0.13)
    }

    private var book: some View {
        HStack(spacing: 1) {
            page.rotationEffect(.degrees(-6), anchor: .bottomTrailing)
            page.rotationEffect(.degrees(6), anchor: .bottomLeading)
        }
        .frame(width: size * 0.5, height: size * 0.26)
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(CGTheme.crust.opacity(0.22))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(CGTheme.crust.opacity(0.35), lineWidth: 1.5)
            }
    }

    private var ghostShape: some Shape {
        GhostPath()
    }
}

/// Dome top, straight sides, scalloped hem.
struct GhostPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let radius = w / 2
        let hemHeight = h * 0.1
        let bodyBottom = h - hemHeight

        path.move(to: CGPoint(x: 0, y: bodyBottom))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(
            center: CGPoint(x: radius, y: radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: bodyBottom))

        let bumps = 4
        let bumpWidth = w / CGFloat(bumps)
        for index in 0..<bumps {
            let endX = w - CGFloat(index + 1) * bumpWidth
            path.addQuadCurve(
                to: CGPoint(x: endX, y: bodyBottom),
                control: CGPoint(x: endX + bumpWidth / 2, y: h)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// Empty-state layout using the mascot instead of an SF Symbol.
struct GhostEmptyState: View {
    let title: String
    let message: String
    var accent: Color = CGTheme.lavender

    var body: some View {
        VStack(spacing: 14) {
            GhostMascot(size: 110, accent: accent)

            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(CGTheme.text)

            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext0)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
