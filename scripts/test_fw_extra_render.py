#!/usr/bin/env python3
"""Unit tests for scripts/fw-extra-render.py.

Covers: TEMP payload (runcmd only), write_files payload, exec-form runcmd,
permissions, non-cloud-config rejection, unsupported-relative-path rejection,
and that every emitted script passes `sh -n` and round-trips its content.
"""
import base64
import importlib.util
import os
import subprocess
import sys
import tempfile

# module file is dash-named (repo convention), load it by path
_spec = importlib.util.spec_from_file_location(
    "fw_extra_render",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "fw-extra-render.py"),
)
R = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(R)

PASS = 0
FAIL = 0

def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  [PASS] %s" % name)
    else:
        FAIL += 1
        print("  [FAIL] %s %s" % (name, detail))

def render_capture(ci, node="active", h="deadbeef"):
    os.environ["FW_CI_B64"] = base64.b64encode(ci.encode("utf-8")).decode("ascii")
    os.environ["FW_NODE"] = node
    os.environ["FW_HASH"] = h
    import io
    from contextlib import redirect_stdout, redirect_stderr
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = R.main()
    return rc, out.getvalue(), err.getvalue()

TEMP_PASSIVE = """#cloud-config
runcmd:
  - sh -c 'echo "extra_uud_passive $(hostname) $(date -u)" >> /var/log/extra_uud_marker.log'
  - touch /tmp/extra_uud_passive_marker
"""

WRITE_FILES = """#cloud-config
write_files:
  - path: /etc/opnsense/extra.conf
    permissions: '0640'
    content: |
      # generated marker
      line one
      line two
runcmd:
  - [ /bin/sh, -c, 'echo booted >> /var/log/extra_uud_marker.log' ]
"""

NOT_CC = "#!/bin/sh\necho hello\n"

REL_PATH = """#cloud-config
write_files:
  - path: relative/thing
    content: |
      x
"""

def main():
    print("== 1. TEMP payload (runcmd, no write_files) ==")
    rc, out, err = render_capture(TEMP_PASSIVE, node="passive")
    check("exit 0", rc == 0, "rc=%s" % rc)
    check("marker path uses node name", "/conf/.extra_uud_passive.hash" in out, out)
    check("never target other node marker", "/conf/.extra_uud_active.hash" not in out)
    body = out.splitlines()
    check("2 runcmd entries emitted", sum(1 for l in body if "| base64 -d | sh" in l) == 2, out)
    check("sh -n passes", subprocess.run(["/bin/sh", "-n"], input=out.encode()).returncode == 0)
    # round-trip: first rendered command decodes to the first runcmd line
    first_cmd = next(l for l in body if "| base64 -d | sh" in l)
    b64part = first_cmd.split("| base64 -d | sh")[0].split("printf ")[1]
    decoded = base64.b64decode(b64part.strip("'")).decode()
    check("runcmd[0] round-trips", decoded == "sh -c 'echo \"extra_uud_passive $(hostname) $(date -u)\" >> /var/log/extra_uud_marker.log'", decoded)

    print("== 2. write_files payload ==")
    rc, out, err = render_capture(WRITE_FILES, node="active")
    check("exit 0", rc == 0, "rc=%s" % rc)
    check("mkdir -p emitted", "mkdir -p \"$(dirname '/etc/opnsense/extra.conf')\"" in out, out)
    check("chmod emitted", "chmod '0640'" in out.replace("\n", " ") or "chmod 0640" in out.replace("\n", " "), out)
    check("sh -n passes", subprocess.run(["/bin/sh", "-n"], input=out.encode()).returncode == 0)
    # extract write content b64 and decode
    write_line = next(l for l in out.splitlines() if "base64 -d > '/etc/opnsense/extra.conf'" in l)
    b64part = write_line.split("base64 -d")[0].split("printf ")[1]
    decoded = base64.b64decode(b64part.strip("'")).decode()
    check("write_files content round-trips", decoded == "# generated marker\nline one\nline two\n", repr(decoded))
    # exec-form runcmd joined with spaces
    exec_line = next(l for l in out.splitlines() if "| base64 -d | sh" in l)
    b = exec_line.split("| base64 -d | sh")[0].split("printf ")[1]
    d = base64.b64decode(b.strip("'")).decode()
    check("exec-form joined as string", d == "/bin/sh -c 'echo booted >> /var/log/extra_uud_marker.log'", d)

    print("== 3. non-cloud-config rejected ==")
    rc, _, err = render_capture(NOT_CC)
    check("exit 2", rc == 2, "rc=%s" % rc)

    print("== 4. relative write_files path rejected ==")
    rc, _, err = render_capture(REL_PATH)
    check("exit 2", rc == 2, "rc=%s" % rc)

    print("== 5. empty / no-op cloud-config rejected ==")
    rc, _, err = render_capture("#cloud-config\n# nothing here\n")
    check("exit 2", rc == 2, "rc=%s" % rc)

    print("\nResult: %d passed | %d failed" % (PASS, FAIL))
    sys.exit(0 if FAIL == 0 else 1)

if __name__ == "__main__":
    main()
