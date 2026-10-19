#!/usr/bin/env python3
"""Real daemon smoke checks, with synthetic TCP/pcap data and isolated storage.

Requires Npcap on Windows or libpcap on Linux. No driver install, elevation,
game, real traffic, credentials, or third-party Python packages are needed.
Also runs against Linux's Unix socket to compare the existing engine.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import socket
import struct
import subprocess
import tempfile
import threading
import time


def game_frame(opcode, body):
    # A2Tools framing: physical frame size = length-varint - 3.
    return bytes([len(body) + 6, *opcode]) + body


def write_capture(path):
    seq = 1
    with path.open("wb") as out:
        out.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for i in range(16):
            # Known damage record used by A2Tools' additional-hits regression:
            # target 30001, actor 1395, damage 1700, two additional hits of 24.
            record = bytes.fromhex("b1ea013600f30a40c0f4007a038000010b199b5f01000000ac52a40d021818")
            data = game_frame((0x04, 0x38), record)
            data += game_frame((0x00, 0x36), bytes(8))
            if i == 14:
                data += game_frame((0x0D, 0x90), struct.pack("<BII", 1, 1002, 7))
            ethernet = bytes(12) + b"\x08\x00"
            ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 40 + len(data), i, 0x4000, 64, 6, 0,
                             socket.inet_aton("192.0.2.1"), socket.inet_aton("192.0.2.2"))
            tcp = struct.pack("!HHIIBBHHH", 13328, 50000, seq, 1, 0x50, 0x18, 65535, 0, 0)
            frame = ethernet + ip + tcp + data
            # Contemporary epoch seconds catch Windows' 32-bit timeval overflow.
            out.write(struct.pack("<IIII", 1_790_000_000 + i // 10, i % 10 * 100000, len(frame), len(frame)))
            out.write(frame)
            seq += len(data)


class Daemon:
    def __init__(self, executable, root, source):
        self.windows = os.name == "nt"
        self.messages = queue.Queue()
        self.events = []
        self.root = root
        env = dict(os.environ, LOCALAPPDATA=str(root), XDG_DATA_HOME=str(root))
        args = [str(executable)]
        endpoint = root / "meter.sock"
        args += ["--stdio"] if self.windows else ["--socket", str(endpoint), "--print"]
        args += source
        self.log = (root / "test.log").open("w+")
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.log, text=True, encoding="utf-8", env=env)
        self.connection = None
        if self.windows:
            reader = self.process.stdout
        else:
            self.connection = socket.socket(socket.AF_UNIX)
            deadline = time.monotonic() + 5
            while True:
                try:
                    self.connection.connect(str(endpoint))
                    break
                except (FileNotFoundError, ConnectionRefusedError):
                    if time.monotonic() >= deadline or self.process.poll() is not None:
                        raise RuntimeError("Unix socket did not start")
                    time.sleep(0.02)
            reader = self.connection.makefile("r", encoding="utf-8")
        self.reader = reader

        def read():
            for line in reader:
                try:
                    self.messages.put(json.loads(line))
                except json.JSONDecodeError:
                    pass
        self.thread = threading.Thread(target=read, daemon=True)
        self.thread.start()

    def send(self, value):
        line = json.dumps(value) + "\n"
        if self.windows:
            self.process.stdin.write(line)
            self.process.stdin.flush()
        else:
            self.connection.sendall(line.encode())

    def wait_for(self, predicate, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                event = self.messages.get(timeout=0.1)
                self.events.append(event)
                if predicate(event):
                    return event
            except queue.Empty:
                pass
        self.log.flush()
        raise AssertionError(f"Expected event missing. Events: {self.events!r}. Log: {(self.root / 'test.log').read_text()}")

    def close(self):
        if self.process.poll() is None:
            if self.windows:
                self.process.stdin.close()  # EOF must save and stop capture too.
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    raise AssertionError("Daemon survived the desktop pipe closing")
            else:
                self.process.terminate()
        self.process.wait(timeout=5)
        if self.connection:
            self.connection.close()
        self.process.stdout.close()
        self.log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=Path, default=Path("target/debug/aion2-meterd.exe" if os.name == "nt" else "target/debug/aion2-meterd"))
    parser.add_argument("--snapshot", type=Path, help="Write deterministic replay results for cross-platform/baseline comparison")
    options = parser.parse_args()
    executable = options.daemon.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="aion2-smoke-") as directory:
        root = Path(directory)
        pcap = root / "synthetic.pcap"
        write_capture(pcap)
        daemon = Daemon(executable, root, ["--pcap", str(pcap), "--realtime"])
        try:
            daemon.send({"cmd": "targetMode", "mode": "allTargets"})
            daemon.send({"cmd": "focus", "id": 1395})
            state = daemon.wait_for(lambda e: e.get("type") == "state" and e["capture"]["locked"] and e["players"])
            assert sum(p["damage"] for p in state["players"]) > 0
            pet = daemon.wait_for(lambda e: e.get("type") == "pets" and e.get("points", {}).get("1002", 0) > 0)
            assert pet["points"]["1002"] == 2 and pet["levels"]["1002"] == 1, pet
            daemon.process.wait(timeout=5)
            assert daemon.process.returncode == 0
            daemon.thread.join(timeout=1)
            while not daemon.messages.empty():
                daemon.events.append(daemon.messages.get_nowait())
            final = [e for e in daemon.events if e.get("type") == "state"][-1]
            assert sum(p["damage"] for p in final["players"]) == 27200, final
            assert sum(s["damage"] for s in final["skills"]) == 27200, final
            if options.snapshot:
                options.snapshot.write_text(json.dumps(final, sort_keys=True, indent=2), encoding="utf-8")
            print("PASS: real pcap replay, signature lock, exact 27,200 damage, pet frames and clean EOF")
        finally:
            daemon.close()

        if os.name == "nt":
            # Invalid adapter stays alive to report its error and receive commands.
            daemon = Daemon(executable, root, ["--iface", "not-an-adapter"])
            try:
                daemon.wait_for(lambda e: e.get("type") == "state" and e["capture"]["error"])
                daemon.send({"cmd": "history", "limit": 2})
                daemon.wait_for(lambda e: e.get("type") == "history")
                daemon.send({"cmd": "reset"})
                daemon.send({"cmd": "shutdown"})
                daemon.process.wait(timeout=5)
                assert daemon.process.returncode == 0
                print("PASS: capture error reporting, history/reset commands and explicit shutdown")
            finally:
                daemon.close()

            daemon = Daemon(executable, root, ["--iface", "not-an-adapter"])
            daemon.close()
            assert daemon.process.returncode == 0
            print("PASS: closing the parent's input pipe stops the capture process")


if __name__ == "__main__":
    main()
