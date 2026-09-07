import SwiftUI

extension Color {
    /// Dark forest green (#0C241C).
    static let forestGreen = Color(red: 12 / 255, green: 36 / 255, blue: 28 / 255)
    /// Warm ivory for titles on forest green (#F3E9D7).
    static let titleIvory = Color(red: 243 / 255, green: 233 / 255, blue: 215 / 255)
    /// Fire-engine red (#CE2029).
    static let fireEngineRed = Color(red: 206 / 255, green: 32 / 255, blue: 41 / 255)
}

struct ForestBackdrop: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            Image("ForestBackground")
                .resizable()
                .scaledToFill()
                .opacity(0.7)
            Color.black.opacity(0.35)
            PineSilhouette()
                .fill(Color.black.opacity(0.55))
                .frame(height: 220)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Simple pine-tree skyline so the nature motif remains if the photo is dimmed.
struct PineSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        let trees: [(peakX: CGFloat, peakY: CGFloat, halfW: CGFloat)] = [
            (0.06, 0.42, 0.10),
            (0.18, 0.18, 0.14),
            (0.32, 0.38, 0.11),
            (0.46, 0.12, 0.16),
            (0.62, 0.28, 0.13),
            (0.76, 0.16, 0.15),
            (0.90, 0.36, 0.12),
            (1.02, 0.48, 0.10),
        ]
        for t in trees {
            let cx = rect.width * t.peakX
            let top = rect.height * t.peakY
            let hw = rect.width * t.halfW
            path.addLine(to: CGPoint(x: cx - hw, y: rect.maxY))
            path.addLine(to: CGPoint(x: cx, y: top))
            path.addLine(to: CGPoint(x: cx + hw, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    func forestGreenScreen() -> some View {
        #if os(iOS)
        self
            .scrollContentBackground(.hidden)
            .background { ForestBackdrop() }
            .toolbarBackground(Color.black.opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.92), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
        #else
        self.background { ForestBackdrop() }
        #endif
    }

    func professionalNavTitle(_ title: String) -> some View {
        let titleView = Text(title)
            .font(.system(size: 24, weight: .semibold, design: .serif))
            .tracking(1.6)
            .foregroundStyle(Color.titleIvory)
        #if os(iOS)
        return self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleView
                }
            }
        #else
        return self.toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
        }
        #endif
    }
}
