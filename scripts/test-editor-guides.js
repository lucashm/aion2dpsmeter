// Checks edit mode's alignment guides (overlay/EditorLayer.qml) by running its
// functions on a fake 2560x1440 screen: node scripts/test-editor-guides.js
const src = require("fs").readFileSync(__dirname + "/../overlay/EditorLayer.qml", "utf8");
const fn = (name) => src.match(new RegExp(`    function ${name}\\([^]*?\\n    }\\n`))[0];
const build = new Function("ctx", `with (ctx) { ${["snap", "alignLines", "placeAxis", "place"].map(fn).join("\n")}
  return { place, placeAxis }; }`);

const other = { visible: true, posX: 100, posY: 200, implicitWidth: 300, implicitHeight: 100 };
const me = { visible: true, implicitWidth: 200, implicitHeight: 50 };
const SHIFT = 0x02000000;
const ctx = {
    width: 2560, height: 1440, widgets: [other, me],
    settings: { gridSize: 16, snapToGrid: true }, guidesX: [], guidesY: [],
    Qt: { ShiftModifier: SHIFT, point: (x, y) => ({ x, y }) },
};
const e = build(ctx);
const eq = (got, want, what) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
        console.error(`FAIL ${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
        process.exitCode = 1;
    }
};
eq(e.placeAxis(me, 1280 - 100 + 4, true), [1180, [1280]], "centres on the screen centre");
eq(e.placeAxis(me, 105, true), [100, [100]], "aligns with another widget's left edge");
eq(e.placeAxis(me, 707, true)[0], 704, "falls back to the grid");
const p = e.place(me, 707, 333, SHIFT);
eq([p.x, p.y, ctx.guidesX.length], [707, 333, 0], "Shift places freely");
if (!process.exitCode) console.log("editor guides: ok");
