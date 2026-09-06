import SwiftUI

extension Color {
    /// Deep forest green (#1B4332).
    static let forestGreen = Color(red: 27 / 255, green: 67 / 255, blue: 50 / 255)
    /// Warm ivory for titles on forest green (#F3E9D7).
    static let titleIvory = Color(red: 243 / 255, green: 233 / 255, blue: 215 / 255)
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
