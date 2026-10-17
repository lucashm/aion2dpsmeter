import QtQuick

// The focused player's skills (yours unless you picked someone in the meter):
// damage share, DPS, hits, crit and back-attack rates.
OverlayWidget {
    id: skills

    required property var client
    title: "Skills"

    readonly property int width_: Math.round(360 * Theme.scale)
    readonly property var rows: client.skills.slice(0, settings.skillRows)
    readonly property var owner: {
        const s = client.state;
        if (!s || s.skillsOf === null) return null;
        return client.players.find(p => p.id === s.skillsOf) || null;
    }

    Panel {
        width: skills.width_

        SkillTable {
            width: skills.width_ - Theme.pad * 2
            rows: skills.rows
            title: skills.owner ? skills.owner.name + (skills.owner.job ? "  ·  " + skills.owner.job : "") : "Skills"
            titleColor: skills.owner ? Theme.jobColor(skills.owner.jobKey) : Theme.text
            barColor: skills.owner ? Theme.jobColor(skills.owner.jobKey) : Theme.accent
        }
    }
}
