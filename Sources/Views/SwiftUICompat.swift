//
//  SwiftUICompat.swift
//  ArmbandIOS
//
//  Host-build (macOS) shims for the handful of iOS-only SwiftUI text-field
//  modifiers used in the Settings form. iOS keeps the real UIKit-backed
//  modifiers; these no-ops only exist so `swift build` / `swift test` can
//  compile the shared views on the Mac. Not compiled for iOS.
//

#if !os(iOS)
import SwiftUI

extension View {
    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalizationShim?) -> some View { self }
    func keyboardType(_ type: KeyboardTypeShim) -> some View { self }
}

enum TextInputAutocapitalizationShim { case never, words, sentences, characters }
enum KeyboardTypeShim { case `default`, URL, emailAddress, numberPad, decimalPad, phonePad }
#endif
