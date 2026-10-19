#!/usr/bin/env python3
"""Check native widget sizes through zoom changes and HWND recreation on Windows.

Requires the built desktop executable, but no game, Npcap or third-party Python
packages. Only the test's overlay child and isolated preferences are used.
"""
import argparse
from collections import deque
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time


SIZES = {"meter": (360, 220), "boss": (400, 86), "ping": (120, 48), "alert": (360, 80)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("target/debug/aion2-meter-windows.exe"))
    options = parser.parse_args()
    if os.name != "nt":
        parser.error("This integration check requires Windows")
    executable = options.app.resolve(strict=True)
    user32 = ctypes.windll.user32
    user32.SetProcessDpiAwarenessContext.argtypes = [ctypes.c_void_p]
    user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user32.GetDpiForWindow.argtypes = [wintypes.HWND]
    user32.GetDpiForWindow.restype = wintypes.UINT

    with tempfile.TemporaryDirectory(prefix="daevalog-scale-") as directory:
        env = dict(os.environ, LOCALAPPDATA=directory, APPDATA=directory,
                   AION2_COMPANION_SMOKE_REPORT=str(Path(directory) / "unused.json"))
        process = subprocess.Popen([str(executable), "--overlay-stdio"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, encoding="utf-8", env=env, creationflags=0x08000000)
        logs = deque(maxlen=32)

        def read(pipe):
            for line in pipe:
                logs.append(line.rstrip())

        readers = [threading.Thread(target=read, args=(pipe,), daemon=True)
                   for pipe in (process.stdout, process.stderr)]
        for reader in readers:
            reader.start()

        def windows():
            found = {}

            @callback_type
            def visit(hwnd, _):
                pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                if pid.value == process.pid and user32.IsWindowVisible(hwnd):
                    title = ctypes.create_unicode_buffer(128)
                    user32.GetWindowTextW(hwnd, title, len(title))
                    if title.value.startswith("Daevalog · "):
                        name = title.value.removeprefix("Daevalog · ")
                        rect = wintypes.RECT()
                        user32.GetClientRect(hwnd, ctypes.byref(rect))
                        found[name] = (rect.right - rect.left, rect.bottom - rect.top,
                                       user32.GetDpiForWindow(hwnd))
                return True

            user32.EnumWindows(visit, 0)
            return found

        preferences = {"scale": 100, "opacity": 90, "overlayVisible": True,
                       "widgets": [{"id": name, "enabled": True, "x": .1, "y": .1} for name in SIZES]}

        def send():
            process.stdin.write(json.dumps({"state": {}, "preferences": preferences, "locked": False}) + "\n")
            process.stdin.flush()

        def wait_for_geometry(enabled):
            deadline, stable = time.monotonic() + 8, 0
            while time.monotonic() < deadline:
                actual = windows()
                matches = set(actual) == set(enabled)
                for name, (width, height, dpi) in actual.items():
                    if name not in SIZES or not dpi:
                        matches = False
                        continue
                    expected = [round(size * preferences["scale"] / 100 * dpi / 96) for size in SIZES[name]]
                    matches &= abs(width - expected[0]) <= 1 and abs(height - expected[1]) <= 1
                stable = stable + 1 if matches else 0
                if stable >= 4:
                    return actual
                if process.poll() is not None:
                    raise AssertionError(f"Overlay exited early: {list(logs)}")
                time.sleep(.05)
            raise AssertionError(f"Wrong geometry at {preferences['scale']}%: {windows()}; {list(logs)}")

        try:
            for scale in (100, 150, 75, 100):
                preferences["scale"] = scale
                send()
                before = wait_for_geometry(SIZES)
                preferences["widgets"][0]["enabled"] = False
                send()
                wait_for_geometry(set(SIZES) - {"meter"})
                preferences["widgets"][0]["enabled"] = True
                send()
                after = wait_for_geometry(SIZES)
                assert after == before, (scale, before, after)
                print(f"PASS: {scale}% widget sizes stay correct through recreation: {after['meter'][:2]}")
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            for reader in readers:
                reader.join(timeout=1)
            process.stdout.close()
            process.stderr.close()


if __name__ == "__main__":
    main()
