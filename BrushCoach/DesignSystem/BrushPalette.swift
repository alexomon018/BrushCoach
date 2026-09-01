import BrushDesign
import SwiftUI

/// The companion app's names for the brand colours.
///
/// The values live in `BrushBrand` so the Watch app cannot drift from them; the
/// names stay local because they read better at each call site.
extension Color {
    static let deepInk = BrushBrand.ink
    static let enamelWash = BrushBrand.enamelWash
    static let rinseBlue = BrushBrand.blue
    static let mintFresh = BrushBrand.mint
    static let sketchLavender = BrushBrand.lavender
    static let achievementGold = BrushBrand.gold
    static let mintDeep = BrushBrand.mintDeep
    static let coachCoral = BrushBrand.coral
}
