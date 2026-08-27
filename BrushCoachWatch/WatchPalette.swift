import SwiftUI

/// The watch app's colours, in one place.
///
/// These were previously duplicated as `private extension Color` in both
/// CoachView and RecordingView, which meant a third screen could not use them
/// without copying the values a third time.
extension Color {
    // Coach
    static let watchInk = Color(red: 0.027, green: 0.102, blue: 0.141)
    static let watchBlue = Color(red: 0.23, green: 0.69, blue: 0.86)
    static let watchMint = Color(red: 0.498, green: 0.878, blue: 0.765)
    static let watchCoral = Color(red: 0.98, green: 0.41, blue: 0.37)

    // Capture
    static let captureInk = Color(red: 0.025, green: 0.055, blue: 0.09)
    static let enamel = Color(red: 0.96, green: 0.98, blue: 0.99)
    static let rinseBlue = Color(red: 0.23, green: 0.72, blue: 0.94)
    static let recordCoral = Color(red: 1.0, green: 0.36, blue: 0.34)
    static let mintSignal = Color(red: 0.38, green: 0.89, blue: 0.69)
}
