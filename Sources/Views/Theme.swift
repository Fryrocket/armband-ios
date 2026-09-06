import SwiftUI

extension Color {
    /// Classic hunter green (#355E3B).
    static let hunterGreen = Color(red: 53 / 255, green: 94 / 255, blue: 59 / 255)
}

extension View {
    func hunterGreenScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.hunterGreen.ignoresSafeArea())
            .toolbarBackground(Color.hunterGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.hunterGreen, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
    }
}
