import QtQuick

// The current target's HP, the fight timer, and an estimated time to kill at
// the party's current DPS.
OverlayWidget {
    id: boss

    required property var client
    title: "Boss HP"
    readonly property int width_: Math.round(460 * Theme.scale)
    defaultPos: Qt.point(Math.round(((screen ? screen.width : 2560) - width_) / 2), Math.round(64 * Theme.scale))

    readonly property var target: client.target
    readonly property bool hasHp: target !== null && target.maxHp > 0
    readonly property real currentHp: {
        if (!hasHp) return 0;
        if (target.currentHp >= 0) return target.currentHp;
        return Math.max(0, target.maxHp - target.damageTaken);
    }
    readonly property real fraction: hasHp ? Math.max(0, Math.min(1, currentHp / target.maxHp)) : 0
    readonly property real ttkMs: client.totalDps > 0 && hasHp ? currentHp / client.totalDps * 1000 : -1

    Panel {
        width: boss.width_

        Item {
            width: boss.width_ - Theme.pad * 2
            height: Math.round(18 * Theme.scale)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.6
                elide: Text.ElideRight
                text: boss.target ? boss.target.name : "No target"
                color: Theme.text
                font.pixelSize: Theme.fontNormal
                font.family: Theme.fontFamily
                font.bold: true
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    let t = boss.client.state ? Theme.duration(boss.client.state.battleTimeMs) : "-:--";
                    if (boss.target) t = Theme.compact(boss.target.damageTaken) + " dealt   " + t;
                    return boss.ttkMs > 0 ? t + "   ~" + Theme.duration(boss.ttkMs) + " left" : t;
                }
                color: Theme.dim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            width: boss.width_ - Theme.pad * 2
            height: Math.round(16 * Theme.scale)
            radius: 4
            color: Theme.hpBack

            Rectangle {
                width: parent.width * boss.fraction
                height: parent.height
                radius: 4
                color: Theme.hp
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
            Text {
                anchors.centerIn: parent
                text: boss.hasHp
                    ? Theme.percent(boss.fraction, 1) + "   " + Theme.compact(boss.currentHp) + " / " + Theme.compact(boss.target.maxHp)
                    : (boss.target ? Theme.compact(boss.target.damageTaken) + " dealt" : "")
                color: Theme.text
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.6)
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                font.features: { "tnum": 1 }
            }
        }
    }
}
