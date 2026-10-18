// Checks the app's Pets page counts (overlay/PetsPage.qml) on the real pet data:
// node scripts/test-pets-page.js
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../overlay/PetsPage.qml", "utf8");
const fn = (name) => src.match(new RegExp(`    function ${name}\\([^]*?\\n    }\\n`))[0];
const pets = JSON.parse(fs.readFileSync(__dirname + "/../overlay/data/pets.json", "utf8")).pets;
const needed = [5, 25, 75];
const PetData = {
    pets, needed, maxLevel: 3,
    sideMaps: { elyos: ["Poeta", "Verteron", "Eltnen"], asmodian: ["Ishalgen", "Altgard", "Morheim"] },
    collectionRewards: [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200]
        .map((at) => ({ at, reward: at % 50 === 0 ? "10 empathy candy" : "100 soul crystals" })),
};
const { petsModel } = new Function("PetData", `${fn("areaOf")}\n${fn("petsModel")}\nreturn { petsModel };`)(PetData);
const eq = (got, want, what) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
        console.error(`FAIL ${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
        process.exitCode = 1;
    }
};
const opts = (o) => Object.assign({ phase: "1", genus: ["cogni"], farmIn: ["elyos", "asmodian", "abyss"], search: "", sort: "closest" }, o);
const cogni = Object.keys(pets).filter((id) => pets[id].genus === "cogni");

// Every Cogni pet collected but Krall Laborer (4 souls of 5): phase 1, one pet needed.
const levels = {}, points = { 1002: 4 };
for (const id of cogni) if (id !== "1002") levels[id] = 1;
let m = petsModel(pets, levels, points, [], opts({}));
eq(m.phase, 1, "the phase picked");
eq(m.needed.map((p) => [p.name, p.toPhase]), [["Krall Laborer", 1]], "the pet needed and its souls");
eq(m.soulsNeeded, 1, "souls needed for the phase");
eq(m.phaseCounts[1], m.farmable - 1, "pets done for the phase");
eq(m.needed[0].drop.npc + " " + m.needed[0].drop.region, "Krall Armed Soldier Verteron", "the easiest monster where you farm");
eq(m.genus.cogni.collected, cogni.length - 1, "genus collected");
eq(m.genus.cogni.total, 41, "genus total");
eq(m.notFarmed.some((p) => p.genus === "fera"), true, "genuses you don't farm are not farmed");
eq(m.notFarmed.some((p) => p.genus === "special"), true, "special pets are not farmed");
eq(m.nextReward.at > m.collected, true, "the next reward is ahead");

// Collected: phase 2 next, with 25 souls each.
levels[1002] = 1;
m = petsModel(pets, levels, {}, [], opts({ phase: "2" }));
eq([m.phase, m.soulsNeeded], [2, 25 * m.farmable], "level 2 needs 25 souls each from level 1");
eq(petsModel(pets, levels, {}, [], opts({})).needed.length, 0, "every pet collected: nothing needed for level 1");
eq(petsModel(pets, levels, {}, [], opts({ phase: "auto" })).phase, 3, "an old auto setting is level 3");

// Areas: farming only the Abyss leaves Krall Laborer (Verteron) not farmed.
m = petsModel(pets, {}, {}, [], opts({ farmIn: ["abyss"] }));
eq(m.needed.some((p) => p.name === "Krall Laborer"), false, "pets outside your areas aren't needed");

// Search, sort, estimated levels.
m = petsModel(pets, {}, { 1002: 4 }, [1002], opts({ search: "krall armed" }));
eq(m.needed.map((p) => p.name), ["Krall Laborer"], "search finds a pet by its monster");
eq(m.needed[0].estimated, true, "estimated levels are marked");
m = petsModel(pets, {}, {}, [], opts({ sort: "name" }));
eq(m.needed.map((p) => p.name).join() === m.needed.map((p) => p.name).sort((a, b) => a.localeCompare(b)).join(), true, "sorted by name");
// Closest to done is closest to level 3: a level 2 pet comes before a level 0 pet with 4 of 5 souls.
m = petsModel(pets, { 1003: 2 }, { 1002: 4 }, [], opts({ phase: "3", genus: ["cogni", "natura"] }));
eq(m.needed[0].name, "Forest Specter", "closest to done means closest to level 3");
if (!process.exitCode) console.log("pets page: ok");
