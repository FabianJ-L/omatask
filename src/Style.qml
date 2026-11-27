import QtQuick

// The app's design tokens: one spacing scale, one type scale, three corner
// radii and three surface layers. Every page sizes itself from these, so
// gaps and text line up from page to page. Colors still come from the
// Omarchy theme, so a theme switch recolors everything live.
QtObject {
    // Spacing
    readonly property int xs: 4
    readonly property int s: 8
    readonly property int m: 12
    readonly property int l: 16
    readonly property int xl: 24

    // Type
    readonly property int caption: 11
    readonly property int small: 12
    readonly property int body: 13
    readonly property int title: 15
    readonly property int h2: 20
    readonly property int display: 28

    // Corners, capped by Hyprland's rounding (square themes stay square).
    readonly property int rSmall: Math.min(4, theme.radius)
    readonly property int rMed: Math.min(8, theme.radius)
    readonly property int rLarge: Math.min(12, theme.radius + 4)

    // Surfaces: the rail sits deepest, pages on the canvas, content in cards.
    // The window itself is see-through like the terminal, so the compositor's
    // blur shows behind it; the layers on top only tint it. Popups use the
    // solid colors, since they sit over other content of the same window.
    readonly property color window: Qt.alpha(theme.colors.darkBackground, 0.7)
    readonly property color rail: Qt.alpha(theme.colors.darkerBackground, 0.45)
    readonly property color canvas: "transparent"
    readonly property color card: Qt.alpha(theme.colors.background, 0.55)
    readonly property color cardSolid: theme.colors.background
    readonly property color raised: Qt.alpha(theme.colors.lighterBackground, 0.8)

    // Sizes
    readonly property int row: 34
    readonly property int control: 32
}
