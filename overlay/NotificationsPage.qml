import QtQuick

// The app's Notifications page: each kind of in-game alert, with a switch
// and a test: hidden cubes, and the hourly events.
Item {
    id: page

    required property var settings
    // Show a sample alert in game: { event, by, mine, distance }.
    signal test(var e)

    implicitHeight: content.implicitHeight

    component Label: Text {
        color: AppTheme.text
        font.pixelSize: AppTheme.normal
        font.family: AppTheme.font
    }
    component Button: Rectangle {
        id: button
        property string label
        property bool checked
        signal clicked()
        height: 32
        width: buttonText.implicitWidth + 28
        radius: 6
        color: checked ? AppTheme.accent : buttonArea.containsMouse ? AppTheme.rowHover : AppTheme.row
        border.color: checked ? AppTheme.accent : AppTheme.cardEdge
        Label {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            color: button.checked ? "white" : AppTheme.text
            font.pixelSize: AppTheme.small
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
    component Switch: Rectangle {
        id: sw
        property bool on
        signal toggled()
        width: 44
        height: 24
        radius: 12
        color: on ? AppTheme.accent : AppTheme.row
        border.color: on ? AppTheme.accent : AppTheme.cardEdge
        Rectangle {
            x: sw.on ? sw.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: "white"
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
    }
    // A switch with a name and a line under it.
    component Option: Row {
        id: option
        property alias on: optionSwitch.on
        property string label
        property string note
        signal toggled()
        spacing: 12
        Switch {
            id: optionSwitch
            anchors.verticalCenter: parent.verticalCenter
            onToggled: option.toggled()
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Label { text: option.label }
            Label {
                text: option.note
                color: AppTheme.faint
                font.pixelSize: AppTheme.small
            }
        }
    }

    Column {
        id: content
        width: parent.width
        spacing: 20

        Column {
            spacing: 6
            Label {
                text: "Notifications"
                font.pixelSize: AppTheme.title
                font.bold: true
            }
            Label {
                text: "Alerts drawn over the game. Turn each one on or off here."
                color: AppTheme.dim
            }
        }

        // Hidden cubes.
        Rectangle {
            width: parent.width
            height: cubeCol.implicitHeight + 40
            radius: AppTheme.radius
            color: AppTheme.card
            border.color: AppTheme.cardEdge

            Item {
                x: 20
                y: 20
                width: parent.width - 40
                height: cubeCol.implicitHeight

                Rectangle {
                    id: cubeIcon
                    width: 22
                    height: 22
                    y: 4
                    rotation: 45
                    color: AppTheme.cube
                }
                Column {
                    id: cubeCol
                    anchors.left: cubeIcon.right
                    anchors.leftMargin: 20
                    anchors.right: cubeSwitch.left
                    anchors.rightMargin: 20
                    spacing: 8
                    Label {
                        text: "Hidden cubes"
                        font.pixelSize: AppTheme.large
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: AppTheme.dim
                        text: "An alert at the top of the screen when a hidden cube comes within about 100 m of you, and when someone else starts opening it or opens it. It shows how far away the cube is when the game has sent your position lately: often in a fight, less while just walking. Move it in Customize."
                    }
                    // Sub-option: only with a key.
                    Row {
                        spacing: 12
                        topPadding: 4
                        opacity: page.settings.notifyCubes ? 1 : 0.4
                        Switch {
                            anchors.verticalCenter: parent.verticalCenter
                            on: page.settings.cubesNeedKey
                            onToggled: page.settings.setCubesNeedKey(!on)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Label { text: "Only when I have a key" }
                            Label {
                                text: "Counts your Hidden Cube Keys from your bag at login, less the ones you use. Until it has seen your bag, it alerts anyway."
                                color: AppTheme.faint
                                font.pixelSize: AppTheme.small
                            }
                        }
                    }
                    Row {
                        spacing: 12
                        opacity: page.settings.notifyCubes ? 1 : 0.4
                        Switch {
                            anchors.verticalCenter: parent.verticalCenter
                            on: page.settings.cubeSound
                            onToggled: page.settings.setCubeSound(!on)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Label { text: "Play a sound" }
                            Label {
                                text: "A short chime when a cube is nearby."
                                color: AppTheme.faint
                                font.pixelSize: AppTheme.small
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        topPadding: 4
                        Button {
                            label: "Test: cube nearby"
                            onClicked: page.test({ event: "near", id: -1, distance: 64, keys: 41 })
                        }
                        Button {
                            label: "Test: opened by someone"
                            onClicked: page.test({ event: "opened", id: -2, by: "Somebody" })
                        }
                    }
                }
                Switch {
                    id: cubeSwitch
                    anchors.right: parent.right
                    on: page.settings.notifyCubes
                    onToggled: page.settings.setNotifyCubes(!on)
                }
            }
        }

        // Hourly events.
        Rectangle {
            width: parent.width
            height: eventCol.implicitHeight + 40
            radius: AppTheme.radius
            color: AppTheme.card
            border.color: AppTheme.cardEdge

            Item {
                x: 20
                y: 20
                width: parent.width - 40
                height: eventCol.implicitHeight

                Rectangle {
                    id: eventIcon
                    width: 22
                    height: 22
                    y: 4
                    radius: 11
                    color: AppTheme.accent
                }
                Column {
                    id: eventCol
                    anchors.left: eventIcon.right
                    anchors.leftMargin: 20
                    anchors.right: parent.right
                    spacing: 8
                    Label {
                        text: "Event reminders"
                        font.pixelSize: AppTheme.large
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: AppTheme.dim
                        text: "A countdown over the game before each hourly event starts, by the server's clock. Move it in Customize."
                    }
                    Option {
                        topPadding: 4
                        label: "Shugo Festival"
                        note: "Every hour on the hour."
                        on: page.settings.notifyShugo
                        onToggled: page.settings.setNotifyShugo(!on)
                    }
                    Option {
                        label: "Dimensional Invasion"
                        note: "Every hour at half past: Beritra Air Raid, Accursed Sword or Incursion of the Spirits. Level 45 and up."
                        on: page.settings.notifyInvasion
                        onToggled: page.settings.setNotifyInvasion(!on)
                    }
                    Row {
                        spacing: 8
                        opacity: page.settings.notifyShugo || page.settings.notifyInvasion ? 1 : 0.4
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            rightPadding: 4
                            text: "Remind me"
                        }
                        Repeater {
                            model: [1, 3, 5, 10]
                            Button {
                                required property int modelData
                                label: modelData + " min"
                                checked: page.settings.eventLead === modelData
                                onClicked: page.settings.setEventLead(modelData)
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 4
                            text: "before"
                        }
                    }
                    Option {
                        opacity: page.settings.notifyShugo || page.settings.notifyInvasion ? 1 : 0.4
                        label: "Play a sound"
                        note: "A short chime when a reminder shows."
                        on: page.settings.eventSound
                        onToggled: page.settings.setEventSound(!on)
                    }
                    Row {
                        spacing: 8
                        topPadding: 4
                        Button {
                            label: "Test: Shugo Festival"
                            onClicked: page.test({ reminder: "shugo" })
                        }
                        Button {
                            label: "Test: Dimensional Invasion"
                            onClicked: page.test({ reminder: "invasion" })
                        }
                    }
                }
            }
        }
    }
}
