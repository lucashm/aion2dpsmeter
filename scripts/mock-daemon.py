#!/usr/bin/env python3
"""A stand-in for aion2-meterd that serves a made-up fight, for working on the
overlay without the game: python3 scripts/mock-daemon.py [socket-path]"""

import json
import math
import os
import random
import socket
import sys
import threading
import time

PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "aion2-meter.sock")

PLAYERS = [
    (101, "Gran", "SORCERER", "Sorcerer", 1.00),
    (102, "Edmundo", "GLADIATOR", "Gladiator", 0.92),
    (103, "Kaisinel", "ASSASSIN", "Assassin", 0.88),
    (104, "Lumiel", "RANGER", "Ranger", 0.80),
    (105, "Yustiel", "CHANTER", "Chanter", 0.45),
    (106, "Ariel", "CLERIC", "Cleric", 0.22),
]
SKILLS = ["Flame Bolt", "Ice Chain", "Blaze", "Wind Spear", "Inferno", "Frost Nova", "Summon Fire Spirit", "Erosion", "Delayed Blast", "Arcane Thunderbolt"]
LOCAL = 101
clients = []
lock = threading.Lock()
focus = {"id": None}
start = time.time()
MAX_HP = 48_000_000
history = []


def state():
    t = time.time() - start
    elapsed_ms = int(t * 1000)
    players, total = [], 0
    for pid, name, key, job, mult in PLAYERS:
        dps = 41_000 * mult * (1 + 0.08 * math.sin(t / 3 + pid))
        dmg = dps * max(t, 1)
        total += dmg
        players.append({"id": pid, "name": name, "job": job, "jobKey": key, "dps": dps, "damage": dmg,
                        "share": 0, "critRate": 0.35 + 0.1 * math.sin(pid), "isLocal": pid == LOCAL})
    for p in players:
        p["share"] = p["damage"] / total * 100
    players.sort(key=lambda p: -p["damage"])
    who = focus["id"] or LOCAL
    me = next(p for p in players if p["id"] == who)
    weights = [1 / (i + 1.3) for i in range(len(SKILLS))]
    wsum = sum(weights)
    skills = [{"code": 1000 + i, "name": n, "damage": int(me["damage"] * w / wsum), "hits": int(t * w * 3) + 1,
               "share": w / wsum, "dps": me["dps"] * w / wsum, "critRate": 0.3 + (i % 3) * 0.1,
               "backRate": 0.15 * (i % 2), "isDot": n == "Erosion"} for i, (n, w) in enumerate(zip(SKILLS, weights))]
    hp = max(0, MAX_HP - total)
    return {"type": "state",
            "capture": {"gameRunning": True, "locked": True, "error": None},
            "pingMs": int(48 + 10 * math.sin(t)), "targetMode": "bossTargets",
            "target": {"id": 9001, "name": "Guardian General Kromede", "isBoss": True, "maxHp": MAX_HP, "currentHp": int(hp), "damageTaken": int(total)},
            "battleTimeMs": elapsed_ms, "players": players, "skillsOf": who, "skills": skills}


def send_all(msg):
    line = (json.dumps(msg) + "\n").encode()
    with lock:
        for c in list(clients):
            try:
                c.sendall(line)
            except OSError:
                clients.remove(c)


def reader(conn):
    for line in conn.makefile():
        try:
            cmd = json.loads(line)
        except ValueError:
            continue
        print("command:", cmd, flush=True)
        if cmd.get("cmd") == "focus":
            focus["id"] = cmd.get("id")
        elif cmd.get("cmd") == "reset":
            global start
            start = time.time()
        elif cmd.get("cmd") == "history":
            send_all({"type": "history", "fights": history})
        elif cmd.get("cmd") == "fight":
            f = next((h for h in history if h["id"] == cmd.get("id")), None)
            if f:
                send_all({"type": "fight", "summary": f, "skills": []})


def main():
    for i in range(4):
        players = [{"id": pid, "name": n, "job": j, "jobKey": k, "damage": int(9e6 * m), "dps": 40_000 * m} for pid, n, k, j, m in PLAYERS]
        history.append({"id": f"mock-{i}", "bossName": ["Kromede", "Taloc", "Padmarashka", "Beritra"][i],
                        "startTimeMs": int((time.time() - 3600 * (i + 1)) * 1000), "durationMs": 140_000 + 20_000 * i,
                        "totalDamage": sum(p["damage"] for p in players), "killed": i != 2, "players": players})
    try:
        os.unlink(PATH)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(PATH)
    srv.listen()
    print("mock daemon on", PATH, flush=True)
    threading.Thread(target=lambda: [send_all(state()) or time.sleep(0.2) for _ in iter(int, 1)], daemon=True).start()
    while True:
        conn, _ = srv.accept()
        with lock:
            clients.append(conn)
        threading.Thread(target=reader, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
