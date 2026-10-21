// Checks the hidden cube banner (overlay/CubeAlert.qml): a cube in range stays
// up with a live distance and goes when it's opened or out of range.
// node scripts/test-cube-alert.js
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../overlay/CubeAlert.qml", "utf8");
const fn = (name) => src.match(new RegExp(`    function ${name}\\([^]*?\\n    }\\n`))[0];
const played = [];
const alerts = {
    shown: [], count: 0, now: 0,
    settings: { notifyCubes: true, cubesNeedKey: true, cubeSound: true },
    Quickshell: { execDetached: (cmd) => played.push(cmd), shellDir: "/x" },
};
const { push, nearNote } = new Function("alerts", `with (alerts) { ${fn("nearNote")}\n${fn("push")}\nreturn { push, nearNote }; }`)(alerts);
const eq = (got, want, what) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
        console.error(`FAIL ${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
        process.exitCode = 1;
    }
};
const note = () => alerts.shown.filter((a) => a.cube === 7).map((a) => nearNote(Object.assign({}, a, { at: alerts.now })))[0];

push({ event: "near", id: 7, distance: 64, keys: 41 });
eq(note(), "About 64 m away  ·  41 keys", "a cube in range");
eq(played.length, 1, "the chime plays");
push({ event: "distance", id: 7, distance: 20 });
eq(note(), "About 20 m away  ·  41 keys", "its distance follows you");
push({ event: "opening", id: 7, by: "Rival", mine: false });
eq(alerts.shown.map((a) => a.title), ["Rival is opening a hidden cube", "Hidden cube nearby"], "someone opening it shows too");
push({ event: "opening", id: 7, by: null, mine: false });
eq(alerts.shown[0].title, "A hidden cube is being opened", "an opener with no name isn't called someone else");
push({ event: "opened", id: 7, mine: true });
eq(alerts.shown.some((a) => a.cube === 7), false, "opened: its banner goes");
push({ event: "near", id: 8, distance: null, keys: null });
push({ event: "left", id: 8 });
eq(alerts.shown.some((a) => a.cube === 8), false, "out of range: its banner goes");
push({ event: "near", id: 9, keys: 0 });
eq(alerts.shown.some((a) => a.cube === 9), false, "no keys: no alert");
alerts.settings.hideWidgets = true;
push({ event: "near", id: 10, distance: 30, keys: 5 });
eq(alerts.shown.some((a) => a.cube === 10), true, "widgets hidden: still alerts");
alerts.settings.hideWidgets = false;
if (!process.exitCode) console.log("cube alert: ok");
