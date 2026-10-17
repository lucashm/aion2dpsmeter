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

    visible: enabledInSettings && (wanted || editMode) && !remap.running
    color: "transparent"
    // To be dragged in game the surface covers the screen for as long as the
    // setting is on, and the body moves inside it: a surface moving under the
    // pointer chases its own coordinates, and one resized at the grab shows a
    // frame at the screen's edge.
    readonly property bool roomy: settings.moveInGame && !interactive
    // Turning roomy resizes a live surface, and the compositor stretches the
    // old frame across the new size for a moment: hide it across the change.
    onRoomyChanged: remap.restart()
    Timer { id: remap; interval: 50 }
    // The compositor has made the surface full-screen.
    readonly property bool fullScreen: roomy && screen && width >= screen.width && height >= screen.height

    anchors.top: true
    anchors.left: true
    anchors.right: roomy
    anchors.bottom: roomy
    margins.left: roomy ? 0 : posX
    margins.top: roomy ? 0 : posY
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.max(1, body.implicitWidth)
    implicitHeight: Math.max(1, body.implicitHeight)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aion2-meter-" + widgetId
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Dragged by itself, outside edit mode, when the setting allows it.
    readonly property bool movable: settings.moveInGame && !editMode && !interactive

    mask: Region { item: (win.interactive && !win.editMode) || win.movable ? body : null }

    function clampX(x) {
        return Math.max(0, Math.min(x, (screen ? screen.width : 4000) - implicitWidth));
    }
    function clampY(y) {
        return Math.max(0, Math.min(y, (screen ? screen.height : 3000) - implicitHeight));
    }

    Item { id: whole; anchors.fill: parent }

    Item {
        id: body
        x: win.fullScreen ? win.posX : 0
        y: win.fullScreen ? win.posY : 0
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    MouseArea {
        anchors.fill: body
        enabled: win.movable
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        // The pointer's place in the widget at the press.
        property real offX: 0
        property real offY: 0
        property bool moved: false
        function snap(v) {
            const g = win.settings.gridSize;
            return win.settings.snapToGrid ? Math.round(v / g) * g : v;
        }
        onPressed: mouse => {
            offX = mouse.x;
            offY = mouse.y;
            moved = false;
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            if (!moved && Math.abs(mouse.x - offX) + Math.abs(mouse.y - offY) < 4) return;
            moved = true;
            // The pointer on the screen; the surface is still at the widget until it turns full-screen.
            const p = mapToItem(whole, mouse.x, mouse.y);
            const x = p.x - offX + (win.fullScreen ? 0 : win.posX);
            const y = p.y - offY + (win.fullScreen ? 0 : win.posY);
            const free = mouse.modifiers & Qt.ShiftModifier;
            win.dragX = free ? x : snap(x);
            win.dragY = free ? y : snap(y);
        }
        onReleased: mouse => {
            if (moved) win.settings.setWidgetPos(win.widgetId, win.posX, win.posY);
            else win.tapped(mouse.x, mouse.y);
            win.dragX = NaN;
            win.dragY = NaN;
        }
        onCanceled: {
            win.dragX = NaN;
            win.dragY = NaN;
        }
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
