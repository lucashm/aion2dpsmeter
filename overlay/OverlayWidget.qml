import QtQuick
import Quickshell
import Quickshell.Wayland

// One widget = one small layer-shell surface on Hyprland's overlay layer.
//
// That layer draws above fullscreen windows, is never tiled, and takes no
// keyboard focus. The input mask is empty unless the widget is interactive
// (like the open history panel), so clicks go through to the game. Moving
// widgets is done by EditorLayer, which covers the screen in edit mode.
PanelWindow {
    id: win

    required property string widgetId
    required property var settings
    property bool editMode: false
    property bool interactive: false
    property bool wanted: true
    property point defaultPos: Qt.point(40, 40)
    // Default layouts are drawn on a 2560x1440 screen. The game's HUD scales
    // with the screen's height, so offsets from the centre and top scale by
    // this; offsets from the left and right edges stay in pixels.
    readonly property real hud: (screen ? screen.height : 1440) / 1440
    property string title: widgetId

    // A click on the widget in edit mode, in widget coordinates.
    signal tapped(real x, real y)

    default property alias content: body.data
    readonly property alias body: body

    // Set by the editor while dragging.
    property real dragX: NaN
    property real dragY: NaN
    readonly property var saved: settings.widgetPos(widgetId)
    readonly property real posX: Math.round(clampX(!isNaN(dragX) ? dragX : (saved ? saved.x : defaultPos.x)))
    readonly property real posY: Math.round(clampY(!isNaN(dragY) ? dragY : (saved ? saved.y : defaultPos.y)))
    readonly property bool enabledInSettings: settings.widgetVisible(widgetId)

    visible: enabledInSettings && (wanted || editMode)
    color: "transparent"
    anchors.top: true
    anchors.left: true
    margins.left: posX
    margins.top: posY
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.max(1, body.implicitWidth)
    implicitHeight: Math.max(1, body.implicitHeight)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aion2-meter-" + widgetId
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region { item: win.interactive && !win.editMode ? body : null }

    function clampX(x) {
        return Math.max(0, Math.min(x, (screen ? screen.width : 4000) - implicitWidth));
    }
    function clampY(y) {
        return Math.max(0, Math.min(y, (screen ? screen.height : 3000) - implicitHeight));
    }

    Item {
        id: body
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    Rectangle {
        visible: win.editMode
        anchors.fill: body
        color: "transparent"
        border.color: Theme.accent
        border.width: 1
        radius: Theme.radius
    }
}
