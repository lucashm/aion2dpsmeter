pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Pet names and where their souls drop (data/pets.json, from A2Tools' Pet
// Soul Tracker via scripts/update-pet-data.py), and the souls each level takes.
Singleton {
    id: data

    // Souls a pet needs to go from level N to N + 1; level 3 is the top.
    readonly property var needed: [5, 25, 75]
    readonly property int maxLevel: needed.length
    // id -> { name, genus, drops, chests }
    property var pets: ({})
    // Collection status rewards, by pets collected (wikily.gg/aion-2/genus-insight).
    readonly property var collectionRewards: [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200]
        .map(at => ({ at: at, reward: at % 50 === 0 ? "10 empathy candy" : "100 soul crystals" }))
    // Each side's maps; Reshanta and the dungeons belong to both.
    readonly property var sideMaps: ({ elyos: ["Poeta", "Verteron", "Eltnen"], asmodian: ["Ishalgen", "Altgard", "Morheim"] })

    function name(id) {
        const p = pets[id];
        return p ? p.name : "Pet #" + id;
    }
    // Souls still needed to reach level 3.
    function left(level, points) {
        return Math.max(0, needed.slice(level).reduce((n, x) => n + x, 0) - points);
    }

    FileView {
        path: Quickshell.shellDir + "/data/pets.json"
        onLoaded: {
            try {
                data.pets = JSON.parse(text()).pets;
            } catch (e) {
                console.warn("aion2-meter: bad pets.json", e);
            }
        }
    }
}
