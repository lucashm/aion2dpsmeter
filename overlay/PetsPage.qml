import QtQuick
import QtQuick.Layouts

// Every pet with your level and souls, the phase you farm in, and where to
// find the pets you still need. A page of the app window (App.qml).
Item {
    id: page

    required property var client
    required property var settings
    // Open the Map page on these pets (none: every pet still needed).
    signal openMap(var names, string title)

    implicitHeight: content.implicitHeight

    property string search: ""
    property bool showDone: false
    property bool showNotFarmed: false
    property bool sortOpen: false

    readonly property var pets: client.pets
    readonly property var model: petsModel(PetData.pets, pets ? pets.levels : {}, pets ? pets.points : {}, pets ? pets.estimated || [] : [], {
        phase: settings.petsPhase,
        genus: settings.petsGenus,
        farmIn: settings.petsFarmIn,
        search: search,
        sort: settings.petsSort
    })
    readonly property var phaseTitles: ({ 1: "Collect every pet", 2: "Take every pet to level 2", 3: "Take every pet to level 3" })
    readonly property var sorts: [
        { key: "closest", label: "Closest to done" },
        { key: "name", label: "Name" },
        { key: "level", label: "Level" }
    ]
    readonly property var genuses: [
        { key: "cogni", label: "Cogni" }, { key: "fera", label: "Fera" }, { key: "natura", label: "Natura" },
        { key: "varian", label: "Varian" }, { key: "special", label: "Special" }
    ]
    readonly property var areas: [
        { key: "elyos", label: "Elyos" }, { key: "asmodian", label: "Asmodian" }, { key: "abyss", label: "Abyss" }, { key: "other", label: "Other" }
    ]
    readonly property bool live: !!(client.capture && client.capture.locked)
    readonly property string character: client.state && client.state.character ? client.state.character : ""

    // Which side's ground a drop's region is: "elyos", "asmodian", "abyss" or "other".
    function areaOf(region) {
        if (PetData.sideMaps.elyos.includes(region)) return "elyos";
        if (PetData.sideMaps.asmodian.includes(region)) return "asmodian";
        return region.includes("Reshanta") ? "abyss" : "other";
    }

    // Everything the page shows, from the pet data, your levels and points,
    // and the filters: { phase, farmable, phaseCounts, needed, done,
    // notFarmed, soulsNeeded, genus, collected, total, nextReward }.
    function petsModel(all, levels, points, estimated, o) {
        const needed = PetData.needed;
        const souls = (level, pts, upTo) => Math.max(0, needed.slice(level, upTo).reduce((n, x) => n + x, 0) - pts);
        const q = (o.search || "").trim().toLowerCase();
        const list = [];
        const genus = {};
        let collected = 0;
        for (const id in all) {
            const p = all[id];
            const level = levels[id] || 0;
            const pts = points[id] || 0;
            const g = genus[p.genus] || (genus[p.genus] = { collected: 0, total: 0 });
            g.total++;
            if (level >= 1) {
                g.collected++;
                collected++;
            }
            // The easiest monster in the areas you farm: lowest level, then most spawns.
            const drops = p.drops.filter(d => o.farmIn.includes(areaOf(d.region)));
            drops.sort((a, b) => a.level - b.level || b.spawns - a.spawns);
            const drop = drops.length ? drops[0] : null;
            list.push({
                id: id, name: p.name, genus: p.genus, level: level, points: pts,
                estimated: estimated.includes(Number(id)),
                drop: drop,
                farmable: !!drop && !p.unreleased && p.genus !== "special" && o.genus.includes(p.genus),
                toMax: souls(level, pts, needed.length),
                matches: !q || p.name.toLowerCase().includes(q) || p.drops.some(d => d.npc.toLowerCase().includes(q))
            });
        }
        const farmable = list.filter(p => p.farmable);
        const phaseCounts = {};
        for (let l = 1; l <= needed.length; l++) phaseCounts[l] = farmable.filter(p => p.level >= l).length;
        // The level you farm toward: 1, 2 or 3 (anything else, such as an
        // old "auto", is 3).
        const phase = Number(o.phase) >= 1 && Number(o.phase) <= needed.length ? Number(o.phase) : needed.length;
        for (const p of list) p.toPhase = souls(p.level, p.points, phase);
        const by = {
            // Closest to level 3: the fewest souls left to the top.
            closest: (a, b) => a.toMax - b.toMax || a.name.localeCompare(b.name),
            name: (a, b) => a.name.localeCompare(b.name),
            level: (a, b) => b.level - a.level || a.name.localeCompare(b.name)
        }[o.sort] || ((a, b) => a.name.localeCompare(b.name));
        const shown = p => p.matches;
        const neededNow = farmable.filter(p => p.level < phase);
        const milestones = PetData.collectionRewards;
        return {
            phase: phase,
            farmable: farmable.length,
            phaseCounts: phaseCounts,
            needed: neededNow.filter(shown).sort(by),
            neededCount: neededNow.length,
            neededNames: neededNow.map(p => p.name),
            soulsNeeded: neededNow.reduce((n, p) => n + p.toPhase, 0),
            done: farmable.filter(p => p.level >= phase).filter(shown).sort(by),
            notFarmed: list.filter(p => !p.farmable).filter(shown).sort(by),
            notFarmedCount: list.length - farmable.length,
            genus: genus,
            collected: collected,
            total: list.length,
            nextReward: milestones.find(m => m.at > collected) || null
        };
    }

    function toggle(list, key) {
        return list.includes(key) ? list.filter(k => k !== key) : list.concat([key]);
    }

    // ── bits ──
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
    component Check: Item {
        id: check
        property string label
        property string note
        property bool checked
        signal toggled()
        width: parent ? parent.width : 200
        height: 26
        Rectangle {
            id: box
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 4
            color: check.checked ? AppTheme.accent : "transparent"
            border.color: check.checked ? AppTheme.accent : AppTheme.faint
            Text {
                anchors.centerIn: parent
                visible: check.checked
                text: "✓"
                color: "white"
                font.pixelSize: 11
                font.bold: true
            }
        }
        Label {
            anchors.left: box.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: check.label
        }
        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: check.note
            color: AppTheme.dim
            font.pixelSize: AppTheme.small
            font.features: { "tnum": 1 }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: check.toggled()
        }
    }
    component Card: Rectangle {
        color: AppTheme.card
        radius: AppTheme.radius
        border.color: AppTheme.cardEdge
    }
    component Bar: Rectangle {
        property real value: 0
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.08)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: 2
            color: AppTheme.accent
        }
    }

    Column {
        id: content
        width: page.width
        spacing: 20

        // ── header ──
        Item {
            width: parent.width
            height: 64
            Column {
                spacing: 6
                Label {
                    text: "Pets"
                    font.pixelSize: AppTheme.title
                    font.bold: true
                }
                Label {
                    text: "Every pet with your level and souls, the phase you farm in and where to find the pets you still need."
                    color: AppTheme.dim
                }
            }
            Row {
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: pill.implicitWidth + 24
                    radius: 13
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: AppTheme.cardEdge
                    Row {
                        id: pill
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 4
                            color: page.live ? AppTheme.good : AppTheme.faint
                        }
                        Label {
                            text: page.live ? "Live" + (page.character ? " · " + page.character : "") : "Offline"
                            font.pixelSize: AppTheme.small
                        }
                    }
                }
                Rectangle {
                    height: 34
                    width: mapButton.implicitWidth + 28
                    radius: 6
                    color: mapArea.containsMouse ? Qt.lighter(AppTheme.accent, 1.12) : AppTheme.accent
                    Label {
                        id: mapButton
                        anchors.centerIn: parent
                        text: "Open the map"
                        color: "white"
                        font.bold: true
                    }
                    MouseArea {
                        id: mapArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.openMap([], "")
                    }
                }
            }
        }

        // ── how it works ──
        Card {
            visible: !page.settings.petsHelpHidden
            width: parent.width
            height: help.implicitHeight + 40
            color: Qt.rgba(0.24, 0.55, 1, 0.05)
            border.color: Qt.rgba(0.24, 0.55, 1, 0.35)
            Column {
                id: help
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 14
                Label {
                    text: "How pet farming works"
                    font.pixelSize: AppTheme.large
                    font.bold: true
                }
                RowLayout {
                    width: parent.width
                    spacing: 24
                    Repeater {
                        model: [
                            ["Kill a pet's monster for its souls", "5 souls collect the pet, 25 more take it to level 2 and 75 more to level 3. Every level adds to your stats."],
                            ["Every pet first, then the next level", "Collecting gives 100 Genus EXP per soul, level 2 only 10 and level 3 about 3. So collect every pet, then take all to level 2, then to 3."],
                            ["Pick an area and open the map", "The map then shows where the pets you still need spawn, and the pet souls widget tracks the ones you farm."]
                        ]
                        Row {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 10
                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                color: AppTheme.accentSoft
                                Label {
                                    anchors.centerIn: parent
                                    text: index + 1
                                    color: AppTheme.accent
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                            Column {
                                width: parent.width - 30
                                spacing: 3
                                Label {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: modelData[0]
                                    font.bold: true
                                }
                                Label {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: modelData[1]
                                    color: AppTheme.dim
                                    font.pixelSize: AppTheme.small
                                }
                            }
                        }
                    }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "ⓘ  Your progress comes from the game while the meter runs. A level-up shows as Est. until the game confirms it (when you teleport or log in)."
                    color: AppTheme.dim
                    font.pixelSize: AppTheme.small
                }
            }
            Label {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                text: "✕"
                color: AppTheme.dim
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.settings.setPetsHelpHidden(true)
                }
            }
        }

        // ── filters and table ──
        Row {
            width: parent.width
            spacing: 20

            Card {
                id: filters
                width: 220
                height: filterCol.implicitHeight + 32
                Column {
                    id: filterCol
                    x: 16
                    y: 16
                    width: parent.width - 32
                    spacing: 4

                    Section { text: "PHASE" }
                    Repeater {
                        model: [1, 2, 3]
                        Check {
                            required property int modelData
                            label: "Lv. " + modelData
                            note: (page.model.phaseCounts[modelData] || 0) + " / " + page.model.farmable
                            checked: page.model.phase === modelData
                            onToggled: page.settings.setPetsPhase(modelData)
                        }
                    }

                    Item { width: 1; height: 12 }
                    Section { text: "GENUS INSIGHT" }
                    Repeater {
                        model: page.genuses
                        Check {
                            required property var modelData
                            readonly property var g: page.model.genus[modelData.key] || { collected: 0, total: 0 }
                            readonly property var insight: page.pets && page.pets.genus ? page.pets.genus[modelData.key] : null
                            label: modelData.label
                            note: g.collected + " / " + g.total + (insight ? " · Lv. " + insight.level : "")
                            checked: page.settings.petsGenus.includes(modelData.key)
                            onToggled: page.settings.setPetsGenus(page.toggle(page.settings.petsGenus, modelData.key))
                        }
                    }

                    Item { width: 1; height: 12 }
                    Item {
                        width: parent.width
                        height: farmTitle.height
                        Section { id: farmTitle; text: "FARM IN" }
                        Label {
                            anchors.right: parent.right
                            text: "Reset"
                            color: AppTheme.accent
                            font.pixelSize: AppTheme.small
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.settings.setPetsFarmIn(["elyos", "asmodian", "abyss"])
                            }
                        }
                    }
                    Repeater {
                        model: page.areas
                        Check {
                            required property var modelData
                            label: modelData.label
                            checked: page.settings.petsFarmIn.includes(modelData.key)
                            onToggled: page.settings.setPetsFarmIn(page.toggle(page.settings.petsFarmIn, modelData.key))
                        }
                    }

                    Item { width: 1; height: 12 }
                    Section { text: "COLLECTION" }
                    Item {
                        width: parent.width
                        height: 24
                        Label { text: "Collected" }
                        Label {
                            anchors.right: parent.right
                            text: page.model.collected + " / " + page.model.total
                            color: AppTheme.dim
                            font.features: { "tnum": 1 }
                        }
                    }
                    Item {
                        visible: !!page.model.nextReward
                        width: parent.width
                        height: 24
                        Label {
                            text: page.model.nextReward ? page.model.nextReward.reward : ""
                            width: parent.width - rewardAt.implicitWidth - 6
                            elide: Text.ElideRight
                            font.pixelSize: AppTheme.small
                        }
                        Label {
                            id: rewardAt
                            anchors.right: parent.right
                            text: page.model.nextReward ? "at " + page.model.nextReward.at + " pets" : ""
                            color: AppTheme.dim
                            font.pixelSize: AppTheme.small
                        }
                    }
                }
            }

            Column {
                width: parent.width - filters.width - 20
                spacing: 14

                // Phase title, counts and progress.
                Row {
                    width: parent.width
                    spacing: 10
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.phaseTitles[page.model.phase]
                        font.pixelSize: AppTheme.large
                        font.bold: true
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·  " + page.model.neededCount + " pets needed  ·  " + page.model.soulsNeeded + " souls"
                        color: AppTheme.dim
                    }
                    Bar {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 110
                        value: page.model.farmable ? page.model.phaseCounts[page.model.phase] / page.model.farmable : 0
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.model.phaseCounts[page.model.phase] + " / " + page.model.farmable
                        color: AppTheme.dim
                        font.pixelSize: AppTheme.small
                    }
                }

                // Search and sort.
                Row {
                    anchors.right: parent.right
                    spacing: 10
                    z: 2
                    Rectangle {
                        width: 240
                        height: 34
                        radius: 6
                        color: AppTheme.card
                        border.color: searchInput.activeFocus ? AppTheme.accent : AppTheme.cardEdge
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: AppTheme.text
                            font.pixelSize: AppTheme.normal
                            font.family: AppTheme.font
                            clip: true
                            onTextEdited: page.search = text
                            Label {
                                visible: !searchInput.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search pets or monsters"
                                color: AppTheme.faint
                            }
                        }
                    }
                    Rectangle {
                        width: 190
                        height: 34
                        radius: 6
                        color: AppTheme.card
                        border.color: page.sortOpen ? AppTheme.accent : AppTheme.cardEdge
                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: (page.sorts.find(s => s.key === page.settings.petsSort) || page.sorts[0]).label
                        }
                        Label {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌄"
                            color: AppTheme.dim
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.sortOpen = !page.sortOpen
                        }
                        Rectangle {
                            visible: page.sortOpen
                            y: parent.height + 4
                            width: parent.width
                            height: sortList.implicitHeight + 8
                            radius: 6
                            color: AppTheme.card
                            border.color: AppTheme.cardEdge
                            Column {
                                id: sortList
                                y: 4
                                width: parent.width
                                Repeater {
                                    model: page.sorts
                                    Rectangle {
                                        required property var modelData
                                        width: sortList.width
                                        height: 30
                                        color: sortArea.containsMouse ? AppTheme.rowHover : "transparent"
                                        Label {
                                            x: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: modelData.key === page.settings.petsSort ? AppTheme.accent : AppTheme.text
                                        }
                                        MouseArea {
                                            id: sortArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                page.settings.setPetsSort(modelData.key);
                                                page.sortOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // The table.
                Card {
                    width: parent.width
                    height: table.implicitHeight
                    clip: true
                    Column {
                        id: table
                        width: parent.width

                        readonly property var cols: [0.27, 0.15, 0.15, 0.25, 0.13, 0.05]
                        function colX(i) {
                            let x = 16;
                            for (let k = 0; k < i; k++) x += cols[k] * (width - 32);
                            return x;
                        }

                        Item {
                            width: parent.width
                            height: 40
                            Repeater {
                                model: ["PET", "LEVEL", "SOULS", "MONSTER", "WHERE"]
                                Section {
                                    required property string modelData
                                    required property int index
                                    x: table.colX(index)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                }
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: AppTheme.cardEdge }
                        }

                        Group {
                            host: page
                            tbl: table
                            title: "Needed now"
                            note: page.model.neededCount + " pets · " + page.model.soulsNeeded + " souls"
                            titleColor: AppTheme.accent
                            open: true
                            rows: page.model.needed
                        }
                        Group {
                            host: page
                            tbl: table
                            title: "Done for this phase"
                            note: page.model.phaseCounts[page.model.phase] + " pets"
                            titleColor: AppTheme.good
                            open: page.showDone
                            onToggle: page.showDone = !page.showDone
                            rows: page.model.done
                        }
                        Group {
                            host: page
                            tbl: table
                            title: "Not farmed"
                            note: page.model.notFarmedCount + " pets · where you don't farm, not on the map or not from monsters"
                            titleColor: AppTheme.text
                            open: page.showNotFarmed
                            onToggle: page.showNotFarmed = !page.showNotFarmed
                            rows: page.model.notFarmed
                        }
                    }
                }
            }
        }
    }

    // A collapsible group of pet rows in the table.
    component Group: Column {
        id: group
        required property var host
        required property var tbl
        property string title
        property string note
        property color titleColor
        property bool open
        property var rows: []
        signal toggle()
        width: group.tbl.width

        Item {
            width: parent.width
            height: 38
            Row {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Label {
                    text: group.open ? "⌄" : "›"
                    color: AppTheme.dim
                    width: 12
                }
                Label {
                    text: group.title
                    color: group.titleColor
                    font.bold: true
                }
                Label {
                    text: group.note
                    color: AppTheme.dim
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: group.toggle()
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: AppTheme.cardEdge }
        }
        Repeater {
            model: group.open ? group.rows : []
            PetRow {
                host: group.host
                tbl: group.tbl
            }
        }
    }

    component PetRow: Rectangle {
        id: row
        required property var modelData
        required property var host
        required property var tbl
        readonly property var p: modelData
        readonly property bool full: p.level >= PetData.maxLevel
        width: row.tbl.width
        height: 52
        color: rowArea.containsMouse ? AppTheme.rowHover : "transparent"
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
        }

        // Pet: portrait, name, genus.
        Row {
            x: row.tbl.colX(0)
            width: row.tbl.cols[0] * (row.tbl.width - 32)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                width: 32
                height: 32
                radius: 6
                color: Qt.alpha(AppTheme.genusColor(row.p.genus), 0.18)
                clip: true
                Image {
                    id: portrait
                    anchors.fill: parent
                    source: MapData.portraits[row.p.name] || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Label {
                    anchors.centerIn: parent
                    visible: portrait.status !== Image.Ready
                    text: row.p.name.charAt(0)
                    color: AppTheme.genusColor(row.p.genus)
                    font.bold: true
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 42
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.p.name
                }
                Label {
                    text: row.p.genus.charAt(0).toUpperCase() + row.p.genus.slice(1)
                    color: AppTheme.dim
                    font.pixelSize: AppTheme.small
                }
            }
        }
        // Level.
        Label {
            x: row.tbl.colX(1)
            anchors.verticalCenter: parent.verticalCenter
            text: row.p.level === 0 ? "Not collected" : "Lv. " + row.p.level + (row.p.estimated ? " Est." : "")
            color: row.p.level === 0 ? AppTheme.dim : AppTheme.text
        }
        // Souls toward the next level.
        Row {
            x: row.tbl.colX(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Label {
                text: row.full ? "Max" : row.p.points + " / " + PetData.needed[row.p.level]
                font.features: { "tnum": 1 }
            }
            Bar {
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.full
                width: 50
                value: row.full ? 1 : row.p.points / PetData.needed[row.p.level]
            }
        }
        // Monster and where.
        Label {
            x: row.tbl.colX(3)
            width: row.tbl.cols[3] * (row.tbl.width - 32) - 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: row.p.drop ? row.p.drop.npc + (row.p.drop.level ? " <font color=\"" + AppTheme.dim + "\">Lv. " + row.p.drop.level + "</font>" : "") : "–"
        }
        Label {
            x: row.tbl.colX(4)
            width: row.tbl.cols[4] * (row.tbl.width - 32) - 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.p.drop ? row.p.drop.region : ""
        }
        Label {
            x: row.tbl.colX(5)
            anchors.verticalCenter: parent.verticalCenter
            visible: !!MapData.spawns[row.p.name]
            text: "⌖"
            color: mapIcon.containsMouse ? AppTheme.accent : AppTheme.dim
            font.pixelSize: AppTheme.large
            MouseArea {
                id: mapIcon
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.host.openMap([row.p.name], row.p.name)
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.04) }
    }
}
