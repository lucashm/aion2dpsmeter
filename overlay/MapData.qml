pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The pet map's data from Arkive (github.com/arkive-games/arkive, by tc-imba,
// CC BY-NC 4.0), downloaded by fetch-map.sh into the data folder: each map's
// pet spawn clusters by pet name, and the pets' portraits. The Abyss has no
// spawn points there, so its pets go to the middle of the zones they drop in.
Singleton {
    id: mapData

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/aion2-meter/map"
    readonly property string resources: "https://resource-aion2.tc-imba.com/"
    // The maps: tiles of 1024 px per side, the coarsest tile level there is
    // (2 = quarter size), and the region name the pet data uses for it.
    readonly property var maps: [
        { id: "World_L_A", name: "Verteron", region: "Verteron", tiles: 8, levels: 2 },
        { id: "World_D_A", name: "Altgard", region: "Altgard", tiles: 8, levels: 2 },
        { id: "Abyss_Reshanta_A", name: "Abyss", region: "Chaotic Lower Reshanta", tiles: 4, levels: 1 }
    ]
    readonly property int tileSize: 1024
    function mapOf(id) {
        return maps.find(m => m.id === id) || maps[0];
    }

    // "idle" until asked, "fetching", "ready" or "failed".
    property string status: "idle"
    // Pet name -> [{ map, x, y, count }]: spawn clusters in map pixels.
    property var spawns: ({})
    // Pet name -> portrait file URL.
    property var portraits: ({})

    // Download (or check) the data, then read it. Cheap when it's current.
    function fetch() {
        if (status === "fetching") return;
        status = "fetching";
        fetcher.running = true;
    }

    // A tile's URL: quarter and half size are downloaded; full size loads from Arkive.
    function tileUrl(map, level, x, y) {
        const name = map + "_" + String(x).padStart(2, "0") + "_" + String(y).padStart(2, "0") + ".webp";
        const path = "UI/Map/WorldMap/" + map + "/Res/" + (level > 0 ? "z-" + level + "/" : "") + name;
        return level > 0 ? "file://" + dir + "/" + path : resources + path;
    }

    // A polygon's centre (its area centroid), from Arkive's region borders.
    function centre(ring) {
        let a = 0, cx = 0, cy = 0;
        for (let i = 0; i < ring.length - 1; i++) {
            const [x0, y0] = ring[i], [x1, y1] = ring[i + 1];
            const f = x0 * y1 - x1 * y0;
            a += f;
            cx += (x0 + x1) * f;
            cy += (y0 + y1) * f;
        }
        return a ? { x: cx / (3 * a), y: cy / (3 * a) } : { x: ring[0][0], y: ring[0][1] };
    }

    function read() {
        const spawns = {};
        const portraits = {};
        const add = (n, s) => (spawns[n] || (spawns[n] = [])).push(s);
        for (let i = 0; i < files.count; i++) {
            const f = files.objectAt(i);
            if (!f || !f.markers || !f.names) continue;
            let creatures = 0;
            for (const m of f.markers) {
                if (m.category !== "creature") continue;
                const n = f.names[m.id] && f.names[m.id].name;
                if (!n) continue;
                creatures++;
                add(n, { map: f.map, x: m.x, y: m.y, count: m.count || 1 });
                if (m.icon && !portraits[n]) portraits[n] = "file://" + dir + "/" + m.icon;
            }
            if (creatures || !f.regions || !f.regionNames) continue;
            // No spawn points: each pet at the middle of each zone its monsters
            // are in, the pets sharing a zone spread in a ring around it.
            const zones = {};
            for (const r of f.regions) {
                const name = f.regionNames[r.name] && f.regionNames[r.name].name;
                if (name && r.borders && r.borders[0]) zones[name] = centre(r.borders[0]);
            }
            const region = mapOf(f.map).region;
            const inZone = {};
            for (const id in PetData.pets) {
                const p = PetData.pets[id];
                for (const d of p.drops) {
                    if (d.region !== region) continue;
                    for (const z of d.zones) {
                        if (!zones[z]) continue;
                        const here = inZone[z] || (inZone[z] = {});
                        here[p.name] = (here[p.name] || 0) + Math.max(1, Math.round((d.spawns || 1) / d.zones.length));
                    }
                }
            }
            for (const z in inZone) {
                const names = Object.keys(inZone[z]).sort();
                const r = names.length > 1 ? 40 * Math.sqrt(names.length) : 0;
                names.forEach((n, k) => {
                    const a = 2 * Math.PI * k / names.length;
                    add(n, { map: f.map, x: zones[z].x + r * Math.cos(a), y: zones[z].y + r * Math.sin(a), count: inZone[z][n], zone: z });
                });
            }
        }
        mapData.spawns = spawns;
        mapData.portraits = portraits;
    }
    // The zone dots come from the pet data, which may load after the maps.
    Connections {
        target: PetData
        function onPetsChanged() { mapData.read(); }
    }

    Process {
        id: fetcher
        command: [Quickshell.shellDir + "/fetch-map.sh", mapData.dir]
        onExited: code => {
            for (let i = 0; i < files.count; i++) files.objectAt(i).reload();
            mapData.status = code === 0 ? "ready" : "failed";
        }
    }

    // Each map's markers and their English names; read whenever they load.
    Instantiator {
        id: files
        model: mapData.maps
        delegate: QtObject {
            id: entry
            required property var modelData
            readonly property string map: modelData.id
            property var markers: null
            property var names: null
            property var regions: null
            property var regionNames: null
            function reload() {
                markerFile.reload();
                nameFile.reload();
                regionFile.reload();
                regionNameFile.reload();
            }
            readonly property FileView markerFile: FileView {
                path: mapData.dir + "/markers/" + modelData.id + ".json"
                onLoaded: {
                    try { entry.markers = JSON.parse(text()).markers; } catch (e) {}
                    mapData.read();
                }
            }
            readonly property FileView nameFile: FileView {
                path: mapData.dir + "/names/" + modelData.id + ".json"
                onLoaded: {
                    try { entry.names = JSON.parse(text()); } catch (e) {}
                    mapData.read();
                }
            }
            readonly property FileView regionFile: FileView {
                path: mapData.dir + "/regions/" + modelData.id + ".json"
                onLoaded: {
                    try { entry.regions = JSON.parse(text()).regions; } catch (e) {}
                    mapData.read();
                }
            }
            readonly property FileView regionNameFile: FileView {
                path: mapData.dir + "/region-names/" + modelData.id + ".json"
                onLoaded: {
                    try { entry.regionNames = JSON.parse(text()); } catch (e) {}
                    mapData.read();
                }
            }
        }
    }
}
