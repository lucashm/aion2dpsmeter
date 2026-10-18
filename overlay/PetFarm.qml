import QtQuick

// The pets whose souls you're picking up, up to 5, the last farmed first:
// each one's portrait, level, souls to the next level and to level 3, the
// rate per minute, and how long both take at that rate. Each goes 5 minutes after its
// last soul. The portraits come with the app's map data (MapData.qml).
OverlayWidget {
    id: farm

    required property var client
    title: "Pet souls"
    readonly property int width_: Math.round(300 * Theme.scale)
    defaultPos: Qt.point(24, Math.round((screen ? screen.height : 1440) * 0.62))

    readonly property var pets: client.pets
    property real now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: farm.pets !== null && farm.pets.farming.length > 0
        onTriggered: farm.now = Date.now()
    }
    readonly property var farming: pets ? pets.farming.filter(f => now - f.lastMs < 5 * 60 * 1000) : []
    readonly property bool recent: farming.length > 0
    // The portraits: downloaded with the map data, if the app hasn't yet.
    onRecentChanged: if (recent && MapData.status === "idle") MapData.fetch()
    readonly property int face: Math.round(40 * Theme.scale)

    Panel {
        width: farm.width_

        // Something to place in Customize while nothing is farmed.
        Text {
            visible: !farm.recent
            text: "Pet souls: shows while you farm"
            color: Theme.dim
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
        }

        Repeater {
            model: farm.farming

            Row {
                id: pet
                required property var modelData
                required property int index
                spacing: Theme.pad
                topPadding: index ? Theme.pad : 0
                // What's left beside the portrait.
                readonly property int inner: farm.width_ - Theme.pad * 3 - farm.face
                readonly property string name: PetData.name(modelData.pet)
                readonly property string genus: PetData.pets[modelData.pet] ? PetData.pets[modelData.pet].genus : ""

                readonly property int level: farm.pets.levels[modelData.pet] || 0
                readonly property int points: farm.pets.points[modelData.pet] || 0
                readonly property bool full: level >= PetData.maxLevel
                readonly property int target: full ? 0 : PetData.needed[level]
                readonly property int soulsLeft: PetData.left(level, points)
                // Souls a minute since its first one; from the second soul on.
                readonly property real perMinute: {
                    if (modelData.gained < 2) return 0;
                    const ms = Math.max(modelData.lastMs, farm.now) - modelData.startedMs;
                    return ms > 0 ? modelData.gained / (ms / 60000) : 0;
                }
                function eta(souls) {
                    return perMinute > 0 ? "~" + Theme.duration(souls / perMinute * 60000) : "–";
                }

                // The portrait, framed in its genus's colour; its initial until it loads.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: farm.face
                    height: farm.face
                    radius: Math.round(6 * Theme.scale)
                    color: Qt.alpha(AppTheme.genusColor(pet.genus), 0.2)
                    border.color: AppTheme.genusColor(pet.genus)
                    clip: true
                    Image {
                        id: portrait
                        anchors.fill: parent
                        anchors.margins: 1
                        source: MapData.portraits[pet.name] || ""
                        sourceSize: Qt.size(80, 80)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: portrait.status !== Image.Ready
                        text: pet.name.charAt(0)
                        color: AppTheme.genusColor(pet.genus)
                        font.pixelSize: Theme.fontLarge
                        font.family: Theme.fontFamily
                        font.bold: true
                    }
                }

                Column {
                    spacing: Math.round(3 * Theme.scale)

                    Item {
                        width: pet.inner
                        height: Math.round(18 * Theme.scale)
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.7
                            elide: Text.ElideRight
                            text: pet.name
                            color: Theme.text
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.fontFamily
                            font.bold: true
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: pet.full ? "Level 3 · full" : "Level " + pet.level
                            color: pet.full ? Theme.good : Theme.dim
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.fontFamily
                        }
                    }

                    Rectangle {
                        width: pet.inner
                        height: Math.round(14 * Theme.scale)
                        radius: 4
                        color: Qt.rgba(0.36, 0.84, 0.54, 0.16)
                        Rectangle {
                            width: parent.width * (pet.full ? 1 : Math.min(1, pet.points / pet.target))
                            height: parent.height
                            radius: 4
                            color: Theme.good
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: pet.full ? "Full" : pet.points + " / " + pet.target + " to level " + (pet.level + 1)
                            color: Theme.text
                            style: Text.Outline
                            styleColor: Qt.rgba(0, 0, 0, 0.6)
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.fontFamily
                            font.features: { "tnum": 1 }
                        }
                    }

                    Text {
                        visible: !pet.full
                        width: pet.inner
                        wrapMode: Text.WordWrap
                        text: pet.soulsLeft + " to level 3   ·   " + (pet.perMinute > 0 ? (pet.perMinute < 10 ? pet.perMinute.toFixed(1) : Math.round(pet.perMinute)) + "/minute" : "–/minute")
                            + "   ·   next " + pet.eta(pet.target - pet.points) + "   full " + pet.eta(pet.soulsLeft)
                        color: Theme.dim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
