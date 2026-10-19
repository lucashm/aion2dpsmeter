// Checks the hourly event reminders (overlay/EventAlert.qml): each shows the
// lead time before :00 / :30 UTC and goes a minute after it starts.
// node scripts/test-event-alert.js
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../overlay/EventAlert.qml", "utf8");
const fn = (name) => src.match(new RegExp(`    function ${name}\\([^]*?\\n    }\\n`))[0];
const alerts = {
    events: eval(src.match(/readonly property var events: (\[[^]*?\n    \])/)[1]),
    sample: null, now: 0, gameRunning: true,
    settings: { notifyShugo: true, notifyInvasion: true, eventLead: 3 },
};
const { upcoming, countdown } = new Function("alerts", `with (alerts) { ${fn("upcoming")}\n${fn("countdown")}\nreturn { upcoming, countdown }; }`)(alerts);
const eq = (got, want, what) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
        console.error(`FAIL ${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
        process.exitCode = 1;
    }
};
const at = (hms) => Date.parse(`2026-10-18T${hms}Z`);
const names = (t) => upcoming(t).map((a) => a.name);

eq(names(at("14:50:00")), [], "nothing due at :50");
eq(names(at("14:57:00")), ["Shugo Festival"], "3 min before :00");
eq(names(at("15:00:59")), ["Shugo Festival"], "still up just after it starts");
eq(names(at("15:01:00")), [], "gone a minute after");
eq(names(at("15:27:30")), ["Dimensional Invasion"], "before :30");
alerts.now = at("15:27:30");
eq(countdown(upcoming(at("15:27:30"))[0]), "Starts in 2:30", "the countdown");
alerts.settings.notifyInvasion = false;
eq(names(at("15:27:30")), [], "turned off");
alerts.settings.eventLead = 10;
eq(names(at("15:51:00")), ["Shugo Festival"], "a longer lead time");
alerts.sample = { id: "shugo", start: at("15:10:10") };
eq(upcoming(at("15:10:00")).map((a) => a.key), ["sample"], "a test reminder");
alerts.settings.notifyInvasion = true;
alerts.gameRunning = false;
eq(names(at("15:27:30")), [], "game closed: no reminders");
alerts.sample = { id: "shugo", start: at("15:27:40") };
eq(names(at("15:27:30")), ["Shugo Festival"], "game closed: a test still shows");
alerts.gameRunning = true;
alerts.sample = null;
if (!process.exitCode) console.log("event alert: ok");
