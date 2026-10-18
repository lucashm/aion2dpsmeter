import QtQuick

// Past runs side by side: every saved fight's players, grouped by player,
// class or boss (or one row per run), filtered and sorted, with the picked
// row's runs in a pane beside the table. A page of the app window (App.qml).
Item {
    id: an

    required property var client
    required property var settings
    // The page is on screen: the fight list is fetched then.
    property bool open: false
    // "player", "job", "boss" or "run"
    property string group: "player"
    property string sortKey: "avgDps"
    property bool sortDesc: true
    // 0 = all time, else the last this many days.
    property int periodDays: 0
    property bool killsOnly: false
    property bool meOnly: false
    // Group name -> the value runs must have there ({ boss: "Vakron" }).
    property var filters: ({})
    property string selectedKey: ""
    // The sparkline bar under the pointer, or null.
    property var hoverRun: null

    signal openFight(string id)

    // Every name you've played, so "Me" works with the game closed.
    readonly property string localName: {
        const me = client.players.find(p => p.isLocal);
        return me ? me.name : "";
    }
    onLocalNameChanged: if (localName) settings.addMyName(localName)

    // One entry per player per fight, oldest first.
    readonly property var runs: {
        const mine = settings.myNames;
        const out = [];
        for (const f of client.history) {
            const seconds = Math.max(1, f.durationMs / 1000);
            for (const p of f.players) {
                // Actors the roster never named: not anyone to compare.
                if (p.name.startsWith("#")) continue;
                out.push({
                    fightId: f.id, boss: f.bossName || "Unknown", start: f.startTimeMs, durationMs: f.durationMs, killed: f.killed,
                    player: p.name, job: p.job, jobKey: p.jobKey, isMe: mine.includes(p.name),
                    dps: p.dps, damage: p.damage, share: f.totalDamage > 0 ? p.damage / f.totalDamage : 0,
                    // Missing from a daemon older than the overlay.
                    critRate: p.critRate || 0, backRate: p.backRate || 0,
                    healPs: (p.heal || 0) / seconds, takenPs: (p.damageTaken || 0) / seconds, deaths: p.deaths || 0,
                    gearScore: p.gearScore || 0, combatPower: p.combatPower || 0
                });
            }
        }
        return out.sort((a, b) => a.start - b.start);
    }

    readonly property var filtered: {
        const since = periodDays ? Date.now() - periodDays * 86400000 : 0;
        const f = filters;
        return runs.filter(r => r.start >= since && (!killsOnly || r.killed) && (!meOnly || r.isMe)
            && Object.keys(f).every(k => keyOf(r, k) === f[k]));
    }

    readonly property var rows: {
        const g = group;
        const byKey = {};
        for (const r of filtered) {
            const k = keyOf(r, g);
            (byKey[k] = byKey[k] || []).push(r);
        }
        const avg = (rs, f) => rs.reduce((t, r) => t + f(r), 0) / rs.length;
        const out = Object.keys(byKey).map(key => {
            const rs = byKey[key];
            const last = rs[rs.length - 1];
            const avgDps = avg(rs, r => r.dps);
            return {
                key: key, runs: rs, count: rs.length,
                label: g === "player" ? last.player : g === "job" ? last.job : g === "boss" ? last.boss : last.boss + "  ·  " + last.player,
                job: last.job, jobKey: g === "boss" ? "" : last.jobKey, isMe: (g === "player" || g === "run") && last.isMe,
                start: last.start, durationMs: last.durationMs, killed: last.killed,
                avgDps: avgDps, bestDps: Math.max(...rs.map(r => r.dps)),
                share: avg(rs, r => r.share), critRate: avg(rs, r => r.critRate), backRate: avg(rs, r => r.backRate),
                healPs: avg(rs, r => r.healPs), takenPs: avg(rs, r => r.takenPs), deaths: avg(rs, r => r.deaths),
                killRate: avg(rs, r => r.killed ? 1 : 0),
                // The last 5 runs against all of them.
                trend: rs.length >= 6 ? avg(rs.slice(-5), r => r.dps) / Math.max(1, avgDps) - 1 : NaN
            };
        });
        const k = sortKey, dir = sortDesc ? -1 : 1;
        const num = v => isNaN(v) ? -Infinity : Number(v);
        return out.sort((a, b) => dir * (typeof a[k] === "string" ? a[k].localeCompare(b[k]) : num(a[k]) - num(b[k])));
    }

    // The picked row; else yours; else the top one.
    readonly property var sel: rows.find(r => r.key === selectedKey) || rows.find(r => r.isMe) || rows[0] || null
    // What the pane's "best by" list is broken down by.
    readonly property string other: group === "player" ? "boss" : "player"

    readonly property var groupNames: ({ player: "Player", job: "Class", boss: "Boss", run: "Run" })
    readonly property int colW: Math.round(62 * Theme.scale)
    readonly property var common: [
        { key: "share", title: "Share", fmt: v => Theme.percent(v, 0) },
        { key: "critRate", title: "Crit", fmt: v => Theme.percent(v, 0) },
        { key: "backRate", title: "Back", fmt: v => Theme.percent(v, 0) },
        { key: "healPs", title: "Heal/s", fmt: v => v > 0 ? Theme.compact(v) : "–" },
        { key: "takenPs", title: "Taken/s", fmt: v => Theme.compact(v) }
    ]
    readonly property var columns: group === "run" ? [
        { key: "start", title: "Date", w: 1.7, fmt: v => new Date(v).toLocaleString(Qt.locale(), "d MMM HH:mm") },
        { key: "durationMs", title: "Time", fmt: v => Theme.duration(v) },
        { key: "avgDps", title: "DPS", main: true, fmt: v => Theme.compact(v) }
    ].concat(common, [
        { key: "deaths", title: "Deaths", fmt: v => v > 0 ? String(v) : "–" },
        { key: "killed", title: "Kill", fmt: v => v ? "✓" : "", color: () => Theme.good }
    ]) : [
        { key: "count", title: "Runs", fmt: v => String(v) },
        { key: "avgDps", title: "Avg DPS", main: true, fmt: v => Theme.compact(v) },
        { key: "bestDps", title: "Best DPS", fmt: v => Theme.compact(v) }
    ].concat(common, [
        { key: "deaths", title: "Deaths", fmt: v => v.toFixed(1) },
        { key: "killRate", title: "Kill %", fmt: v => Theme.percent(v, 0) },
        {
            key: "trend", title: "Trend",
            fmt: v => isNaN(v) ? "–" : (v >= 0 ? "▲ " : "▼ ") + Math.abs(v * 100).toFixed(0) + "%",
            color: v => isNaN(v) ? Theme.faint : v >= 0 ? Theme.good : Theme.bad
        }
    ])

    implicitHeight: card.implicitHeight
    readonly property int width_: Math.max(Math.round(900 * Theme.scale), width)
    readonly property int paneW: Math.round(300 * Theme.scale)
    readonly property int tableW: width_ - Theme.pad * 3 - paneW
    readonly property int labelW: Math.max(Math.round(80 * Theme.scale), tableW - columns.reduce((t, c) => t + Math.round((c.w || 1) * colW), 0))

    onOpenChanged: if (open) client.requestHistory()
    Connections {
        target: an.client
        function onFightSaved() {
            if (an.open) an.client.requestHistory();
        }
    }

    function keyOf(r, g) {
        return g === "player" ? r.player : g === "job" ? r.jobKey : g === "boss" ? r.boss : r.fightId + "/" + r.player;
    }
    function setGroup(g) {
        group = g;
        sortKey = g === "run" ? "start" : "avgDps";
        sortDesc = true;
        selectedKey = "";
    }
    function sortBy(k) {
        if (sortKey === k) sortDesc = !sortDesc;
        else {
            sortKey = k;
            sortDesc = k !== "label";
        }
    }
    // `filters` is replaced, never mutated, so bindings see the change.
    function setFilter(g, value) {
        const f = Object.assign({}, filters);
        if (value === undefined) delete f[g];
        else f[g] = value;
        filters = f;
    }
    function filterLabel(g, value) {
        const r = runs.find(r => keyOf(r, g) === value);
        return groupNames[g] + ": " + (g === "job" && r ? r.job : value);
    }
    function date(ms) {
        return new Date(ms).toLocaleString(Qt.locale(), "d MMM");
    }

    Panel {
        id: card
        width: an.width_
        color: Qt.alpha(Theme.panel, 1)

        // ── title ──
        Item {
            width: an.width_ - Theme.pad * 2
            height: Math.round(22 * Theme.scale)
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.pad
                Text {
                    text: "Analytics"
                    color: Theme.text
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.fontFamily
                    font.bold: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: an.filtered.length + " runs  ·  last " + an.client.history.length + " fights"
                    color: Theme.faint
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
            }
        }

        // ── grouping and filters ──
        Item {
            width: an.width_ - Theme.pad * 2
            height: groupRow.height
            Row {
                id: groupRow
                spacing: Math.round(4 * Theme.scale)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Group by"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
                Repeater {
                    model: ["player", "job", "boss", "run"]
                    Chip {
                        required property string modelData
                        label: modelData === "run" ? "Runs" : an.groupNames[modelData]
                        checked: an.group === modelData
                        onClicked: an.setGroup(modelData)
                    }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: Math.round(4 * Theme.scale)
                Chip {
                    label: an.periodDays ? "Last " + an.periodDays + " days ▸" : "All time ▸"
                    onClicked: an.periodDays = an.periodDays === 0 ? 30 : an.periodDays === 30 ? 7 : 0
                }
                Chip {
                    label: "Kills only"
                    checked: an.killsOnly
                    onClicked: an.killsOnly = !an.killsOnly
                }
                Chip {
                    label: "Me only"
                    checked: an.meOnly
                    onClicked: an.meOnly = !an.meOnly
                }
            }
        }
        Row {
            visible: Object.keys(an.filters).length > 0
            spacing: Math.round(4 * Theme.scale)
            Repeater {
                model: Object.keys(an.filters)
                Chip {
                    required property string modelData
                    label: an.filterLabel(modelData, an.filters[modelData]) + "  ✕"
                    onClicked: an.setFilter(modelData)
                }
            }
        }

        Row {
            spacing: Theme.pad

            // ── table ──
            Column {
                width: an.tableW
                spacing: Math.round(3 * Theme.scale)

                Row {
                    Repeater {
                        model: [{ key: "label", title: an.groupNames[an.group] }].concat(an.columns)
                        Text {
                            required property var modelData
                            required property int index
                            width: index === 0 ? an.labelW : Math.round((modelData.w || 1) * an.colW)
                            leftPadding: index === 0 ? Math.round(6 * Theme.scale) : 0
                            rightPadding: index === 0 ? 0 : Math.round(6 * Theme.scale)
                            horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                            text: modelData.title + (an.sortKey === modelData.key ? (an.sortDesc ? " ▼" : " ▲") : "")
                            color: an.sortKey === modelData.key ? Theme.text : Theme.dim
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: an.sortBy(parent.modelData.key)
                            }
                        }
                    }
                }

                ListView {
                    visible: count > 0
                    width: an.tableW
                    height: Math.min(contentHeight, Math.round(520 * Theme.scale))
                    clip: true
                    spacing: Math.round(2 * Theme.scale)
                    boundsBehavior: Flickable.StopAtBounds
                    model: an.rows
                    delegate: Rectangle {
                        id: line
                        required property var modelData
                        readonly property bool picked: an.sel !== null && an.sel.key === modelData.key
                        width: an.tableW
                        height: Theme.rowHeight
                        radius: 4
                        color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Theme.rowBg
                        border.color: picked ? Theme.accent : modelData.isMe ? Qt.rgba(1, 1, 1, 0.35) : "transparent"
                        border.width: 1

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            Row {
                                width: an.labelW
                                leftPadding: Math.round(6 * Theme.scale)
                                spacing: Math.round(6 * Theme.scale)
                                Image {
                                    id: icon
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: line.modelData.jobKey !== ""
                                    width: Math.round(16 * Theme.scale)
                                    height: width
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    source: line.modelData.jobKey ? Qt.resolvedUrl("icons/" + line.modelData.jobKey + ".png") : ""
                                }
                                Text {
                                    width: an.labelW - Math.round(6 * Theme.scale) - (icon.visible ? icon.width + Math.round(6 * Theme.scale) : 0)
                                    text: line.modelData.label
                                    color: line.modelData.jobKey && an.group !== "boss" ? Theme.jobColor(line.modelData.jobKey) : Theme.text
                                    font.pixelSize: Theme.fontNormal
                                    font.family: Theme.fontFamily
                                    font.bold: line.modelData.isMe
                                    elide: Text.ElideRight
                                }
                            }
                            Repeater {
                                model: an.columns
                                Text {
                                    required property var modelData
                                    readonly property var value: line.modelData[modelData.key]
                                    width: Math.round((modelData.w || 1) * an.colW)
                                    rightPadding: Math.round(6 * Theme.scale)
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.fmt(value)
                                    color: modelData.color ? modelData.color(value) : modelData.main ? Theme.text : Theme.dim
                                    font.pixelSize: modelData.main ? Theme.fontNormal : Theme.fontSmall
                                    font.family: Theme.fontFamily
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: an.selectedKey = line.modelData.key
                        }
                    }
                }
                Text {
                    visible: an.rows.length === 0
                    text: an.client.history.length === 0 ? "No saved fights yet. Boss fights are saved when they end." : "No runs match these filters."
                    color: Theme.faint
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
            }

            // ── the picked row ──
            Rectangle {
                width: an.paneW
                height: pane.implicitHeight + Theme.pad * 2
                radius: 4
                color: Theme.rowBg
                visible: an.sel !== null

                Column {
                    id: pane
                    x: Theme.pad
                    y: Theme.pad
                    width: an.paneW - Theme.pad * 2
                    spacing: Math.round(4 * Theme.scale)
                    readonly property var s: an.sel

                    Text {
                        width: parent.width
                        text: !pane.s ? "" : (pane.s.isMe ? "★ " : "") + pane.s.label + (an.group === "player" ? "  ·  " + pane.s.job : "")
                        color: pane.s && pane.s.jobKey && an.group !== "boss" ? Theme.jobColor(pane.s.jobKey) : Theme.text
                        font.pixelSize: Theme.fontLarge
                        font.family: Theme.fontFamily
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: !pane.s ? "" : an.group === "run"
                            ? new Date(pane.s.start).toLocaleString(Qt.locale(), "ddd d MMM, HH:mm") + "  ·  " + Theme.duration(pane.s.durationMs) + (pane.s.killed ? "  ·  killed" : "")
                            : pane.s.count + " runs  ·  avg " + Theme.compact(pane.s.avgDps) + "/s  ·  best " + Theme.compact(pane.s.bestDps) + "/s"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        font.features: { "tnum": 1 }
                    }

                    // DPS per run, oldest to newest.
                    Item { width: 1; height: Math.round(4 * Theme.scale); visible: spark.visible }
                    Text {
                        visible: spark.visible
                        text: an.hoverRun
                            ? an.hoverRun.boss + "  ·  " + an.hoverRun.player + "  ·  " + an.date(an.hoverRun.start) + "  ·  " + Theme.compact(an.hoverRun.dps) + "/s"
                            : "DPS per run" + (pane.s && pane.s.runs.length > 40 ? ", last 40" : "")
                        color: an.hoverRun ? Theme.text : Theme.faint
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        font.features: { "tnum": 1 }
                        width: parent.width
                        elide: Text.ElideRight
                    }
                    Row {
                        id: spark
                        visible: an.group !== "run" && pane.s !== null
                        readonly property var bars: pane.s ? pane.s.runs.slice(-40) : []
                        readonly property real peak: Math.max(1, ...bars.map(r => r.dps))
                        height: Math.round(56 * Theme.scale)
                        spacing: Math.max(1, Math.round(2 * Theme.scale))
                        Repeater {
                            model: spark.bars
                            Item {
                                required property var modelData
                                width: Math.min(Math.round(14 * Theme.scale), (pane.width - spark.spacing * (spark.bars.length - 1)) / spark.bars.length)
                                height: spark.height
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * parent.modelData.dps / spark.peak)
                                    radius: Math.min(2, width / 2)
                                    color: an.hoverRun === parent.modelData ? Theme.accent
                                        : Qt.alpha(an.group === "boss" ? Theme.accent : Theme.jobColor(parent.modelData.jobKey), parent.modelData.killed ? 0.75 : 0.35)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: an.hoverRun = parent.modelData
                                    onExited: if (an.hoverRun === parent.modelData) an.hoverRun = null
                                    onClicked: an.openFight(parent.modelData.fightId)
                                }
                            }
                        }
                    }

                    // Best run per boss (or per player).
                    Item { width: 1; height: Math.round(4 * Theme.scale); visible: bests.count > 0 }
                    Text {
                        visible: bests.count > 0
                        text: "Best by " + an.groupNames[an.other].toLowerCase()
                        color: Theme.faint
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                    }
                    Repeater {
                        id: bests
                        model: {
                            if (!pane.s || an.group === "run") return [];
                            const best = {};
                            for (const r of pane.s.runs) {
                                const k = an.keyOf(r, an.other);
                                if (!best[k] || r.dps > best[k].dps) best[k] = r;
                            }
                            return Object.values(best).sort((a, b) => b.dps - a.dps).slice(0, 8);
                        }
                        Rectangle {
                            id: best
                            required property var modelData
                            width: pane.width
                            height: Math.round(20 * Theme.scale)
                            radius: 3
                            color: bestArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Math.round(4 * Theme.scale)
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.5
                                text: an.other === "boss" ? best.modelData.boss : best.modelData.player
                                color: an.other === "player" ? Theme.jobColor(best.modelData.jobKey) : Theme.text
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.fontFamily
                                font.bold: an.other === "player" && best.modelData.isMe
                                elide: Text.ElideRight
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: Math.round(4 * Theme.scale)
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.compact(best.modelData.dps) + "/s   " + an.date(best.modelData.start) + "  ›"
                                color: Theme.dim
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.fontFamily
                                font.features: { "tnum": 1 }
                            }
                            MouseArea {
                                id: bestArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: an.setFilter(an.other, an.keyOf(best.modelData, an.other))
                            }
                        }
                    }

                    Item { width: 1; height: Math.round(4 * Theme.scale) }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        lineHeight: 1.2
                        text: {
                            const s = pane.s;
                            if (!s) return "";
                            const per = an.group === "run" ? "" : " per run";
                            const lines = [
                                "Crit " + Theme.percent(s.critRate, 0) + "  ·  back " + Theme.percent(s.backRate, 0) + "  ·  share " + Theme.percent(s.share, 0),
                                (s.healPs > 0 ? "Heal " + Theme.compact(s.healPs) + "/s  ·  " : "") + "taken " + Theme.compact(s.takenPs) + "/s",
                                (an.group === "run" ? s.deaths : s.deaths.toFixed(1)) + " deaths" + per + (an.group === "run" ? "" : "  ·  " + Theme.percent(s.killRate, 0) + " kills")
                            ];
                            // The newest gear: it changes over time.
                            const geared = s.runs.filter(r => r.gearScore > 0);
                            if ((an.group === "player" || an.group === "run") && geared.length) {
                                const g = geared[geared.length - 1];
                                lines.push("Gear score " + g.gearScore + "  ·  CP " + Theme.compact(g.combatPower));
                            }
                            return lines.join("\n");
                        }
                        color: Theme.dim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        font.features: { "tnum": 1 }
                    }

                    Item { width: 1; height: Math.round(4 * Theme.scale) }
                    Chip {
                        visible: an.group === "run"
                        label: "Open fight ›"
                        onClicked: an.openFight(pane.s.runs[0].fightId)
                    }
                    Chip {
                        visible: an.group !== "run"
                        label: "Only this " + an.groupNames[an.group].toLowerCase() + " ›"
                        // Narrow to it and break it down by the other side.
                        onClicked: {
                            const g = an.group, key = pane.s.key;
                            an.setFilter(g, key);
                            an.setGroup(g === "boss" || g === "job" ? "player" : "boss");
                        }
                    }
                }
            }
        }
    }
}
