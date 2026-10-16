import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Edit mode: a full-screen layer over the game that takes the pointer. Drag a
// widget's outline to move it; the panel in the middle holds the settings.
// Working in this surface's coordinates (the screen's) keeps dragging exact,
// where moving a layer surface by its own coordinates would lag behind.
PanelWindow {
    id: editor

    required property var settings
    required property var client
    // OverlayWidget instances that can be moved.
    property var widgets: []
    property bool active: false

    signal done()

    visible: active
    color: Qt.rgba(0, 0, 0, 0.25)
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aion2-meter-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: editor.done()
    }

    // The snap grid: faint lines, every fourth one a little brighter.
    Canvas {
        id: grid
        anchors.fill: parent
        visible: editor.settings.snapToGrid
        readonly property int step: editor.settings.gridSize
        onStepChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 1;
            for (let i = 0, x = 0; x <= width; i++, x += step) {
                ctx.strokeStyle = i % 4 === 0 ? "rgba(255,255,255,0.13)" : "rgba(255,255,255,0.05)";
                ctx.beginPath();
                ctx.moveTo(x + 0.5, 0);
                ctx.lineTo(x + 0.5, height);
                ctx.stroke();
            }
            for (let i = 0, y = 0; y <= height; i++, y += step) {
                ctx.strokeStyle = i % 4 === 0 ? "rgba(255,255,255,0.13)" : "rgba(255,255,255,0.05)";
                ctx.beginPath();
                ctx.moveTo(0, y + 0.5);
                ctx.lineTo(width, y + 0.5);
                ctx.stroke();
            }
        }
    }

    // Grid position for a dragged widget; Shift places it freely.
    function snap(v, modifiers) {
        const g = settings.gridSize;
        if (!settings.snapToGrid || (modifiers & Qt.ShiftModifier)) return v;
        return Math.round(v / g) * g;
    }

    Repeater {
        model: editor.widgets

        Rectangle {
            id: handle
            required property var modelData
            readonly property var w: modelData
            visible: w.visible
            x: w.posX
            y: w.posY
            width: w.implicitWidth
            height: w.implicitHeight
            color: drag.containsMouse ? Qt.rgba(0.95, 0.76, 0.35, 0.12) : "transparent"
            radius: Theme.radius

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 3
                radius: 3
                color: Theme.accent
                width: tag.implicitWidth + 8
                height: tag.implicitHeight + 2
                Text {
                    id: tag
                    anchors.centerIn: parent
                    text: "⠿ " + handle.w.title
                    color: "#1b1b1b"
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real offX: 0
                property real offY: 0
                property bool moved: false
                onPressed: mouse => {
                    offX = mouse.x;
                    offY = mouse.y;
                    moved = false;
                }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    const p = mapToItem(null, mouse.x, mouse.y);
                    const nx = editor.snap(p.x - offX, mouse.modifiers), ny = editor.snap(p.y - offY, mouse.modifiers);
                    if (!moved && Math.abs(nx - handle.w.posX) + Math.abs(ny - handle.w.posY) < 4) return;
                    moved = true;
                    handle.w.dragX = nx;
                    handle.w.dragY = ny;
                }
                onReleased: mouse => {
                    if (moved) {
                        editor.settings.setWidgetPos(handle.w.widgetId, handle.w.posX, handle.w.posY);
                    } else {
                        handle.w.tapped(mouse.x, mouse.y);
                    }
                    handle.w.dragX = NaN;
                    handle.w.dragY = NaN;
                }
            }
        }
    }

    // ── settings panel ──────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.12
        width: col.implicitWidth + 2 * Theme.pad * 2
        height: col.implicitHeight + 2 * Theme.pad * 2
        radius: Theme.radius * 1.5
        color: Qt.rgba(0.06, 0.07, 0.10, 0.95)
        border.color: Theme.panelEdge

        // Swallow clicks so they do not fall through to the backdrop.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: Theme.pad

            Text {
                text: "AION 2 meter — edit mode"
                color: Theme.text
                font.pixelSize: Theme.fontLarge
                font.family: Theme.fontFamily
                font.bold: true
            }
            Text {
                text: "Drag widgets to move them (they snap to the grid; hold Shift to place freely). Click a player in the meter to see their skills. Esc or the edit key to finish."
                color: Theme.dim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
            }

            Flow {
                Layout.preferredWidth: Math.round(560 * Theme.scale)
                spacing: Theme.pad / 2
                Repeater {
                    model: editor.widgets
                    Chip {
                        required property var modelData
                        label: modelData.title
                        checked: editor.settings.widgetVisible(modelData.widgetId)
                        onClicked: editor.settings.setWidgetVisible(modelData.widgetId, !checked)
                    }
                }
            }

            RowLayout {
                spacing: Theme.pad / 2
                Text { text: "Target"; color: Theme.dim; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Repeater {
                    model: [
                        { id: "bossTargets", label: "Boss" },
                        { id: "lastHitByMe", label: "My target" },
                        { id: "mostDamage", label: "Most damaged" },
                        { id: "allTargets", label: "All" },
                        { id: "trainTargets", label: "Dummy" }
                    ]
                    Chip {
                        required property var modelData
                        label: modelData.label
                        checked: editor.client.state && editor.client.state.targetMode === modelData.id
                        onClicked: editor.client.setTargetMode(modelData.id)
                    }
                }
            }

            RowLayout {
                spacing: Theme.pad / 2
                Text { text: "Meter shows"; color: Theme.dim; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                MetricSwitch {
                    value: editor.settings.meterMetric
                    onPicked: m => editor.settings.setMeterMetric(m)
                }
            }

            RowLayout {
                spacing: Theme.pad / 2
                Chip {
                    label: "Snap to grid"
                    checked: editor.settings.snapToGrid
                    onClicked: editor.settings.setSnapToGrid(!checked)
                }
                Text { text: "Grid"; color: Theme.dim; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Chip { label: "−"; onClicked: editor.settings.setGridSize(editor.settings.gridSize - 4) }
                Text { text: editor.settings.gridSize + " px"; color: Theme.text; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Chip { label: "+"; onClicked: editor.settings.setGridSize(editor.settings.gridSize + 4) }
                Text { text: "(hold Shift to place freely)"; color: Theme.faint; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
            }

            RowLayout {
                spacing: Theme.pad / 2
                Text { text: "Size"; color: Theme.dim; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Chip { label: "−"; onClicked: editor.settings.setScale(editor.settings.uiScale - 0.1) }
                Text { text: Math.round(editor.settings.uiScale * 100) + "%"; color: Theme.text; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Chip { label: "+"; onClicked: editor.settings.setScale(editor.settings.uiScale + 0.1) }
                Item { width: Theme.pad }
                Text { text: "Opacity"; color: Theme.dim; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Chip { label: "−"; onClicked: editor.settings.setOpacity(editor.settings.uiOpacity - 0.1) }
                Text { text: Math.round(editor.settings.uiOpacity * 100) + "%"; color: Theme.text; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                Chip { label: "+"; onClicked: editor.settings.setOpacity(editor.settings.uiOpacity + 0.1) }
                Item { width: Theme.pad }
                Chip {
                    label: "Show outside the game"
                    checked: editor.settings.alwaysShow
                    onClicked: editor.settings.setAlwaysShow(!checked)
                }
            }

            RowLayout {
                spacing: Theme.pad / 2
                Chip { label: "Reset meter"; onClicked: editor.client.reset() }
                Chip { label: "Reset layout"; onClicked: editor.settings.resetLayout() }
                Item { Layout.fillWidth: true }
                Chip { label: "Done"; checked: true; onClicked: editor.done() }
            }
        }
    }
}
