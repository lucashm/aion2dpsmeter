pragma Singleton

import QtQuick
import Quickshell

// The app window's look (App.qml and its pages): an ordinary dark desktop
// window, unlike the see-through overlay widgets (Theme.qml).
Singleton {
    readonly property color bg: "#0B0C0E"
    readonly property color sidebar: "#0F1013"
    readonly property color card: "#121419"
    readonly property color cardEdge: "#22262E"
    readonly property color row: "#161920"
    readonly property color rowHover: "#1C2029"
    readonly property color text: "#E8EAED"
    readonly property color dim: "#A3A9B5"
    readonly property color faint: "#6C7380"
    readonly property color accent: "#3D8BFF"
    readonly property color accentSoft: Qt.rgba(0.24, 0.55, 1, 0.14)
    readonly property color good: "#34C77B"
    readonly property color warn: "#F2C15A"
    readonly property color cube: "#4FD1E8"

    // One family: Qt takes the whole string as a name, not a CSS fallback list.
    readonly property string font: "Noto Sans"
    readonly property int small: 12
    readonly property int normal: 14
    readonly property int large: 16
    readonly property int title: 24
    readonly property int radius: 8
    readonly property int pad: 16

    // Each genus's colour (dots, badges).
    readonly property var genusColors: ({ cogni: "#5F8CFF", fera: "#E8734A", natura: "#41C97A", varian: "#B36BFF", special: "#F2C15A" })
    function genusColor(g) {
        return genusColors[g] || faint;
    }
}
