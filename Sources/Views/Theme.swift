import SwiftUI

extension Color {
    /// Dark forest green (#0C241C).
    static let forestGreen = Color(red: 12 / 255, green: 36 / 255, blue: 28 / 255)
    /// Warm ivory for titles on forest green (#F3E9D7).
    static let titleIvory = Color(red: 243 / 255, green: 233 / 255, blue: 215 / 255)
    /// Fire-engine red (#CE2029).
    static let fireEngineRed = Color(red: 206 / 255, green: 32 / 255, blue: 41 / 255)
}

extension View {
    func forestGreenScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.forestGreen.ignoresSafeArea())
            .toolbarBackground(Color.forestGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.forestGreen, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
    }

    func professionalNavTitle(_ title: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.titleIvory)
                }
            }
    }
}
