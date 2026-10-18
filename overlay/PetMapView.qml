import QtQuick
import QtQuick.Effects

// Where pets spawn: a field map (tiles and spawn clusters from Arkive, see
// MapData.qml) with the pet's portrait on each spawn cluster, ringed in its
// genus's colour, and a panel on the left to pick the map and which pets
// show. The app window's Map page.
Item {
    id: view

    required property var client
    // The pets the Pets page still needs, by name: shown unless a query or
    // "All pets" says otherwise.
    property var neededNames: []
    // Opened from a pet on the Pets page: { names, title }, or null.
    property var query: null
    signal clearQuery()
    // False while the page or the app window is closed: the tiles are let go.
    property bool active: true

    // The panel's filters.
    property string search: ""
    property string scope: "needed"
    readonly property var genuses: ["cogni", "fera", "natura", "varian", "special"]
    property var genus: genuses
    // Pet name -> true for pets unticked in the list.
    property var hidden: ({})

    property string map: ""
    property real zoom: 0.1
    // The tile level for the zoom: 2 = quarter size, 1 = half, 0 = full, as
    // coarse as the map goes.
    readonly property int maxLevel: MapData.mapOf(map).levels
    readonly property int level: Math.min(maxLevel, zoom < 0.3 ? 2 : zoom < 0.6 ? 1 : 0)
    readonly property int full: MapData.mapOf(map).tiles * MapData.tileSize

    readonly property var genusOf: {
        const g = {};
        for (const id in PetData.pets) g[PetData.pets[id].name] = PetData.pets[id].genus;
        return g;
    }
    readonly property var idOf: {
        const ids = {};
        for (const id in PetData.pets) ids[PetData.pets[id].name] = id;
        return ids;
    }
    // The pets the panel lists: the query's, the ones still needed or all
    // with spawns, narrowed by genus and search, closest to level 3 first.
    readonly property var listed: matching(scope, genus, search)
        .map(n => ({ name: n, genus: genusOf[n], left: soulsLeft(n), here: MapData.spawns[n].filter(s => s.map === map).length }))
        .sort((a, b) => a.left - b.left || a.name.localeCompare(b.name))
    readonly property var shown: listed.filter(p => !hidden[p.name]).map(p => p.name)
    // Every spawn cluster of the pets shown, on any map.
    readonly property var allDots: {
        const out = [];
        for (const n of shown) for (const s of MapData.spawns[n] || []) out.push({ name: n, map: s.map, x: s.x, y: s.y, count: s.count });
        return out;
    }
    readonly property var dots: allDots.filter(d => d.map === map)
    property var hovered: null
    // The filters that would show something when nothing shows, to blink:
    // "genus:<g>", "all", "search", "showAll" or "map:<id>".
    readonly property var hints: {
        if (!listed.length) {
            const off = genuses.filter(g => !genus.includes(g));
            const out = off.filter(g => matching(scope, genus.concat([g]), search).length).map(g => "genus:" + g);
            if (!query && scope === "needed" && matching("all", genus, search).length) out.push("all");
            if (out.length) return out;
            // Only several together: every one that adds pets.
            if (matching("all", genuses, search).length) {
                const more = off.filter(g => matching("all", [g], search).length).map(g => "genus:" + g);
                return query || scope === "all" ? more : more.concat(["all"]);
            }
            return search.trim() && matching("all", genuses, "").length ? ["search"] : [];
        }
        if (!shown.length) return ["showAll"];
        if (!dots.length) return MapData.maps.filter(m => allDots.some(d => d.map === m.id)).map(m => "map:" + m.id);
        return [];
    }

    // The pets with spawns for these filters, unsorted.
    function matching(sc, gs, text) {
        const base = query ? query.names : sc === "needed" ? neededNames : Object.keys(MapData.spawns).filter(n => idOf[n] !== undefined);
        const q = text.trim().toLowerCase();
        return base.filter(n => MapData.spawns[n] && gs.includes(genusOf[n]) && (!q || n.toLowerCase().includes(q)));
    }
    // The map with the most of the pets' spawns.
    function pickMap() {
        let best = map || MapData.maps[0].id, most = 0;
        for (const m of MapData.maps) {
            const n = allDots.filter(d => d.map === m.id).length;
            if (n > most) {
                best = m.id;
                most = n;
            }
        }
        if (best !== map) map = best;
    }
    // The whole map in view.
    function fit() {
        zoom = minZoom();
        flick.contentX = 0;
        flick.contentY = 0;
    }
    function minZoom() {
        return Math.min(flick.width / full, flick.height / full);
    }
    // Zoom by `factor`, keeping the map point under (mx, my) in place.
    function zoomAt(factor, mx, my) {
        const z = Math.max(minZoom(), Math.min(1.5, zoom * factor));
        const px = (flick.contentX + mx) / zoom, py = (flick.contentY + my) / zoom;
        zoom = z;
        flick.contentX = Math.max(0, Math.min(full * z - flick.width, px * z - mx));
        flick.contentY = Math.max(0, Math.min(full * z - flick.height, py * z - my));
    }
    // Show one pet's spawns: on the map with most of them, zoomed to fit them.
    function focusOn(name) {
        const spots = MapData.spawns[name] || [];
        if (!spots.length) return;
        const counts = {};
        for (const s of spots) counts[s.map] = (counts[s.map] || 0) + 1;
        const best = Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0];
        if (best !== map) map = best;
        Qt.callLater(() => {
            const here = spots.filter(s => s.map === best);
            const xs = here.map(s => s.x), ys = here.map(s => s.y);
            const pad = 400;
            const w = Math.max(...xs) - Math.min(...xs) + pad * 2, h = Math.max(...ys) - Math.min(...ys) + pad * 2;
            zoom = Math.max(minZoom(), Math.min(1, flick.width / w, flick.height / h));
            flick.contentX = Math.max(0, Math.min(full * zoom - flick.width, ((Math.min(...xs) + Math.max(...xs)) / 2) * zoom - flick.width / 2));
            flick.contentY = Math.max(0, Math.min(full * zoom - flick.height, ((Math.min(...ys) + Math.max(...ys)) / 2) * zoom - flick.height / 2));
        });
    }
    // What the hover card shows about a pet: your level and souls, and the
    // monsters that drop it on this map.
    function petInfo(name) {
        const id = idOf[name];
        const p = client.pets;
        const level = p ? p.levels[id] || 0 : 0;
        const points = p ? p.points[id] || 0 : 0;
        const region = MapData.mapOf(map).region;
        const pet = PetData.pets[id] || { drops: [] };
        return {
            genus: genusOf[name] || "",
            level: level,
            points: points,
            estimated: !!(p && p.estimated && p.estimated.includes(Number(id))),
            left: PetData.left(level, points),
            drops: pet.drops.filter(d => d.region === region)
        };
    }
    function soulsLeft(name) {
        const id = idOf[name];
        const p = client.pets;
        return PetData.left(p ? p.levels[id] || 0 : 0, p ? p.points[id] || 0 : 0);
    }
    function setHidden(names, on) {
        const h = Object.assign({}, hidden);
        for (const n of names) {
            if (on) h[n] = true;
            else delete h[n];
        }
        hidden = h;
    }
    function toggle(list, key) {
        return list.includes(key) ? list.filter(k => k !== key) : list.concat([key]);
    }

    // The map changes only when you pick one, a pet in the list, or a pet's
    // map button on the Pets page; the first open picks the busiest one.
    onQueryChanged: {
        hidden = {};
        search = "";
        // The query's pets show whatever genuses are ticked.
        if (query) genus = genus.concat(genuses.filter(g => !genus.includes(g) && query.names.some(n => genusOf[n] === g)));
        if (query && query.names.length === 1) focusOn(query.names[0]);
    }
    onAllDotsChanged: if (!map && allDots.length) pickMap()
    onMapChanged: Qt.callLater(fit)
    Component.onCompleted: if (MapData.status === "idle") MapData.fetch()

    component Label: Text {
        color: AppTheme.text
        font.pixelSize: AppTheme.normal
        font.family: AppTheme.font
    }
    component Section: Label {
        color: AppTheme.dim
        font.pixelSize: AppTheme.small
        font.bold: true
        font.letterSpacing: 0.5
    }
    // A pulsing outline on a filter that would show results: three blinks,
    // then it stays lit until the filter no longer helps.
    component Blink: Rectangle {
        id: blink
        property bool on
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.color: AppTheme.warn
        border.width: 2
        opacity: 0
        onOnChanged: on ? pulse.restart() : (pulse.stop(), opacity = 0)
        Component.onCompleted: if (on) pulse.restart()
        SequentialAnimation {
            id: pulse
            SequentialAnimation {
                loops: 3
                NumberAnimation { target: blink; property: "opacity"; to: 1; duration: 220 }
                NumberAnimation { target: blink; property: "opacity"; to: 0.15; duration: 220 }
            }
            NumberAnimation { target: blink; property: "opacity"; to: 0.8; duration: 220 }
        }
    }
    component Pill: Rectangle {
        id: pill
        property string label
        property string note
        property bool checked
        property bool hint
        property color tint: AppTheme.accent
        signal clicked()
        height: 30
        radius: 6
        color: checked ? Qt.alpha(tint, 0.18) : pillArea.containsMouse ? AppTheme.rowHover : AppTheme.row
        border.color: checked ? tint : AppTheme.cardEdge
        Label {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            color: pill.checked ? AppTheme.text : AppTheme.dim
            font.pixelSize: AppTheme.small
        }
        Label {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: pill.note
            color: AppTheme.faint
            font.pixelSize: AppTheme.small
            font.features: { "tnum": 1 }
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
        Blink { on: pill.hint }
    }

    // ── the panel ──
    Rectangle {
        id: panel
        width: 320
        height: parent.height
        radius: AppTheme.radius
        color: AppTheme.card
        border.color: AppTheme.cardEdge

        Column {
            id: controls
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 10

            // Search.
            Rectangle {
                width: parent.width
                height: 34
                radius: 6
                color: AppTheme.bg
                border.color: searchInput.activeFocus ? AppTheme.accent : AppTheme.cardEdge
                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    text: view.search
                    onTextEdited: view.search = text
                    color: AppTheme.text
                    font.pixelSize: AppTheme.normal
                    font.family: AppTheme.font
                    clip: true
                    Label {
                        visible: !searchInput.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search pets…"
                        color: AppTheme.faint
                    }
                }
                Blink { on: view.hints.includes("search") }
            }

            // The query from the Pets page.
            Rectangle {
                visible: !!view.query
                width: parent.width
                height: 34
                radius: 6
                color: AppTheme.accentSoft
                border.color: AppTheme.accent
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: clearQ.left
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: view.query ? "Showing: " + view.query.title : ""
                    color: AppTheme.accent
                    font.pixelSize: AppTheme.small
                }
                Label {
                    id: clearQ
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: AppTheme.accent
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.clearQuery()
                    }
                }
            }

            // Maps.
            Section { text: "MAP" }
            Grid {
                width: parent.width
                columns: 3
                spacing: 6
                Repeater {
                    model: MapData.maps
                    Pill {
                        required property var modelData
                        width: (controls.width - 12) / 3
                        label: modelData.name
                        note: String(view.allDots.filter(d => d.map === modelData.id).length)
                        checked: view.map === modelData.id
                        hint: view.hints.includes("map:" + modelData.id)
                        onClicked: view.map = modelData.id
                    }
                }
            }

            // Which pets.
            Section { text: "PETS" }
            Row {
                visible: !view.query
                width: parent.width
                spacing: 6
                Pill {
                    width: (controls.width - 6) / 2
                    label: "Still needed"
                    note: String(view.neededNames.filter(n => MapData.spawns[n]).length)
                    checked: view.scope === "needed"
                    onClicked: view.scope = "needed"
                }
                Pill {
                    width: (controls.width - 6) / 2
                    label: "All pets"
                    checked: view.scope === "all"
                    hint: view.hints.includes("all")
                    onClicked: view.scope = "all"
                }
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [["cogni", "Cogni"], ["fera", "Fera"], ["natura", "Natura"], ["varian", "Varian"], ["special", "Special"]]
                    Pill {
                        required property var modelData
                        width: (controls.width - 12) / 3
                        label: modelData[1]
                        tint: AppTheme.genusColor(modelData[0])
                        checked: view.genus.includes(modelData[0])
                        hint: view.hints.includes("genus:" + modelData[0])
                        onClicked: view.genus = view.toggle(view.genus, modelData[0])
                    }
                }
            }
            Row {
                width: parent.width
                spacing: 6
                Pill {
                    width: (controls.width - 6) / 2
                    label: "Show all"
                    hint: view.hints.includes("showAll")
                    onClicked: view.hidden = {}
                }
                Pill {
                    width: (controls.width - 6) / 2
                    label: "Hide all"
                    onClicked: view.setHidden(view.listed.map(p => p.name), true)
                }
            }
            Label {
                text: view.hints.length ? (view.listed.length && view.shown.length ? "None here: try the highlighted map" : "Nothing shows: try the highlighted filter")
                    : view.shown.length + " of " + view.listed.length + " pets shown  ·  " + view.dots.length + " spawn areas here"
                color: view.hints.length ? AppTheme.warn : AppTheme.faint
                font.pixelSize: AppTheme.small
            }
        }

        // The pets: tick to show, click the name to go to its spawns.
        ListView {
            anchors.top: controls.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            x: 6
            width: parent.width - 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: view.listed
            delegate: Rectangle {
                id: petRow
                required property var modelData
                readonly property bool on: !view.hidden[modelData.name]
                width: ListView.view.width
                height: 44
                radius: 6
                color: rowArea.containsMouse ? AppTheme.rowHover : "transparent"
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.setHidden([petRow.modelData.name], false);
                        view.focusOn(petRow.modelData.name);
                    }
                }
                Rectangle {
                    id: tick
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 4
                    color: petRow.on ? AppTheme.accent : "transparent"
                    border.color: petRow.on ? AppTheme.accent : AppTheme.faint
                    Label {
                        anchors.centerIn: parent
                        visible: petRow.on
                        text: "✓"
                        color: "white"
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.setHidden([petRow.modelData.name], petRow.on)
                    }
                }
                Rectangle {
                    id: face
                    anchors.left: tick.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 6
                    color: Qt.alpha(AppTheme.genusColor(petRow.modelData.genus), 0.2)
                    border.color: AppTheme.genusColor(petRow.modelData.genus)
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: MapData.portraits[petRow.modelData.name] || ""
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                Column {
                    anchors.left: face.right
                    anchors.leftMargin: 10
                    anchors.right: here.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: petRow.modelData.name
                        color: petRow.on ? AppTheme.text : AppTheme.faint
                    }
                    Label {
                        text: petRow.modelData.left ? petRow.modelData.left + " souls to level 3" : "Level 3"
                        color: AppTheme.faint
                        font.pixelSize: 11
                    }
                }
                Label {
                    id: here
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: petRow.modelData.here ? String(petRow.modelData.here) : "–"
                    color: AppTheme.dim
                    font.pixelSize: AppTheme.small
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    // ── the map ──
    Rectangle {
        id: frame
        anchors.left: panel.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        height: parent.height
        radius: AppTheme.radius
        color: "#0A1016"
        border.color: AppTheme.cardEdge
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 1
            contentWidth: view.full * view.zoom
            contentHeight: view.full * view.zoom
            boundsBehavior: Flickable.StopAtBounds
            onWidthChanged: if (view.zoom < view.minZoom()) view.fit()
            onHeightChanged: if (view.zoom < view.minZoom()) view.fit()

            // The tiles, one layer per detail level: quarter size always, half
            // and full size on top once zoomed in enough. A coarser layer stays
            // under the finer one, so zooming never shows a blank map while
            // tiles load. Finer tiles load only on screen (and just past it).
            Repeater {
                model: [2, 1, 0]
                Repeater {
                    id: tileLayer
                    required property int modelData
                    readonly property int n: MapData.mapOf(view.map).tiles >> modelData
                    model: view.map && view.level <= modelData && modelData <= view.maxLevel ? n * n : 0
                    Image {
                        required property int index
                        readonly property real side: view.full / tileLayer.n * view.zoom
                        // Under the portraits, finer layers over coarser ones.
                        z: -1 - tileLayer.modelData
                        x: Math.floor(index / tileLayer.n) * side
                        y: (index % tileLayer.n) * side
                        width: Math.ceil(side)
                        height: Math.ceil(side)
                        readonly property real margin: side / 4
                        readonly property bool onScreen: view.active && (tileLayer.modelData === view.maxLevel
                            || x + width > flick.contentX - margin && x < flick.contentX + flick.width + margin
                            && y + height > flick.contentY - margin && y < flick.contentY + flick.height + margin)
                        source: onScreen ? MapData.tileUrl(view.map, tileLayer.modelData, Math.floor(index / tileLayer.n), index % tileLayer.n) : ""
                        asynchronous: true
                        retainWhileLoading: true
                        cache: true
                        smooth: true
                    }
                }
            }

            Repeater {
                model: view.dots
                // The pet's portrait in a ring of its genus's colour, bigger
                // with more spawns; just the ring's colour until it loads.
                Item {
                    id: dot
                    required property var modelData
                    // Half size with the whole map in view, full size from half zoom up,
                    // so a crowded map stays readable.
                    readonly property real size: (28 + Math.min(12, Math.sqrt(modelData.count) * 1.5)) * Math.max(0.5, Math.min(1, view.zoom * 2))
                    x: modelData.x * view.zoom - size / 2
                    y: modelData.y * view.zoom - size / 2
                    z: dotArea.containsMouse ? 1 : 0
                    width: size
                    height: size
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: AppTheme.genusColor(view.genusOf[dot.modelData.name])
                        border.color: "white"
                        border.width: dotArea.containsMouse ? 2 : 0
                    }
                    Image {
                        id: dotFace
                        anchors.fill: parent
                        anchors.margins: 3
                        source: MapData.portraits[dot.modelData.name] || ""
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    Item {
                        id: round
                        anchors.fill: dotFace
                        layer.enabled: true
                        visible: false
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                        }
                    }
                    MultiEffect {
                        anchors.fill: dotFace
                        source: dotFace
                        visible: dotFace.status === Image.Ready
                        maskEnabled: true
                        maskSource: round
                    }
                    // The dots are rebuilt whenever the pet data changes, so the
                    // hovered one is matched by pet and place, and a dot that goes
                    // while hovered takes the card with it.
                    readonly property bool isHovered: !!view.hovered && view.hovered.name === modelData.name && view.hovered.x === modelData.x && view.hovered.y === modelData.y
                    Component.onDestruction: if (isHovered) view.hovered = null
                    MouseArea {
                        id: dotArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse) view.hovered = dot.modelData;
                            else if (dot.isHovered) view.hovered = null;
                        }
                    }
                }
            }
        }

        // The wheel zooms around the pointer. Above the map so the Flickable
        // doesn't take it for scrolling; it takes no clicks, so dragging still
        // pans and the portraits still get hovered.
        MouseArea {
            anchors.fill: flick
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                const delta = wheel.angleDelta.y || wheel.pixelDelta.y;
                if (delta) view.zoomAt(Math.pow(1.0015, delta), wheel.x, wheel.y);
            }
        }

        // The pet under the pointer: a card beside its portrait.
        Rectangle {
            id: card
            readonly property var info: view.hovered ? view.petInfo(view.hovered.name) : null
            readonly property real dotX: view.hovered ? view.hovered.x * view.zoom - flick.contentX : 0
            readonly property real dotY: view.hovered ? view.hovered.y * view.zoom - flick.contentY : 0
            visible: !!info
            // Right of the portrait, or left of it near the edge; kept inside the map.
            x: dotX + 28 + width < frame.width - 8 ? dotX + 28 : Math.max(8, dotX - 28 - width)
            y: Math.max(8, Math.min(frame.height - height - 8, dotY - 30))
            z: 10
            width: 320
            height: cardCol.implicitHeight + 24
            radius: AppTheme.radius
            color: Qt.alpha(AppTheme.card, 0.97)
            border.color: card.info ? AppTheme.genusColor(card.info.genus) : AppTheme.cardEdge

            Column {
                id: cardCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Row {
                    spacing: 10
                    Rectangle {
                        width: 44
                        height: 44
                        radius: 8
                        clip: true
                        color: card.info ? Qt.alpha(AppTheme.genusColor(card.info.genus), 0.2) : "transparent"
                        Image {
                            anchors.fill: parent
                            source: view.hovered ? MapData.portraits[view.hovered.name] || "" : ""
                            sourceSize: Qt.size(88, 88)
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Label {
                            text: view.hovered ? view.hovered.name : ""
                            font.pixelSize: AppTheme.large
                            font.bold: true
                        }
                        Label {
                            text: card.info ? card.info.genus.charAt(0).toUpperCase() + card.info.genus.slice(1) + "  ·  "
                                + (card.info.level === 0 ? "Not collected" : "Lv. " + card.info.level + (card.info.estimated ? " Est." : "")) : ""
                            color: card.info ? AppTheme.genusColor(card.info.genus) : AppTheme.dim
                            font.pixelSize: AppTheme.small
                        }
                    }
                }

                // Souls toward the next level, and to the top.
                Column {
                    width: parent.width
                    spacing: 4
                    readonly property bool full: !!card.info && card.info.level >= PetData.maxLevel
                    Item {
                        width: parent.width
                        height: soulsLabel.implicitHeight
                        Label {
                            id: soulsLabel
                            text: !card.info ? "" : parent.parent.full ? "Level 3 · full"
                                : card.info.points + " / " + PetData.needed[card.info.level] + " souls to Lv. " + (card.info.level + 1)
                            font.pixelSize: AppTheme.small
                        }
                        Label {
                            anchors.right: parent.right
                            visible: !parent.parent.full
                            text: card.info ? card.info.left + " to level 3" : ""
                            color: AppTheme.dim
                            font.pixelSize: AppTheme.small
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle {
                            width: !card.info ? 0 : parent.parent.full ? parent.width
                                : parent.width * Math.min(1, card.info.points / PetData.needed[card.info.level])
                            height: parent.height
                            radius: 2
                            color: card.info ? AppTheme.genusColor(card.info.genus) : AppTheme.accent
                        }
                    }
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    // Abyss pets have no spawn points, only the zone.
                    text: !view.hovered ? "" : view.hovered.zone
                        ? "Somewhere in " + view.hovered.zone + "  ·  about " + view.hovered.count + (view.hovered.count === 1 ? " spawn" : " spawns")
                        : "This spot: " + view.hovered.count + (view.hovered.count === 1 ? " spawn" : " spawns")
                    color: AppTheme.dim
                    font.pixelSize: AppTheme.small
                }

                // The monsters that drop it on this map.
                Repeater {
                    model: card.info ? card.info.drops.slice(0, 3) : []
                    Column {
                        required property var modelData
                        width: cardCol.width
                        spacing: 1
                        Label {
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.npc + (modelData.level ? "  Lv. " + modelData.level : "") + (modelData.chance && modelData.chance !== "100%" ? "  ·  " + modelData.chance : "")
                            font.pixelSize: AppTheme.small
                        }
                        Label {
                            readonly property var k: modelData.kibelisk || (modelData.bySide ? Object.values(modelData.bySide)[0] : null)
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: [modelData.zones.join(", "), k ? (k.teleport ? "teleport #" + k.teleport + " " : "near ") + k.name + " · " + k.m + " m" : ""].filter(t => t).join("  ·  ")
                            color: AppTheme.faint
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // Download state.
        Label {
            anchors.centerIn: parent
            visible: MapData.status === "fetching" || MapData.status === "failed"
            text: MapData.status === "fetching" ? "Downloading the map…" : "Couldn't download the map. Check your connection and open it again."
            color: AppTheme.dim
            font.pixelSize: AppTheme.large
        }
        Label {
            anchors.centerIn: parent
            visible: MapData.status === "ready" && !!view.query && view.query.names.every(n => !MapData.spawns[n])
            text: "No known spawns for " + (view.query && view.query.names.length === 1 ? "this pet" : "these pets") + " on the field maps (dungeon or Abyss drops)."
            color: AppTheme.dim
        }

        // Zoom buttons and credit.
        Column {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 6
            Repeater {
                model: [["+", 1.4], ["−", 1 / 1.4], ["⤢", 0]]
                Rectangle {
                    required property var modelData
                    width: 32
                    height: 32
                    radius: 6
                    color: zoomArea.containsMouse ? AppTheme.rowHover : Qt.alpha(AppTheme.card, 0.9)
                    border.color: AppTheme.cardEdge
                    Label {
                        anchors.centerIn: parent
                        text: modelData[0]
                        font.pixelSize: AppTheme.large
                    }
                    MouseArea {
                        id: zoomArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData[1] ? view.zoomAt(modelData[1], flick.width / 2, flick.height / 2) : view.fit()
                    }
                }
            }
        }
        Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            text: "Map and spawns: Arkive by tc-imba (CC BY-NC 4.0)"
            color: AppTheme.faint
            font.pixelSize: 11
        }
    }
}
