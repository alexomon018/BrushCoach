import SwiftUI

/// Every brand colour in the product, defined exactly once.
///
/// The iPhone and Watch apps previously each carried their own palette. Three
/// values were byte-identical duplicates, and — worse — both defined
/// `Color.rinseBlue` with *different* values. They are separate targets, so that
/// compiled fine and simply meant the same symbol named two different colours
/// depending on which app you were reading.
///
/// The per-app palettes still exist and still use their own names: a Watch
/// screen legitimately wants a brighter blue than a sheet of white paper on a
/// phone. What they no longer do is carry literals. Every one of them resolves
/// to a case here, so a brand change happens in one file and a collision like
/// `rinseBlue` cannot come back.
public enum BrushBrand {
    // MARK: Core

    /// The near-black both apps use as their dark ground.
    public static let ink = Color(red: 0.027, green: 0.102, blue: 0.141)
    /// The signature mint. Interactive, positive, and the same on both devices.
    public static let mint = Color(red: 0.498, green: 0.878, blue: 0.765)
    /// Warnings and destructive actions.
    public static let coral = Color(red: 0.98, green: 0.41, blue: 0.37)

    // MARK: Blues
    //
    // One hue, three levels. The Watch runs on OLED at arm's length in a
    // bathroom, so it needs more saturation than the same blue on a phone.

    /// Companion default, on light backgrounds.
    public static let blue = Color(red: 0.145, green: 0.568, blue: 0.735)
    /// Watch coach screens, on the dark ground.
    public static let blueBright = Color(red: 0.23, green: 0.69, blue: 0.86)
    /// Watch capture screens, where it has to read as instrumentation.
    public static let blueVivid = Color(red: 0.23, green: 0.72, blue: 0.94)

    // MARK: Grounds

    /// The companion app's off-white page.
    public static let enamelWash = Color(red: 0.946, green: 0.976, blue: 0.973)
    /// The Watch capture screen's cooler, brighter white.
    public static let enamel = Color(red: 0.96, green: 0.98, blue: 0.99)
    /// A darker ink used only by capture, to separate a developer tool from the
    /// shipping coach screens.
    public static let captureInk = Color(red: 0.025, green: 0.055, blue: 0.09)

    // MARK: Accents

    /// Deep mint for controls that need contrast against white.
    public static let mintDeep = Color(red: 0.09, green: 0.55, blue: 0.43)
    /// Bright mint for live signal readouts on the Watch.
    public static let mintSignal = Color(red: 0.38, green: 0.89, blue: 0.69)
    public static let recordCoral = Color(red: 1.0, green: 0.36, blue: 0.34)
    public static let lavender = Color(red: 0.47, green: 0.36, blue: 0.88)
    public static let gold = Color(red: 0.95, green: 0.7, blue: 0.24)
}
