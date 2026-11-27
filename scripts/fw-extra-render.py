#!/usr/bin/env python3
"""fw-extra-render.py - render a minimal #cloud-config into a remote apply script.

Cloud-config subset supported (the partner contract: files + shell, executed
only when the content changes):
  #cloud-config
  runcmd:
    - <command>                  # scalar string
    - [cmd, arg1, arg2]          # exec-form list (joined with spaces)
  write_files:
    - path: /abs/path            # absolute target
      permissions: '0644'        # optional chmod
      content: |                 # literal block (only this form is supported)
        <lines>

Everything is encoded as base64 in the emitted script so no quoting/escaping
can break shell. The script ends by writing the content hash marker.

Env: FW_CI_B64 (base64 of the payload), FW_NODE (active|passive), FW_HASH.
Writes the remote sh script to stdout. Exits 2 when the payload is not a
#cloud-config or uses an unsupported construct.
"""
import base64
import os
import re
import sys

def b64(s: str) -> str:
    return base64.b64encode(s.encode("utf-8")).decode("ascii")

def unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    return s

def main() -> int:
    ci = base64.b64decode(os.environ["FW_CI_B64"]).decode("utf-8", "replace")
    node = os.environ.get("FW_NODE", "node")
    h = os.environ["FW_HASH"]
    mark = "/conf/.extra_uud_%s.hash" % node

    lines = [l[:-1] if l.endswith("\r") else l for l in ci.split("\n")]

    # first non-empty line must be the cloud-config header (it starts with #)
    first = next((l for l in lines if l.strip()), "")
    if not first.strip().startswith("#cloud-config"):
        sys.stderr.write("fw-extra-render: payload is not a #cloud-config\n")
        return 2

    section = None            # 'runcmd' | 'write_files'
    curfile = None
    content_indent = -1       # >=0 while collecting a content block
    content_lines = []
    files = []
    runcmd = []

    def commit_content():
        nonlocal content_indent, content_lines
        if curfile is not None and content_lines:
            # cloud-config literal block: dedent content by the block indent
            # (min leading spaces over non-empty lines); extra indentation and
            # blank lines are preserved, matching YAML block-scalar semantics.
            nonempty = [l for l in content_lines if l.strip()]
            if nonempty:
                bi = min(len(l) - len(l.lstrip(" ")) for l in nonempty)
                ded = [l[bi:] if l.strip() else "" for l in content_lines]
                curfile["content"] = "\n".join(ded) + "\n"
        content_lines = []
        content_indent = -1

    for raw in lines:
        strip = raw.strip()
        if not strip or (strip.startswith("#") and content_indent < 0):
            continue
        indent = len(raw) - len(raw.lstrip(" "))

        # Inside a literal content block: anything more indented is its data.
        if content_indent >= 0:
            if indent > content_indent:
                content_lines.append(raw)
                continue
            commit_content()   # fall through: line closes the block

        if indent == 0 and ":" in strip and not strip.startswith("-"):
            commit_content()
            head = strip.split(":", 1)[0].strip()
            section = head if head in ("runcmd", "write_files") else None
            curfile = None
            continue

        if section == "runcmd" and strip.startswith("-"):
            item = strip[1:].strip()
            if item.startswith("[") and item.endswith("]"):
                # exec-form: keep inner quoting intact (only trim outer spaces
                # around each comma-separated element) so args with spaces and
                # quotes survive the join.
                inner = item[1:-1]
                parts = [p.strip() for p in inner.split(",")]
                item = " ".join(parts)
            else:
                item = unquote(item)
            if item:
                runcmd.append(item)
            continue

        if section == "write_files":
            if strip.startswith("-"):
                commit_content()
                curfile = {}
                files.append(curfile)
                rest = strip[1:].strip()
                if rest.startswith("path:"):
                    curfile["path"] = unquote(rest[len("path:"):])
                continue
            if curfile is not None:
                if strip.startswith("path:"):
                    curfile["path"] = unquote(strip[len("path:"):])
                elif strip.startswith("permissions:"):
                    curfile["mode"] = unquote(strip[len("permissions:"):])
                elif strip.startswith("content:") and "|" in strip:
                    content_indent = indent
                    content_lines = []
                # unknown keys inside write_files are ignored
                continue

        # anything else (unknown top-level keys, comments) is ignored
        if strip.startswith("#") and content_indent < 0:
            continue

    commit_content()

    # ---- emit ----
    head = "#!/bin/sh\nset -e\n"
    body = []
    for f in files:
        path = f.get("path", "")
        if not path.startswith("/"):
            sys.stderr.write("fw-extra-render: write_files path must be absolute: %r\n" % path)
            return 2
        content = f.get("content", "")
        body.append('mkdir -p "$(dirname %s)"' % _shq(path))
        body.append('printf %s | base64 -d > %s' % (_shq(b64(content)), _shq(path)))
        mode = f.get("mode")
        if mode:
            body.append("chmod %s %s" % (_shq(mode), _shq(path)))
    for cmd in runcmd:
        body.append('printf %s | base64 -d | sh' % _shq(b64(cmd)))
    if not (files or runcmd):
        sys.stderr.write("fw-extra-render: cloud-config has no runcmd/write_files\n")
        return 2
    tail = ['printf %s > %s' % (_shq(h), _shq(mark)), ""]
    sys.stdout.write(head + "\n".join(body) + "\n" + "\n".join(tail) + "\n")
    return 0

def _shq(s: str) -> str:
    return "'" + s.replace("'", "'\\''") + "'"

if __name__ == "__main__":
    sys.exit(main())
