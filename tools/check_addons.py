"""Check every addon in this repo against the installed WoW Forever client.

Usage:
    python tools/check_addons.py            report only, changes nothing
    python tools/check_addons.py --apply    also write the game's interface number
                                            into every addon's TOC

What it reports, for every addon folder (a folder with <Folder>.toc):
  1. The game's interface number, worked out from the installed Forever client
     (.build.info, product "wowf"): version 1.60.1 -> 1*10000 + 60*100 + 1 = 16001.
     Each TOC's "## Interface:" is compared with it.
  2. A Lua syntax check of every .lua file outside Libs/ (needs the Python
     package luaparser; skipped with a note when it isn't installed).
  3. The addon's own saved error log (<Folder>DB.errorLog), as a count.
     Run tools/read_errors.py <Folder> for the full text.
  4. The game API the addon calls (C_*.Function names and global functions),
     to check against the API changes of a new game version.

Never prints the game path or account names. Without --apply nothing is written.
Dev tool only, never needed at runtime.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
FOREVER_PRODUCT = "wowf"

# Lua keywords and standard-library names: never reported as game API.
LUA_NAMES = set("""and break do else elseif end false for function if in local nil not or repeat return
then true until while assert collectgarbage error getmetatable ipairs next pairs pcall print rawequal
rawget rawset select setmetatable tonumber tostring type unpack xpcall string table math coroutine os
debug bit strsub strlen strupper strlower strfind strmatch gsub format tinsert tremove wipe sort floor
ceil abs max min date time""".split())


def game_path():
    config = json.load(open(os.path.join(ROOT, "tools", "deploy.local.json"), encoding="utf-8"))
    return os.path.normpath(config["gamePath"])


def game_version(game):
    """The installed Forever client's version, e.g. '1.60.1.71037', or None."""
    for base in (game, os.path.dirname(game)):
        path = os.path.join(base, ".build.info")
        if not os.path.exists(path):
            continue
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
        header = [h.split("!")[0] for h in lines[0].split("|")]
        for line in lines[1:]:
            row = dict(zip(header, line.split("|")))
            if row.get("Product") == FOREVER_PRODUCT:
                return row.get("Version")
    return None


def interface_number(version):
    major, minor, patch = (int(x) for x in version.split(".")[:3])
    return major * 10000 + minor * 100 + patch


def addons():
    found = []
    for path in sorted(glob.glob(os.path.join(ROOT, "*", "*.toc"))):
        folder = os.path.basename(os.path.dirname(path))
        name = os.path.splitext(os.path.basename(path))[0]
        if name == folder or name.startswith(folder + "_"):
            found.append((folder, path))
    return found


def toc_field(text, field):
    m = re.search(r"^##\s*%s:\s*(.*?)\s*$" % field, text, re.M)
    return m.group(1) if m else None


def lua_files(folder):
    out = []
    for path in glob.glob(os.path.join(ROOT, folder, "**", "*.lua"), recursive=True):
        rel = os.path.relpath(path, os.path.join(ROOT, folder))
        if not rel.replace("\\", "/").startswith("Libs/"):
            out.append(path)
    return sorted(out)


def syntax_errors(files):
    try:
        from luaparser import ast
    except ImportError:
        return None
    errors = []
    for path in files:
        try:
            ast.parse(open(path, encoding="utf-8").read())
        except Exception as e:  # report the file, keep checking the rest
            errors.append("%s: %s" % (os.path.relpath(path, ROOT), str(e).splitlines()[0][:160]))
    return errors


def api_calls(files):
    """Game API names an addon calls: C_Namespace.Function and global Functions."""
    namespaced, globals_, defined = set(), set(), set()
    for path in files:
        code = open(path, encoding="utf-8").read()
        code = re.sub(r"--\[\[.*?\]\]", "", code, flags=re.S)
        code = re.sub(r"--[^\n]*", "", code)
        # The addon's own names (found before strings are blanked out).
        defined.update(re.findall(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", code))
        defined.update(re.findall(r"\blocal\s+function\s+([A-Za-z_]\w*)", code))
        defined.update(re.findall(r"\blocal\s+([A-Za-z_]\w*)\s*=", code))
        # Blank out quoted strings; a Lua quoted string never spans lines.
        code = re.sub(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', '""', code)
        namespaced.update(re.findall(r"\b(C_\w+\.\w+)", code))
        for name in re.findall(r"(?<![\w.:])([A-Z][A-Za-z0-9_]*)\s*\(", code):
            globals_.add(name)
    globals_ -= defined
    globals_ -= LUA_NAMES
    globals_ = {g for g in globals_ if not g.startswith("C_")}
    return sorted(namespaced), sorted(globals_)


def error_count(game, folder):
    try:
        from read_errors import read_global, as_list
    except Exception:
        return None
    total = 0
    for path in glob.glob(os.path.join(game, "WTF", "Account", "*", "SavedVariables", folder + ".lua")):
        try:
            db = read_global(path, folder + "DB")
        except Exception:
            continue
        for e in as_list((db or {}).get("errorLog")):
            total += 1
    return total


def main():
    apply = "--apply" in sys.argv
    game = game_path()
    version = game_version(game)
    if not version:
        print("Could not find the Forever client's version (.build.info, product %s)." % FOREVER_PRODUCT)
        return 1
    wanted = str(interface_number(version))
    print("Game: WoW Forever %s -> interface %s\n" % (version, wanted))

    for folder, toc in addons():
        text = open(toc, encoding="utf-8").read()
        interface = toc_field(text, "Interface") or "?"
        addon_version = toc_field(text, "Version") or "?"
        print("=== %s %s ===" % (folder, addon_version))

        numbers = [n.strip() for n in interface.split(",")]
        if wanted in numbers:
            print("  Interface: %s (up to date)" % interface)
        elif apply:
            text = re.sub(r"^(##\s*Interface:\s*).*$", lambda m: m.group(1) + wanted, text, count=1, flags=re.M)
            open(toc, "w", encoding="utf-8", newline="").write(text)
            print("  Interface: %s -> %s (WRITTEN)" % (interface, wanted))
        else:
            print("  Interface: %s, the game wants %s (run with --apply to update)" % (interface, wanted))

        files = lua_files(folder)
        errors = syntax_errors(files)
        if errors is None:
            print("  Syntax: skipped (pip install luaparser to check)")
        elif errors:
            print("  Syntax: %d file(s) with errors" % len(errors))
            for e in errors:
                print("    " + e)
        else:
            print("  Syntax: %d files OK" % len(files))

        count = error_count(game, folder)
        if count is None:
            print("  Saved errors: could not read")
        else:
            print("  Saved errors: %d%s" % (count, " (python tools/read_errors.py %s)" % folder if count else ""))

        namespaced, globals_ = api_calls(files)
        print("  API (C_*): " + (", ".join(namespaced) or "none"))
        print("  API (global): " + (", ".join(globals_) or "none"))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
