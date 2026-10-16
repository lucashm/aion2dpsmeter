pragma Singleton

import QtQuick
import Quickshell

// Colours, sizes and number formatting shared by every widget.
Singleton {
    id: theme

    // Set from the settings file.
    property real scale: 1.0
    property real opacity: 0.85

    readonly property color panel: Qt.rgba(0.05, 0.06, 0.09, 0.78 * opacity)
    readonly property color panelEdge: Qt.rgba(1, 1, 1, 0.08)
    readonly property color rowBg: Qt.rgba(1, 1, 1, 0.05)
    readonly property color text: "#E9EDF5"
    readonly property color dim: "#9AA4B8"
    readonly property color faint: "#69728A"
    readonly property color accent: "#F2C15A"
    readonly property color good: "#5BD68A"
    readonly property color warn: "#F2C15A"
    readonly property color bad: "#F0605D"
    readonly property color hp: "#E0484D"
    readonly property color hpBack: Qt.rgba(0.88, 0.28, 0.30, 0.18)

    readonly property int radius: Math.round(8 * scale)
    readonly property int pad: Math.round(8 * scale)
    readonly property int rowHeight: Math.round(22 * scale)
    readonly property int fontSmall: Math.round(11 * scale)
    readonly property int fontNormal: Math.round(12.5 * scale)
    readonly property int fontLarge: Math.round(15 * scale)
    // Meter columns: damage, DPS, share, crit (PlayerBar and MeterHeader).
    readonly property int colDamage: Math.round(50 * scale)
    readonly property int colDps: Math.round(44 * scale)
    readonly property int colShare: Math.round(32 * scale)
    readonly property int colCrit: Math.round(32 * scale)
    readonly property int colSpacing: Math.round(6 * scale)

    readonly property string fontFamily: "Inter, Noto Sans, sans-serif"

    // A2Tools' class colours, by class key.
    readonly property var jobColors: ({
        "GLADIATOR": "#4FD1C5",
        "TEMPLAR": "#5F8CFF",
        "RANGER": "#41D98A",
        "ASSASSIN": "#7BE35A",
        "SORCERER": "#9A6BFF",
        "ELEMENTALIST": "#E06BFF",
        "CLERIC": "#F2C15A",
        "CHANTER": "#FF9A3D",
        "FIGHTER": "#E85D5D"
    })

    function jobColor(key) {
        return jobColors[key] || "#8C96AA";
    }

    // 1234 -> "1.23K", 12345678 -> "12.3M"
    function compact(n) {
        n = Number(n) || 0;
        const a = Math.abs(n);
        if (a >= 1e9) return (n / 1e9).toFixed(a >= 1e10 ? 1 : 2) + "B";
        if (a >= 1e6) return (n / 1e6).toFixed(a >= 1e7 ? 1 : 2) + "M";
        if (a >= 1e3) return (n / 1e3).toFixed(a >= 1e4 ? 1 : 2) + "K";
        return Math.round(n).toString();
    }

    function percent(f, digits) {
        return ((Number(f) || 0) * 100).toFixed(digits === undefined ? 1 : digits) + "%";
    }

    // 83500 -> "1:23"
    function duration(ms) {
        const s = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
        const m = Math.floor(s / 60);
        const h = Math.floor(m / 60);
        const ss = String(s % 60).padStart(2, "0");
        return h > 0 ? h + ":" + String(m % 60).padStart(2, "0") + ":" + ss : m + ":" + ss;
    }
}
