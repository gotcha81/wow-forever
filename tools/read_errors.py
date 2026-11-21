"""Print an addon's caught Lua errors, for fixing them.

Usage:
    python tools/read_errors.py <AddonFolder> [--all-lua]

Reads two places in the local game folder (gamePath from tools/deploy.local.json):
  1. The addon's own error log: <AddonFolder>DB.errorLog in
     WTF/Account/*/SavedVariables/<AddonFolder>.lua. The game writes this file on
     /reload, logout or exit, so do one of those after an error.
  2. The game's own Lua error lines ([E][Lua]) in Logs/General.log, filtered to
     the addon (or every addon with --all-lua). The game empties this file every
     time it starts, so it only has the current session.

Never prints the game path or the account folder names (accounts are shown as
"account 1", "account 2", ...). Read-only: nothing in the game folder is changed.
Dev tool only, never needed at runtime.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --- a small reader for the Lua tables the game writes into SavedVariables ---

class LuaReader:
    def __init__(self, text):
        self.s, self.i = text, 0

    def ws(self):
        s = self.s
        while self.i < len(s):
            if s[self.i].isspace():
                self.i += 1
            elif s.startswith("--", self.i):
                end = s.find("\n", self.i)
                self.i = len(s) if end < 0 else end + 1
            else:
                break

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c == '"':
            return self.string()
        m = re.compile(r"-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?)|true|false|nil").match(self.s, self.i)
        if not m:
            raise ValueError("unexpected input at %d" % self.i)
        self.i = m.end()
        t = m.group(0)
        if t in ("true", "false"):
            return t == "true"
        if t == "nil":
            return None
        return int(t, 16) if "x" in t else (float(t) if any(ch in t for ch in ".eE") else int(t))

    def string(self):
        s, out = self.s, []
        self.i += 1
        while True:
            c = s[self.i]
            if c == '"':
                self.i += 1
                return "".join(out)
            if c == "\\":
                n = s[self.i + 1]
                out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"', "\n": "\n"}.get(n, n))
                self.i += 2
            else:
                out.append(c)
                self.i += 1

    def table(self):
        self.i += 1
        result, index = {}, 1
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                return result
            if self.s[self.i] == "[":
                self.i += 1
                key = self.value()
                self.ws()
                self.i += 1  # ]
                self.ws()
                self.i += 1  # =
                result[key] = self.value()
            else:
                result[index] = self.value()
                index += 1
            self.ws()
            if self.s[self.i] in ",;":
                self.i += 1


def read_global(path, name):
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"^%s\s*=\s*" % re.escape(name), text, re.M)
    if not m:
        return None
    reader = LuaReader(text)
    reader.i = m.end()
    return reader.value()


def as_list(t):
    if not isinstance(t, dict):
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


# --- main ---

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    all_lua = "--all-lua" in sys.argv
    if len(args) != 1 or not re.fullmatch(r"[A-Za-z0-9_]+", args[0]):
        print(__doc__)
        return 2
    addon = args[0]
    config = json.load(open(os.path.join(ROOT, "tools", "deploy.local.json"), encoding="utf-8"))
    game = config["gamePath"]

    print("=== %s: saved error log ===" % addon)
    files = sorted(glob.glob(os.path.join(game, "WTF", "Account", "*", "SavedVariables", addon + ".lua")))
    if not files:
        print("No saved file yet (the game writes it on /reload, logout or exit).")
    for n, path in enumerate(files, 1):
        try:
            db = read_global(path, addon + "DB")
        except Exception as e:  # a half-written file; say so instead of crashing
            print("account %d: could not read the saved file (%s)" % (n, e))
            continue
        log = as_list((db or {}).get("errorLog"))
        print("account %d: %d different errors" % (n, len(log)))
        for i, e in enumerate(log, 1):
            print("\n--- Error %d: %s time(s), in %s, version %s, first %s, last %s ---" % (
                i, e.get("count"), e.get("where"), e.get("version"), e.get("first"), e.get("last")))
            print(e.get("message", ""))
            stack = (e.get("stack") or "").strip()
            if stack:
                print(stack)

    print("\n=== Game log (General.log, this session only): [E][Lua]%s ===" % ("" if all_lua else " lines for " + addon))
    general = os.path.join(game, "Logs", "General.log")
    counts, order = {}, []
    if os.path.exists(general):
        for line in open(general, encoding="utf-8", errors="replace"):
            if "[E][Lua]" in line and (all_lua or addon in line):
                text = re.sub(r"^\S*\s*\d{1,2}:\d{2}:\d{2}\.\d+\s*", "", line.strip())  # drop the time stamp
                if text not in counts:
                    order.append(text)
                counts[text] = counts.get(text, 0) + 1
    if not order:
        print("None.")
    for text in order:
        print("%dx  %s" % (counts[text], text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
