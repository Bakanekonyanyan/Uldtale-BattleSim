"""Minimal-diff JSON saving.

The data files are hand-formatted (mixed tabs/spaces, compact one-line objects),
so re-serialising a whole file on every save would rewrite hundreds of lines.
Instead we parse the original text while recording where every value sits, then
patch only what changed:

  - changed scalar            -> replace that token
  - dict with the same keys   -> recurse into each key
  - dict with keys added/removed/renamed -> insert/delete just those members
  - anything else (lists of different length, type changes) -> re-serialise
    that one value, inline if it was inline before

`splice()` returns the new text, or None if the result wouldn't parse back to
exactly the new data (the caller then falls back to a full rewrite).
"""
from __future__ import annotations

import json
import re

from .jsonio import dumps

_WS = " \t\r\n"


class _Parser:
    def __init__(self, text: str):
        self.t = text
        self.i = 0
        self.spans: dict = {}       # path -> (start, end) of the value
        self.keys: dict = {}        # path -> start of the key string (members only)

    def ws(self):
        while self.i < len(self.t) and self.t[self.i] in _WS:
            self.i += 1

    def value(self, path):
        self.ws()
        start = self.i
        c = self.t[self.i]
        if c == "{":
            v = self.obj(path)
        elif c == "[":
            v = self.arr(path)
        elif c == '"':
            v = self.string()
        else:
            m = re.compile(r"-?\d+(\.\d+)?([eE][+-]?\d+)?|true|false|null").match(self.t, self.i)
            if not m:
                raise ValueError(f"bad JSON at {self.i}")
            self.i = m.end()
            v = json.loads(m.group(0))
        self.spans[path] = (start, self.i)
        return v

    def string(self):
        m = re.compile(r'"(?:[^"\\]|\\.)*"', re.DOTALL).match(self.t, self.i)
        if not m:
            raise ValueError(f"bad string at {self.i}")
        self.i = m.end()
        return json.loads(m.group(0))

    def obj(self, path):
        self.i += 1
        out = {}
        self.ws()
        if self.t[self.i] == "}":
            self.i += 1
            return out
        while True:
            self.ws()
            kstart = self.i
            k = self.string()
            self.ws()
            if self.t[self.i] != ":":
                raise ValueError(f"expected : at {self.i}")
            self.i += 1
            self.keys[path + (k,)] = kstart
            out[k] = self.value(path + (k,))
            self.ws()
            if self.t[self.i] == ",":
                self.i += 1
                continue
            if self.t[self.i] == "}":
                self.i += 1
                return out
            raise ValueError(f"expected , or }} at {self.i}")

    def arr(self, path):
        self.i += 1
        out = []
        self.ws()
        if self.t[self.i] == "]":
            self.i += 1
            return out
        while True:
            out.append(self.value(path + (len(out),)))
            self.ws()
            if self.t[self.i] == ",":
                self.i += 1
                continue
            if self.t[self.i] == "]":
                self.i += 1
                return out
            raise ValueError(f"expected , or ] at {self.i}")


def parse_with_spans(text: str):
    p = _Parser(text)
    data = p.value(())
    return data, p.spans, p.keys


def _line_ws(text: str, pos: int) -> str:
    """Leading whitespace of the line containing pos."""
    line_start = text.rfind("\n", 0, pos) + 1
    m = re.match(r"[ \t]*", text[line_start:])
    return m.group(0)


def _render(value, text: str, start: int, end: int, indent: str) -> str:
    """Serialise `value` to replace text[start:end], matching its style."""
    was_inline = "\n" not in text[start:end]
    if was_inline and not isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    if was_inline:
        compact = json.dumps(value, ensure_ascii=False, separators=(", ", ": "))
        if isinstance(value, dict) and value and text[start:start + 2] == "{ ":
            compact = "{ " + compact[1:-1] + " }"
        if len(compact) <= 100:
            return compact
    base = _line_ws(text, start)
    lines = dumps(value, indent).split("\n")
    return "\n".join([lines[0]] + [base + l for l in lines[1:]])


def _edits(text, spans, keys, old, new, path, indent, out):
    if old == new and type(old) is type(new):
        return
    start, end = spans[path]
    if isinstance(old, dict) and isinstance(new, dict) and old and new and "\n" in text[start:end]:
        old_keys = list(old)
        new_keys = list(new)
        # pure renames: same length, keys differ only at some positions -> swap the key text
        if len(old_keys) == len(new_keys) and old_keys != new_keys and \
                all(o == n or (o not in new and n not in old) for o, n in zip(old_keys, new_keys)):
            for o, n in zip(old_keys, new_keys):
                if o != n:
                    ks = keys[path + (o,)]
                    ke = re.compile(r'"(?:[^"\\]|\\.)*"', re.DOTALL).match(text, ks).end()
                    out.append((ks, ke, json.dumps(n, ensure_ascii=False)))
                _edits(text, spans, keys, old[o], new[n], path + (o,), indent, out)
            return
        common = [k for k in new_keys if k in old]
        if common == [k for k in old_keys if k in new]:      # surviving keys keep their order
            for k in common:
                _edits(text, spans, keys, old[k], new[k], path + (k,), indent, out)
            # removals: delete the member plus the comma that separates it
            for k in old_keys:
                if k in new:
                    continue
                idx = old_keys.index(k)
                kstart = keys[path + (k,)]
                vend = spans[path + (k,)][1]
                if idx > 0:
                    prev_end = spans[path + (old_keys[idx - 1],)][1]
                    out.append((prev_end, vend, ""))
                else:
                    nxt = old_keys[idx + 1] if idx + 1 < len(old_keys) else None
                    if nxt is not None:
                        out.append((kstart, keys[path + (nxt,)], ""))
                    else:
                        out.append((start + 1, vend, "\n" + _line_ws(text, start)))
            # insertions: after the previous surviving key (or at the start)
            sibling = keys[path + (old_keys[0],)]
            member_ws = _line_ws(text, sibling)
            for i, k in enumerate(new_keys):
                if k in old:
                    continue
                prev = next((p for p in reversed(new_keys[:i]) if p in old), None)
                lines = dumps(new[k], indent).split("\n")
                body = "\n".join([lines[0]] + [member_ws + l for l in lines[1:]])
                member = f"{json.dumps(k, ensure_ascii=False)}: {body}"
                if prev is not None:
                    pos = spans[path + (prev,)][1]
                    out.append((pos, pos, ",\n" + member_ws + member))
                else:
                    pos = keys[path + (old_keys[0],)]
                    out.append((pos, pos, member + ",\n" + member_ws))
            return
    if isinstance(old, list) and isinstance(new, list) and len(old) == len(new) and old and "\n" in text[start:end]:
        for i in range(len(old)):
            _edits(text, spans, keys, old[i], new[i], path + (i,), indent, out)
        return
    out.append((start, end, _render(new, text, start, end, indent)))


def splice(text: str, new_data, indent: str = "\t") -> str | None:
    try:
        old, spans, keys = parse_with_spans(text)
    except (ValueError, IndexError):
        return None
    edits: list = []
    _edits(text, spans, keys, old, new_data, (), indent, edits)
    # apply from the end so offsets stay valid; same-position inserts keep their order
    # At the same start, apply deletions/replacements before pure insertions, and
    # several insertions in their original order (so they read top to bottom).
    order = sorted(enumerate(edits), key=lambda x: (x[1][0], x[1][1] > x[1][0], -x[0]), reverse=True)
    for i, (s, e, rep) in order:
        text = text[:s] + rep + text[e:]
    try:
        if json.loads(text) != new_data:
            return None
    except ValueError:
        return None
    return text
