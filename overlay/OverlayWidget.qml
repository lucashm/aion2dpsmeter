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

    // Dragged by itself, outside edit mode, when the setting allows it.
    readonly property bool movable: settings.moveInGame && !editMode && !interactive

    mask: Region { item: (win.interactive && !win.editMode) || win.movable ? body : null }

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

    // shortcut: the pointer is in this surface's coordinates, and the surface
    // moves a frame behind the drag, so it wobbles while moving and settles
    // where it should. A smooth drag needs a full-screen surface, as edit mode has.
    MouseArea {
        anchors.fill: body
        enabled: win.movable
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
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
            const free = mouse.modifiers & Qt.ShiftModifier;
            const x = win.posX + mouse.x - offX;
            const y = win.posY + mouse.y - offY;
            win.dragX = free ? x : snap(x);
            win.dragY = free ? y : snap(y);
        }
        onReleased: mouse => {
            if (moved) win.settings.setWidgetPos(win.widgetId, win.posX, win.posY);
            else win.tapped(mouse.x, mouse.y);
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
