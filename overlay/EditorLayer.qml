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
        Keys.onEscapePressed: {
            if (editor.confirmingReset) editor.confirmingReset = false;
            else editor.done();
        }
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
    function snap(v) {
        const g = settings.gridSize;
        return settings.snapToGrid ? Math.round(v / g) * g : v;
    }

    // Alignment guides while dragging, in screen coordinates.
    property var guidesX: []
    property var guidesY: []

    // Lines a widget can line up with along one axis: the screen's edges and
    // centre, and every other widget's edges and centre.
    function alignLines(w, horizontal) {
        const lines = horizontal ? [0, width / 2, width] : [0, height / 2, height];
        for (const o of widgets) {
            if (o === w || !o.visible) continue;
            const p = horizontal ? o.posX : o.posY;
            const s = horizontal ? o.implicitWidth : o.implicitHeight;
            lines.push(p, p + s / 2, p + s);
        }
        return lines;
    }

    // One axis of a drag: snaps the widget's nearest edge or centre onto a
    // line within a few pixels, else onto the grid. Returns [position, lines touched].
    function placeAxis(w, start, horizontal) {
        const size = horizontal ? w.implicitWidth : w.implicitHeight;
        const lines = alignLines(w, horizontal);
        let best = null;
        for (const edge of [0, size / 2, size])
            for (const l of lines) {
                const d = l - (start + edge);
                if (Math.abs(d) <= 8 && (best === null || Math.abs(d) < Math.abs(best))) best = d;
            }
        const pos = best !== null ? start + best : snap(start);
        const touched = lines.filter(l => [0, size / 2, size].some(e => Math.abs(pos + e - l) < 0.5));
        return [pos, [...new Set(touched)]];
    }

    // Shift places freely: no guides, no grid.
    function place(w, x, y, modifiers) {
        if (modifiers & Qt.ShiftModifier) {
            guidesX = [];
            guidesY = [];
            return Qt.point(x, y);
        }
        const [px, gx] = placeAxis(w, x, true);
        const [py, gy] = placeAxis(w, y, false);
        guidesX = gx;
        guidesY = gy;
        return Qt.point(px, py);
    }

    // The screen's centre lines, always shown while editing.
    Rectangle {
        x: Math.round(parent.width / 2)
        width: 1
        height: parent.height
        color: Qt.rgba(1, 1, 1, 0.22)
    }
    Rectangle {
        y: Math.round(parent.height / 2)
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.22)
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
                    const at = editor.place(handle.w, p.x - offX, p.y - offY, mouse.modifiers);
                    if (!moved && Math.abs(at.x - handle.w.posX) + Math.abs(at.y - handle.w.posY) < 4) return;
                    moved = true;
                    handle.w.dragX = at.x;
                    handle.w.dragY = at.y;
                }
                onReleased: mouse => {
                    editor.guidesX = [];
                    editor.guidesY = [];
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

    // Alignment guides for the widget being dragged.
    Repeater {
        model: editor.guidesX
        Rectangle {
            required property real modelData
            x: Math.round(modelData)
            width: 1
            height: editor.height
            color: "#FF5FD2"
        }
    }
    Repeater {
        model: editor.guidesY
        Rectangle {
            required property real modelData
            y: Math.round(modelData)
            width: editor.width
            height: 1
            color: "#FF5FD2"
        }
    }

    // ── settings panel ──────────────────────────────────────────────────
    // A label column and a control column, grouped into sections. Pills that
    // pick one option sit joined in a Segmented; on/off settings are Toggles.

    component Label: Text {
        color: Theme.dim
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    }

    component Section: Text {
        Layout.columnSpan: 2
        Layout.topMargin: Theme.pad / 2
        color: Theme.faint
        font.pixelSize: Math.round(10 * Theme.scale)
        font.family: Theme.fontFamily
        font.bold: true
        font.letterSpacing: 1.2
    }

    // One of several options, joined into a single control.
    component Segmented: Rectangle {
        id: seg
        // [{ value, label }]
        property var options: []
        property var value
        signal picked(var value)
        implicitWidth: segRow.implicitWidth + 4
        implicitHeight: segRow.implicitHeight + 4
        radius: Theme.radius
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Theme.panelEdge
        Row {
            id: segRow
            anchors.centerIn: parent
            Repeater {
                model: seg.options
                Rectangle {
                    required property var modelData
                    readonly property bool on: seg.value === modelData.value
                    width: segText.implicitWidth + Theme.pad * 2
                    height: segText.implicitHeight + Theme.pad * 0.75
                    radius: Theme.radius - 2
                    color: on ? Theme.accent : (segArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                    Text {
                        id: segText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.on ? "#1b1b1b" : Theme.text
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        font.bold: parent.on
                    }
                    MouseArea {
                        id: segArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(modelData.value)
                    }
                }
            }
        }
    }

    // An on/off setting: a check box and its label.
    component Toggle: Rectangle {
        id: tog
        property string label
        property bool checked
        signal toggled()
        implicitWidth: togRow.implicitWidth + Theme.pad * 1.5
        implicitHeight: togRow.implicitHeight + Theme.pad * 0.75
        radius: Theme.radius
        color: togArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        Row {
            id: togRow
            anchors.centerIn: parent
            spacing: Theme.pad * 0.75
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(14 * Theme.scale)
                height: width
                radius: 3
                color: tog.checked ? Theme.accent : "transparent"
                border.color: tog.checked ? Theme.accent : Theme.dim
                Text {
                    anchors.centerIn: parent
                    visible: tog.checked
                    text: "✓"
                    color: "#1b1b1b"
                    font.pixelSize: Theme.fontSmall
                    font.bold: true
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tog.label
                color: tog.checked ? Theme.text : Theme.dim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
            }
        }
        MouseArea {
            id: togArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tog.toggled()
        }
    }

    // − value +, for a number setting.
    component Stepper: Rectangle {
        id: step
        property string text
        signal down()
        signal up()
        implicitWidth: stepRow.implicitWidth + 4
        implicitHeight: stepRow.implicitHeight + 4
        radius: Theme.radius
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Theme.panelEdge
        opacity: enabled ? 1 : 0.4
        Row {
            id: stepRow
            anchors.centerIn: parent
            Repeater {
                model: ["−", "", "+"]
                Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool isValue: index === 1
                    width: isValue ? Math.max(stepText.implicitWidth + Theme.pad, Math.round(44 * Theme.scale))
                                   : height
                    height: stepText.implicitHeight + Theme.pad * 0.75
                    radius: Theme.radius - 2
                    color: !isValue && stepArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    Text {
                        id: stepText
                        anchors.centerIn: parent
                        text: parent.isValue ? step.text : modelData
                        color: parent.isValue ? Theme.text : Theme.dim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        font.features: { "tnum": 1 }
                    }
                    MouseArea {
                        id: stepArea
                        anchors.fill: parent
                        enabled: !parent.isValue && step.enabled
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: index === 0 ? step.down() : step.up()
                    }
                }
            }
        }
    }

    // A plain button: quiet unless primary.
    component Button: Rectangle {
        id: btn
        property string label
        property bool primary: false
        signal clicked()
        implicitWidth: btnText.implicitWidth + Theme.pad * (primary ? 3 : 2)
        implicitHeight: btnText.implicitHeight + Theme.pad
        radius: Theme.radius
        color: primary ? (btnArea.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                       : (btnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? "#1b1b1b" : Theme.dim
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
            font.bold: btn.primary
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.12
        width: col.implicitWidth + Theme.pad * 4
        height: col.implicitHeight + Theme.pad * 3
        radius: Theme.radius * 1.5
        color: Qt.rgba(0.06, 0.07, 0.10, 0.95)
        border.color: Theme.panelEdge

        // Swallow clicks so they do not fall through to the backdrop.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: Theme.pad

            // Header: what this is, and how to use it.
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Edit layout"
                    color: Theme.text
                    font.pixelSize: Theme.fontLarge
                    font.family: Theme.fontFamily
                    font.bold: true
                }
                Text {
                    // Wraps to the form's width instead of setting it.
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    wrapMode: Text.WordWrap
                    text: "Drag a widget to move it · Shift places freely · Click a player for their skills · Esc to finish"
                    color: Theme.faint
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.panelEdge }

            GridLayout {
                columns: 2
                columnSpacing: Theme.pad * 1.5
                rowSpacing: Theme.pad * 0.75

                Section { text: "WIDGETS" }

                Label { text: "Show" }
                Flow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 2
                    Repeater {
                        model: editor.widgets
                        Toggle {
                            required property var modelData
                            label: modelData.title
                            checked: editor.settings.widgetVisible(modelData.widgetId)
                            onToggled: editor.settings.setWidgetVisible(modelData.widgetId, !checked)
                        }
                    }
                }

                Label { text: "Monitor" }
                Segmented {
                    options: [{ value: "", label: "Follow game" }].concat(
                        Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
                    value: editor.settings.pinnedMonitor || ""
                    onPicked: v => editor.settings.setPinnedMonitor(v)
                }

                Item { implicitWidth: 1 }
                Toggle {
                    label: "Keep visible when the game isn't focused"
                    checked: editor.settings.alwaysShow
                    onToggled: editor.settings.setAlwaysShow(!checked)
                }

                Section { text: "METER" }

                Label { text: "Target" }
                Segmented {
                    options: [
                        { value: "bossTargets", label: "Boss" },
                        { value: "lastHitByMe", label: "My target" },
                        { value: "mostDamage", label: "Most damaged" },
                        { value: "allTargets", label: "All" },
                        { value: "trainTargets", label: "Dummy" }
                    ]
                    value: editor.client.state ? editor.client.state.targetMode : ""
                    onPicked: v => editor.client.setTargetMode(v)
                }

                Label { text: "Numbers" }
                Segmented {
                    options: [
                        { value: "damage", label: "Damage" },
                        { value: "dps", label: "DPS" },
                        { value: "both", label: "Both" }
                    ]
                    value: editor.settings.meterMetric
                    onPicked: v => editor.settings.setMeterMetric(v)
                }

                Section { text: "APPEARANCE" }

                Label { text: "Size" }
                RowLayout {
                    spacing: Theme.pad * 1.5
                    Stepper {
                        text: Math.round(editor.settings.uiScale * 100) + "%"
                        onDown: editor.settings.setScale(editor.settings.uiScale - 0.1)
                        onUp: editor.settings.setScale(editor.settings.uiScale + 0.1)
                    }
                    Label { text: "Opacity" }
                    Stepper {
                        text: Math.round(editor.settings.uiOpacity * 100) + "%"
                        onDown: editor.settings.setOpacity(editor.settings.uiOpacity - 0.1)
                        onUp: editor.settings.setOpacity(editor.settings.uiOpacity + 0.1)
                    }
                }

                Label { text: "Grid" }
                RowLayout {
                    spacing: Theme.pad
                    Toggle {
                            label: "Snap"
                        checked: editor.settings.snapToGrid
                        onToggled: editor.settings.setSnapToGrid(!checked)
                    }
                    Stepper {
                        enabled: editor.settings.snapToGrid
                        text: editor.settings.gridSize + " px"
                        onDown: editor.settings.setGridSize(editor.settings.gridSize - 4)
                        onUp: editor.settings.setGridSize(editor.settings.gridSize + 4)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.panelEdge }

            // Footer: resets on the left, the way out on the right.
            RowLayout {
                spacing: 2
                Button { label: "Reset layout"; onClicked: editor.settings.resetLayout() }
                Button { label: "Reset meter…"; onClicked: editor.confirmingReset = true }
                Item { Layout.fillWidth: true }
                Button { label: "Done"; primary: true; onClicked: editor.done() }
            }
        }
    }

    // ── reset confirmation ──────────────────────────────────────────────
    property bool confirmingReset: false
    onActiveChanged: confirmingReset = false

    Rectangle {
        visible: editor.confirmingReset
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        // Clicking outside the box cancels.
        MouseArea {
            anchors.fill: parent
            onClicked: editor.confirmingReset = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: box.implicitWidth + Theme.pad * 4
            height: box.implicitHeight + Theme.pad * 4
            radius: Theme.radius * 1.5
            color: Qt.rgba(0.06, 0.07, 0.10, 0.97)
            border.color: Theme.panelEdge

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: box
                anchors.centerIn: parent
                spacing: Theme.pad

                Text {
                    text: "Reset the meter?"
                    color: Theme.text
                    font.pixelSize: Theme.fontLarge
                    font.family: Theme.fontFamily
                    font.bold: true
                }
                Text {
                    text: "Boss fights on it are saved to history first. Other damage is lost."
                    color: Theme.dim
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Theme.pad / 2
                    Button { label: "Cancel"; onClicked: editor.confirmingReset = false }
                    Button {
                        label: "Reset"
                        primary: true
                        onClicked: {
                            editor.client.reset();
                            editor.confirmingReset = false;
                        }
                    }
                }
            }
        }
    }
}
