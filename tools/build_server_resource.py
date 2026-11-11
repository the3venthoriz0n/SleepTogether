"""Generate package/Server/strpm-chat-relay from the vendored upstream relay.

Run from the repo root: python -I tools/build_server_resource.py
"""
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
UPSTREAM = ROOT / "server" / "upstream" / "strpm-chat-relay"
SRC = ROOT / "server" / "sleeptogether"
OUT = ROOT / "package" / "Server" / "strpm-chat-relay"
MANIFEST = "strpm-chat-relay.manifest"

ANCHOR_A = "local playerManager = PlayerManager:get()\n"
ANCHOR_B = 'local flags = tonumber(fields["flags"]) or 0\n'


def read(path):
    return path.read_bytes().decode("utf-8").replace("\r\n", "\n")


def insert_after(text, anchor, addition):
    if text.count(anchor) != 1:
        raise SystemExit("anchor must occur exactly once: %r (found %d)" % (anchor, text.count(anchor)))
    return text.replace(anchor, anchor + addition)


def main():
    relay = read(UPSTREAM / "main.lua")
    logic = read(SRC / "logic.lua")
    handler = read(SRC / "handler.lua")

    embed = (
        "\n-- Sleep Together (embedded; sources: server/sleeptogether/logic.lua, handler.lua)\n"
        "local SleepTogetherLogic = (function()\n" + logic + "\nend)()\n"
        "local SleepTogetherHandler = (function()\n" + handler + "\nend)()"
        "(SleepTogetherLogic, gameServer, playerManager)\n\n"
    )
    call = "  pcall(SleepTogetherHandler, player, fields, message) -- Sleep Together\n"

    relay = insert_after(relay, ANCHOR_A, embed)
    relay = insert_after(relay, "  " + ANCHOR_B, call)

    version = "unknown"
    for line in read(UPSTREAM / MANIFEST).splitlines():
        if line.strip().startswith("version"):
            version = line.split("=", 1)[1].strip()
    header = (
        "-- GENERATED FILE: do not edit. Built by tools/build_server_resource.py from the\n"
        "-- upstream strpm-chat-relay %s (server/upstream/strpm-chat-relay/main.lua) plus\n"
        "-- server/sleeptogether/{logic,handler}.lua. Edit those sources, not this output.\n\n"
        % version
    )

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "main.lua").write_bytes((header + relay).encode("utf-8"))
    shutil.copyfile(UPSTREAM / MANIFEST, OUT / MANIFEST)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
