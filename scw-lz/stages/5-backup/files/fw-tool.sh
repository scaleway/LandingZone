#!/bin/sh
# Stage 5 firewall tool - single entrypoint for the config/log exporter
# (MODE=export) and the restore-drill probe (MODE=probe). HTTP responder, so a
# cron container trigger schedules it. No secrets here: the backup key arrives
# via the FW_SSH_KEY secret env. Required env (all modes): FW_HOSTS, FW_USER,
# PORT, FW_SSH_KEY. Export mode adds BUCKET, PREFIX_*, retention days and
# RCLONE_CONFIG_DST_* / AWS_*.
#
set -eu

# Install runtime deps on cold start (idempotent, ~seconds on alpine).
if ! command -v ssh >/dev/null 2>&1 \
   || ! command -v python3 >/dev/null 2>&1; then
  apk add --no-cache openssh-client python3 >/dev/null 2>&1 || true
fi
# rclone is only needed for the export mode; keep the probe container lean.
if [ "${MODE:-export}" = "export" ] && ! command -v rclone >/dev/null 2>&1; then
  apk add --no-cache rclone >/dev/null 2>&1 || true
fi

# Materialize the injected SSH private key.
: "${FW_SSH_KEY:?FW_SSH_KEY secret not injected}"
printf '%s\n' "$FW_SSH_KEY" > /tmp/fw_id_ed25519
chmod 600 /tmp/fw_id_ed25519

cat > /tmp/fw_tool_server.py <<'PYEOF'
import http.server
import subprocess
import os
import sys
import time
import json
import gzip
import datetime

MODE = os.environ.get("MODE", "export")

FW_HOSTS = [h.strip() for h in os.environ.get("FW_HOSTS", "").split(",") if h.strip()]
FW_USER  = os.environ.get("FW_USER", "root")
PORT     = int(os.environ.get("PORT", "8080"))
SSH_KEY  = "/tmp/fw_id_ed25519"

# Probe nodes can be mid-CARP-settling (serialized reboots) and are on a
# tighter timeout; the exporter talks to steady-state firewalls.
SSH_BASE = [
    "ssh", "-i", SSH_KEY,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=%d" % (5 if MODE == "probe" else 10),
    "-o", "BatchMode=yes",
]

# ---------------------------------------------------------------------------
# Export mode
# ---------------------------------------------------------------------------
BUCKET = os.environ.get("BUCKET", "lz-dev-backup")
PREFIX_CONFIG = os.environ.get("PREFIX_CONFIG", "firewall/config")
PREFIX_LOGS   = os.environ.get("PREFIX_LOGS", "firewall/logs")
CONFIG_RETENTION_DAYS = int(os.environ.get("CONFIG_RETENTION_DAYS", "90"))
LOGS_RETENTION_DAYS   = int(os.environ.get("LOGS_RETENTION_DAYS", "30"))

# OPNsense 26.x keeps logs in per-service directories with date-stamped
# archives plus a stable <service>/latest.log pointer (discovered cloud-side;
# the legacy /var/log/<name>.log flat files are gone). latest.log is what we
# export - the current log - so retention stays bounded by the prune step.
LOG_FILES = [
    ("configd.log",   "/var/log/configd/latest.log"),     # config/daemon changes
    ("system.log",    "/var/log/system/latest.log"),      # system/auth events
    ("filter.log",    "/var/log/filter/latest.log"),      # firewall pass/block
    ("audit.log",     "/var/log/audit/latest.log"),       # auth audit trail
    ("hostwatch.log", "/var/log/hostwatch/latest.log"),   # HA/CARP transitions
]


def ssh_fetch(host, remote_path, timeout=25, allow_missing=False):
    out = subprocess.run(
        SSH_BASE + ["{0}@{1}".format(FW_USER, host), "cat", remote_path],
        capture_output=True, timeout=timeout,
    )
    if out.returncode != 0:
        err = (out.stderr or out.stdout or b"").decode("utf-8", "replace")
        if allow_missing and ("No such file" in err):
            return None
        raise RuntimeError(err.strip()[:300])
    return out.stdout


def rclone_upload(local, dest):
    rc = subprocess.run(["rclone", "copyto", local, "dst:{0}".format(dest)],
                        capture_output=True, timeout=90)
    if rc.returncode != 0:
        err = (rc.stderr or b"rclone failed")
        raise RuntimeError(err.decode("utf-8", "replace").strip()[:300])


def rclone_ls(remote_prefix):
    rc = subprocess.run(
        ["rclone", "lsjson", "dst:{0}".format(remote_prefix), "--recursive", "--files-only"],
        capture_output=True, timeout=120,
    )
    if rc.returncode != 0:
        err = (rc.stderr or b"rclone lsjson failed")
        raise RuntimeError(err.decode("utf-8", "replace").strip()[:300])
    return json.loads(rc.stdout.decode() or "[]")


def rclone_delete(remote_path):
    subprocess.run(["rclone", "deletefile", "dst:{0}".format(remote_path)],
                   capture_output=True, timeout=60)


def export_host_files(host, i, stamp, results):
    # Config - one file per host.
    cfg_name = "/tmp/fw{0}.xml".format(i)
    cfg = ssh_fetch(host, "/conf/config.xml")
    with open(cfg_name, "wb") as fh:
        fh.write(cfg)
    rclone_upload(cfg_name, "{0}/{1}/{2}/fw{3}.xml".format(
        BUCKET, PREFIX_CONFIG, stamp, i))
    results.append("{0}: config ok ({1} B)".format(host, len(cfg)))

    # Logs - a bounded set per host; missing logs are skipped (self-diagnosed
    # via the /var/log listing below), never fatal. Logs are gzipped before
    # upload (text logs compress ~10-20x; deterministic mtime for stable
    # rsync-style mirroring).
    for name, remote_path in LOG_FILES:
        data = ssh_fetch(host, remote_path, allow_missing=True)
        if data is None:
            results.append("{0}: {1} skipped (not present)".format(host, name))
            continue
        if len(data) == 0:
            results.append("{0}: {1} empty".format(host, name))
            continue
        lname = "/tmp/fw{0}-{1}.gz".format(i, name)
        with open(lname, "wb") as fh:
            with gzip.GzipFile(fileobj=fh, mode="wb", mtime=0) as gz:
                gz.write(data)
        rclone_upload(lname, "{0}/{1}/{2}/fw{3}-{4}.gz".format(
            BUCKET, PREFIX_LOGS, stamp, i, name))
        results.append("{0}: {1} ok ({2} B -> {3} B gz)".format(
            host, name, len(data), os.path.getsize(lname)))


def export_host(host, i, stamp, results):
    # Retry transient unreachability (e.g. CARP settling after a FW reboot)
    # a few times before marking the host failed.
    for attempt in range(3):
        try:
            export_host_files(host, i, stamp, results)
            return True
        except Exception as exc:  # noqa: BLE001
            results.append("{0}: FAIL (attempt {1}) {2}".format(host, attempt + 1, exc))
            time.sleep(8)
    return False


def prune(remote_prefix, days, results):
    deleted = 0
    try:
        cutoff = time.time() - days * 86400
        for f in rclone_ls("{0}/{1}".format(BUCKET, remote_prefix)):
            mtime = None
            try:
                mtime = datetime.datetime.fromisoformat(
                    f.get("ModTime", "").replace("Z", "+00:00")).timestamp()
            except (TypeError, ValueError):
                continue
            if mtime is not None and mtime < cutoff:
                path = "{0}/{1}/{2}".format(BUCKET, remote_prefix, f.get("Path", ""))
                rclone_delete(path)
                deleted += 1
        results.append("prune {0} (>={1}d): {2} deleted".format(remote_prefix, days, deleted))
    except Exception as exc:  # noqa: BLE001 - report, do not fail the export
        results.append("prune {0}: FAIL {1}".format(remote_prefix, exc))


def run_export():
    ok = True
    results = []
    # One stamp per invocation (not per process): every request is its own
    # recovery point even if the scale-to-zero instance stays warm.
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    for i, host in enumerate(FW_HOSTS, start=1):
        if not export_host(host, i, stamp, results):
            ok = False
    # Prune on the primary bucket (DR stays the long-term archive).
    prune(PREFIX_CONFIG, CONFIG_RETENTION_DAYS, results)
    prune(PREFIX_LOGS, LOGS_RETENTION_DAYS, results)
    return ok, "; ".join(results)


# ---------------------------------------------------------------------------
# Probe mode
# ---------------------------------------------------------------------------
# One-shot verification: hostname, LAN IP, configd count (pgrep -f matches
# the python configd.py daemon), CARP state per vhid. Fed to `sh -s` on stdin.
PROBE_SCRIPT = (
    "hostname\n"
    "configd_count=$(pgrep -f '/configd.py' | wc -l | tr -d ' '); echo configd:$configd_count\n"
    "ifconfig | grep -E 'carp|vhid' | head -12\n"
    "echo done\n"
)


def probe(host, timeout=15):
    out = subprocess.run(
        SSH_BASE + ["{0}@{1}".format(FW_USER, host), "sh", "-s"],
        input=PROBE_SCRIPT.encode("utf-8"),
        capture_output=True, timeout=timeout,
    )
    if out.returncode != 0:
        err = (out.stderr or out.stdout or b"ssh failed")
        return {"host": host, "ok": False,
                "err": err.decode("utf-8", "replace").strip()[-200:]}
    return {"host": host, "ok": True,
            "report": out.stdout.decode("utf-8", "replace").strip()}


def run_probe():
    results = []
    ok = True
    for host in FW_HOSTS:
        # Retry: right after the serialized reboots one node can be briefly
        # unreachable (CARP settling) - same pattern as the prod exporter.
        res = None
        for _ in range(8):
            res = probe(host)
            if res["ok"] and "configd:" in res["report"] and "vhid" in res["report"]:
                break
            time.sleep(5)
        if res is None or not res["ok"] or "configd:" not in (res.get("report") or "") or "vhid" not in (res.get("report") or ""):
            ok = False
        results.append(res)
    return ok, results


# ---------------------------------------------------------------------------
# HTTP responder + dispatch
# ---------------------------------------------------------------------------
def run():
    if MODE == "probe":
        return run_probe()
    return run_export()


TAG = "drill-fw-probe" if MODE == "probe" else "fw-export"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), args))

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def _handle(self):
        try:
            ok, payload = run()
            if MODE == "probe":
                body = ("[" + TAG + "] " + json.dumps(payload) + "\n").encode("utf-8")
            else:
                body = ("[" + TAG + "] " + payload + "\n").encode("utf-8")
            self._respond(200 if ok else 500, body)
        except Exception as exc:  # noqa: BLE001
            self._respond(500, ("[" + TAG + "] fatal: {0}\n".format(exc)).encode("utf-8"))

    def _respond(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass


http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
PYEOF

exec python3 /tmp/fw_tool_server.py
