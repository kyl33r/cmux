#!/usr/bin/env python3
"""
Empirical dev-build check: does Cmd+Shift+R open the workspace rename flow?

Connects to the tagged debug socket, focuses the window, then simulates
Cmd+Shift+R (the default renameWorkspace binding) and observes whether the
command palette opens in rename-input mode. Also checks Cmd+R (renameTab).

Note: synthetic shortcut events carry no window number, so the palette only
opens when a key window exists (focus_window + activate_app makes one).
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = "/tmp/cmux-debug-rename-ws-shortcut.sock"


def _wait_until(predicate, timeout_s=4.0, interval_s=0.05, message="timeout"):
    start = time.time()
    while time.time() - start < timeout_s:
        if predicate():
            return True
        time.sleep(interval_s)
    return False


def _palette_visible(client, window_id):
    payload = client._call("debug.command_palette.visible", {"window_id": window_id}) or {}
    return bool(payload.get("visible"))


def _rename_selection(client, window_id):
    return client._call("debug.command_palette.rename_input.selection", {"window_id": window_id}) or {}


def _palette_mode(client, window_id):
    try:
        payload = client._call("debug.command_palette.mode", {"window_id": window_id}) or {}
        return payload
    except cmuxError:
        return {}


def _close_palette(client, window_id):
    if _palette_visible(client, window_id):
        client.simulate_shortcut("cmd+p")
        time.sleep(0.3)


def main():
    with cmux(SOCKET_PATH) as client:
        client.activate_app()
        time.sleep(0.2)

        window_id = client.current_window()
        for row in client.list_windows():
            other_id = str(row.get("id") or "")
            if other_id and other_id != window_id:
                client.close_window(other_id)
        time.sleep(0.2)

        client.focus_window(window_id)
        client.activate_app()
        time.sleep(0.3)

        # Case 1: Cmd+Shift+R should open the workspace rename flow.
        client.simulate_shortcut("cmd+shift+r")
        visible = _wait_until(lambda: _palette_visible(client, window_id))
        sel = _rename_selection(client, window_id)
        mode = _palette_mode(client, window_id)
        print(f"cmd+shift+r -> visible={visible} selection={sel} mode={mode}")
        _close_palette(client, window_id)

        # Case 2: Cmd+R (rename tab) should also open the palette.
        client.simulate_shortcut("cmd+r")
        visible_tab = _wait_until(lambda: _palette_visible(client, window_id))
        sel_tab = _rename_selection(client, window_id)
        mode_tab = _palette_mode(client, window_id)
        print(f"cmd+r -> visible={visible_tab} selection={sel_tab} mode={mode_tab}")
        _close_palette(client, window_id)

        if visible:
            print("PASS: Cmd+Shift+R opens the workspace rename flow in dev build")
            return 0
        print("FAIL: Cmd+Shift+R did not open the rename palette")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
