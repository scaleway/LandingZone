#!/usr/bin/env python3
"""Functional test for the merged scw-lz/stages/5-backup/files/fw-tool.sh.

Extracts the embedded Python heredoc and exercises both MODE paths with a
mocked `subprocess.run` (no network, no real ssh/rclone) plus a stubbed
HTTP server (the module blocks on serve_forever() at import time).
"""
import io
import json
import os
import re
import subprocess
import sys
import types
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC = str(REPO_ROOT / "scw-lz/stages/5-backup/files/fw-tool.sh")
with open(SRC) as fh:
    shell = fh.read()

# --- 1. extract the python heredoc ----------------------------------------
m = re.search(r"cat > /tmp/fw_tool_server\.py <<'PYEOF'\n(.*?)^PYEOF$", shell,
              re.MULTILINE | re.DOTALL)
assert m, "python heredoc not found"
code = m.group(1)

compile(code, "fw_tool_server.py", "exec")  # syntax check
print("PASS: embedded python compiles")

# --- 2. import it with a stubbed HTTP server ------------------------------
import http.server

CAPTURED = {}


class FakeServer:
    def __init__(self, addr, handler):
        CAPTURED["addr"] = addr
        CAPTURED["handler"] = handler

    def serve_forever(self):
        pass

orig_threading = http.server.ThreadingHTTPServer
http.server.ThreadingHTTPServer = lambda *a, **k: FakeServer(*a, **k)

mod = types.ModuleType("fw_tool_server")
mod.__dict__["__name__"] = "fw_tool_server"
exec(code, mod.__dict__)

# --- 3. mocked subprocess.run ---------------------------------------------
RESPONSES = {}  # keyed by (host, mode) -> list of fake run outcomes


def fake_run(cmd, **kwargs):
    prog, host = cmd[0], cmd[1]
    if prog == "rclone":
        # simulate an empty bucket listing
        if "lsjson" in cmd:
            return subprocess.CompletedProcess(cmd, 0, stdout=b"[]")
        return subprocess.CompletedProcess(cmd, 0, stdout=b"")
    # ssh path
    host = next(a.split("@")[1] for a in cmd if "@" in a)
    key = (host, os.environ["MODE"])
    outcome = RESPONSES[key]
    if isinstance(outcome, Exception):
        raise outcome
    return outcome


mod.subprocess.run = fake_run
HTTP_ERROR = ("HTTPError", "fatal")


def invoke_probe_response(host):
    # Build the handler without socket I/O: object.__new__ bypasses __init__,
    # _respond() only touches self.wfile + the standard writer methods.
    class W:
        def __init__(self):
            self.data = b""

        def write(self, data):
            self.data += data

    w = W()
    handler = object.__new__(CAPTURED["handler"])
    handler.command = "GET"
    handler.requestline = "GET / HTTP/1.0"
    handler.request_version = "HTTP/1.0"
    handler.close_connection = True
    handler._headers_buffer = []
    handler.client_address = ("127.0.0.1", 0)
    handler.wfile = w
    try:
        handler._handle()
        line = w.data.split(b"\r\n", 1)[0] if w.data else b""
        code = int(line.split()[1]) if line.startswith(b"HTTP/") else 200
    except Exception:
        code = 500
    return type("R", (), {"code": code, "body": w.data})()



# --- 4. cases --------------------------------------------------------------
def test_export_empty_hosts():
    os.environ.update(MODE="export", FW_HOSTS="", FW_USER="root", PORT="8080")
    ok, msg = mod.run_export()
    assert ok, msg
    assert "prune firewall/config" in msg and "prune firewall/logs" in msg, msg
    print("PASS: export mode (no hosts) runs and prunes empty bucket")


def test_export_dispatch_http():
    ok, msg = mod.run()
    assert ok and "prune" in msg
    print("PASS: export dispatch (MODE=export) -> run_export")


def test_probe_success():
    os.environ.update(MODE="probe", FW_HOSTS="10.0.0.9", FW_USER="root", PORT="8090")
    # reload module with fresh env? Instead: run() reads MODE at call time via
    # run() -> run_probe(); but SSH_BASE/PORT read at import. Re-exec module.
    global mod
    mod = types.ModuleType("fw_tool_server")
    exec(code, mod.__dict__)
    mod.subprocess.run = fake_run
    report = "fw-drill-1\nconfigd:2\ncarp: MASTER vhid 10\ncarp: BACKUP vhid 11\ndone\n"
    RESPONSES[("10.0.0.9", "probe")] = subprocess.CompletedProcess(
        ["ssh"], 0, stdout=report.encode(), stderr=b"")
    ok, results = mod.run()
    assert ok, results
    assert results[0]["ok"] and "configd:2" in results[0]["report"], results
    print("PASS: probe mode succeeds and parses report")


def test_probe_failure_http_500():
    RESPONSES[("10.0.0.9", "probe")] = subprocess.CompletedProcess(
        ["ssh"], 255, stdout=b"", stderr=b"Connection refused")
    ok, results = mod.run()
    assert not ok and not results[0]["ok"], results
    print("PASS: probe mode reports failure (ok=False, err present)")


def test_http_500_body_has_tag():
    # a probe failure should produce a 500 with the drill tag
    os.environ.update(MODE="probe", FW_HOSTS="10.0.0.9")
    global mod
    mod = types.ModuleType("fw_tool_server")
    exec(code, mod.__dict__)
    mod.subprocess.run = fake_run
    RESPONSES[("10.0.0.9", "probe")] = subprocess.CompletedProcess(
        ["ssh"], 255, stdout=b"", stderr=b"refused")
    resp = invoke_probe_response("10.0.0.9")
    assert resp.code == 500, resp.code
    assert b"drill-fw-probe" in resp.body, resp.body
    print("PASS: probe HTTP 500 body carries [drill-fw-probe] tag")


if __name__ == "__main__":
    test_export_empty_hosts()
    test_export_dispatch_http()
    test_probe_success()
    test_probe_failure_http_500()
    test_http_500_body_has_tag()
    print("\nALL FIREWALL-TOOL TESTS PASSED")
