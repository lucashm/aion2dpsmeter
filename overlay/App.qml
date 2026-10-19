import QtQuick
import Quickshell

// The app window: pages that need more room than an overlay widget (pets,
// the pet map, analytics), in an ordinary desktop window. Opened from the tray ("Open
// app") or `aion2-meter app`.
FloatingWindow {
    id: app

    required property var client
    required property var settings
    // A run picked in Analytics: the shell opens it in the history widget.
    signal openFight(string id)
    // A sample alert from the Notifications page, for the shell to show in game.
    signal testNotification(var e)

    title: "Daevalog"
    visible: false
    implicitWidth: 1480
    implicitHeight: 940
    color: AppTheme.bg

    readonly property string page: ["pets", "map", "analytics", "notifications"].includes(settings.appPage) ? settings.appPage : "pets"
    // What the Map page shows when opened from a pet: { names, title }; null
    // shows every pet still needed under the Pets page's filters.
    property var mapQuery: null

    function show(page) {
        if (page) settings.setAppPage(page);
        visible = true;
    }
    function openMap(query) {
        mapQuery = query;
        settings.setAppPage("map");
    }
    // The map data (and the portraits in the Pets table): downloaded, or checked for updates.
    onVisibleChanged: if (visible && MapData.status !== "fetching") MapData.fetch()

    readonly property var sections: [
        { title: "IN GAME", pages: [{ id: "pets", label: "Pets", icon: "🐾" }, { id: "map", label: "Map", icon: "🗺" }] },
        { title: "RECORDS", pages: [{ id: "analytics", label: "Analytics", icon: "📈" }] },
        { title: "SETTINGS", pages: [{ id: "notifications", label: "Notifications", icon: "🔔" }] }
    ]

    // ── sidebar ──
    Rectangle {
        id: sidebar
        width: 230
        height: parent.height
        color: AppTheme.sidebar
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: AppTheme.cardEdge }

        Column {
            x: 12
            y: 16
            width: parent.width - 24
            spacing: 4

            Text {
                x: 8
                text: "Daevalog"
                color: AppTheme.text
                font.pixelSize: AppTheme.large
                font.family: AppTheme.font
                font.bold: true
                bottomPadding: 18
            }
            Repeater {
                model: app.sections
                Column {
                    required property var modelData
                    width: parent.width
                    spacing: 2
                    Text {
                        x: 8
                        text: modelData.title
                        color: AppTheme.faint
                        font.pixelSize: 11
                        font.family: AppTheme.font
                        font.bold: true
                        font.letterSpacing: 0.6
                        topPadding: 10
                        bottomPadding: 6
                    }
                    Repeater {
                        model: modelData.pages
                        Rectangle {
                            required property var modelData
                            readonly property bool current: app.page === modelData.id
                            width: parent.width
                            height: 36
                            radius: 6
                            color: current ? AppTheme.row : navArea.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent"
                            Rectangle {
                                visible: parent.current
                                width: 3
                                height: 18
                                radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: AppTheme.accent
                            }
                            Text {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon + "   " + modelData.label
                                color: parent.current ? AppTheme.text : AppTheme.dim
                                font.pixelSize: AppTheme.normal
                                font.family: AppTheme.font
                            }
                            MouseArea {
                                id: navArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // The sidebar's Map is the unfiltered one.
                                    if (modelData.id === "map") app.mapQuery = null;
                                    app.settings.setAppPage(modelData.id);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── page ──
    Item {
        id: area
        anchors.left: sidebar.right
        anchors.right: parent.right
        height: parent.height
        // Pages keep to a readable width, centred; Analytics' table needs more,
        // and scrolls sideways in a narrow window.
        readonly property int pageW: app.page === "analytics" ? Math.max(1240, width - 64) : Math.min(1180, width - 64)

        Flickable {
            anchors.fill: parent
            visible: app.page !== "map"
            contentWidth: Math.max(width, area.pageW + 64)
            contentHeight: pages.height + 64
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Item {
                id: pages
                x: Math.max(32, (area.width - area.pageW) / 2)
                y: 32
                width: area.pageW
                height: app.page === "pets" ? pets.implicitHeight : app.page === "notifications" ? notifications.implicitHeight : analytics.implicitHeight

                PetsPage {
                    id: pets
                    width: parent.width
                    visible: app.page === "pets"
                    client: app.client
                    settings: app.settings
                    onOpenMap: (names, title) => app.openMap(names.length ? { names: names, title: title } : null)
                }
                AnalyticsPage {
                    id: analytics
                    width: parent.width
                    visible: app.page === "analytics"
                    open: app.visible && app.page === "analytics"
                    client: app.client
                    settings: app.settings
                    onOpenFight: id => app.openFight(id)
                }
                NotificationsPage {
                    id: notifications
                    width: parent.width
                    visible: app.page === "notifications"
                    settings: app.settings
                    onTest: e => app.testNotification(e)
                }
            }
        }

        PetMapView {
            x: 32
            y: 24
            width: parent.width - 64
            height: parent.height - 48
            visible: app.page === "map"
            active: app.visible && visible
            client: app.client
            neededNames: pets.model.neededNames
            query: app.mapQuery
            onClearQuery: app.mapQuery = null
        }
    }
}
