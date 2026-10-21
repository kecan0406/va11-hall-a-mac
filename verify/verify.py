import argparse
import hashlib
import json
import os
import platform
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
LAUNCHER = REPO / "app" / "launcher.sh"
DATA_DIR = Path.home() / "Library" / "Application Support" / "VA-11 Hall-A"
sys.path.insert(0, str(HERE))
import scenario as scenario_compiler  # noqa: E402

CRITERIA = [
    ("audit", "Every function the game references that the runner doesn't implement, and that a game event can reach, is listed in allowlist.json with its player-visible effect."),
    ("audio", "Every embedded sound decodes to non-silent audio with the runner's own decoding path."),
    ("scenarios", "Per run: exit code 0, no error lines, no warning outside the allowlist, expected room sequence. Per scenario: two replays give identical rooms and byte-identical screenshots. If a baseline exists for this machine and runner build, screenshots equal it."),
    ("roundtrip", "Replaying a scenario while re-recording it reproduces the same mouse events on the same frames."),
]

ENTRY_UNIT = re.compile(r"^(gml_Object_|gml_Room|.*initialize_detail$)")
ERROR_LINE = re.compile(r"\b(error|fatal|assert|segmentation|segfault|failed|crash)", re.I)
DEMUX_BLOCK = re.compile(r"typedef struct \{\s*const AudioEntry\* entry;.*?(?=// ===\[ Helpers \]===)", re.S)


class Report:
    def __init__(self):
        self.sections = []

    def add(self, title, status, lines):
        self.sections.append((title, status, lines))
        print("[%s] %s" % (status, title))
        for line in lines:
            print("      " + line)

    @property
    def failed(self):
        return any(status == "FAIL" for _, status, _ in self.sections)

    def markdown(self, meta):
        out = ["# Verification report", ""]
        out += ["- %s: %s" % (k, v) for k, v in meta.items()]
        out += ["", "## Criteria (fixed before running)", ""]
        out += ["- **%s**: %s" % c for c in CRITERIA]
        out += ["", "## Results", ""]
        for title, status, lines in self.sections:
            out.append("### %s: %s" % (title, status))
            out += [""] + ["- " + l for l in lines] + [""]
        return "\n".join(out)


def run_logged(cmd, timeout):
    master, slave = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)
    chunks, deadline, timed_out = [], time.time() + timeout, False
    while True:
        ready, _, _ = select.select([master], [], [], 0.25)
        if ready:
            try:
                data = os.read(master, 65536)
            except OSError:
                data = b""
            if not data:
                break
            chunks.append(data)
        elif proc.poll() is not None:
            break
        if time.time() > deadline:
            proc.kill()
            timed_out = True
            break
    proc.wait()
    os.close(master)
    text = b"".join(chunks).decode("utf-8", "replace").replace("\r", "")
    return proc.returncode, text, timed_out


def run_plain(cmd, timeout=300):
    done = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    return done.stdout.decode("utf-8", "replace") + done.stderr.decode("utf-8", "replace")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare_sandbox(ctx):
    sandbox = Path(tempfile.mkdtemp(prefix="va11-verify-"))
    env = dict(
        os.environ,
        VA11_DATA_DIR=str(sandbox),
        VA11_STEAM_RESOURCES=str(ctx.steam_resources),
        VA11_OVERRIDES=str(ctx.overrides) if ctx.overrides else str(sandbox / "overrides"),
        VA11_PREPARE_ONLY="1",
        VA11_NO_DIALOG="1",
    )
    done = subprocess.run([str(LAUNCHER)], env=env, capture_output=True, text=True)
    if done.returncode != 0:
        shutil.rmtree(sandbox, ignore_errors=True)
        raise SystemExit("can't prepare the game folder: " + done.stderr.strip())
    return sandbox, Path(done.stdout.strip().splitlines()[-1])


def parse_disassembly(text):
    calls, callers, unit = {}, {}, None
    for line in text.split("\n"):
        m = re.match(r"=== (\S+) \(length", line)
        if m:
            unit = m.group(1)
            continue
        m = re.match(r"Called by: (.*)", line)
        if m and unit:
            callers[unit] = {c.strip() for c in m.group(1).split(",")}
            continue
        m = re.search(r"Call\.i\s+([A-Za-z0-9_]+)\(", line)
        if m and unit and not m.group(1).startswith("gml_Script_"):
            calls.setdefault(m.group(1), {})
            calls[m.group(1)][unit] = calls[m.group(1)].get(unit, 0) + 1
    return calls, callers


def reachable_entries(units, callers):
    seen, todo, entries = set(), list(units), set()
    while todo:
        unit = todo.pop()
        if unit in seen:
            continue
        seen.add(unit)
        if ENTRY_UNIT.match(unit):
            entries.add(unit)
        todo.extend(callers.get(unit, ()))
    return entries


def audit(ctx, report):
    disasm = run_plain([str(ctx.runner), "--headless", "--disassemble", "*", str(ctx.game)])
    calls, callers = parse_disassembly(disasm)
    out = run_plain([str(ctx.runner), "--headless", "--print-unknown-functions", str(ctx.game)])
    unknown = set(re.findall(r"^- (\S+)$", out, re.M))
    stubs = set()
    vm_builtins = ctx.source / "src" / "vm_builtins.c"
    if vm_builtins.exists():
        stubs = set(re.findall(r"^STUB_[A-Z_]+\(\s*(\w+)", vm_builtins.read_text(), re.M))
    stubbed_used = set(calls) & stubs
    missing = unknown | stubbed_used

    allow = json.loads((HERE / "allowlist.json").read_text())["functions"]
    lines, unexplained, dead = [], [], []
    for name in sorted(missing):
        entries = reachable_entries(calls[name].keys(), callers)
        sites = sum(calls[name].values())
        kind = "unknown" if name in unknown else "stubbed"
        if not entries:
            dead.append(name)
        elif name in allow:
            lines.append("%s (%s, %d call sites, reachable from %d events): %s" % (name, kind, sites, len(entries), allow[name]["note"]))
        else:
            unexplained.append(name)
            lines.append("UNEXPLAINED %s (%s, %d call sites) reachable from %s" % (name, kind, sites, ", ".join(sorted(entries)[:3])))
    stale = sorted(set(allow) - missing)

    total = len(calls)
    sites_total = sum(sum(v.values()) for v in calls.values())
    sites_missing = sum(sum(calls[n].values()) for n in missing)
    lines.insert(0, "referenced functions: %d; implemented %d (%.1f%%); not implemented %d" % (
        total, total - len(missing), 100.0 * (total - len(missing)) / max(total, 1), len(missing)))
    lines.insert(1, "by call sites: %d of %d (%.1f%%) hit an implemented function" % (
        sites_total - sites_missing, sites_total, 100.0 * (sites_total - sites_missing) / max(sites_total, 1)))
    lines.insert(2, "no static path from any game event (dead code, no player-visible effect): %d functions" % len(dead))
    if stale:
        lines.append("allowlist entries no longer needed: " + ", ".join(stale))
    dynamic = sorted(u for n in ("script_execute", "asset_get_index") for u in calls.get(n, {}))
    lines.append("caveat: %d dynamic-dispatch sites (script_execute/asset_get_index) can't be followed statically" % len(set(dynamic)))
    report.add("audit: static function coverage", "FAIL" if unexplained else "PASS", lines)


def dump_audio(game, out_dir):
    with open(game, "rb") as f:
        assert f.read(4) == b"FORM"
        total = struct.unpack("<I", f.read(4))[0]
        pos, audo = 8, None
        while pos < total + 8:
            f.seek(pos)
            name = f.read(4)
            size = struct.unpack("<I", f.read(4))[0]
            if name == b"AUDO":
                audo = pos + 8
                break
            pos += 8 + size
        if audo is None:
            return 0

        def u32(offset):
            f.seek(offset)
            return struct.unpack("<I", f.read(4))[0]

        count = u32(audo)
        for i in range(count):
            offset = u32(audo + 4 + 4 * i)
            size = u32(offset)
            f.seek(offset + 4)
            (out_dir / ("%03d.ogg" % i)).write_bytes(f.read(size))
        return count


def audio(ctx, report):
    source = (ctx.source / "src" / "audio" / "miniaudio" / "ma_audio_system.c").read_text()
    block = DEMUX_BLOCK.search(source)
    if not block:
        report.add("audio: decode every embedded sound", "FAIL", ["can't find the Ogg demuxer in the runner source (patch 0001 not applied?)"])
        return
    work = Path(tempfile.mkdtemp(prefix="va11-audio-"))
    try:
        c_file = work / "audio_check.c"
        c_file.write_text((HERE / "audio_check.c.in").read_text().replace("@DEMUX@", block.group(0)))
        binary = work / "audio_check"
        build = subprocess.run(["cc", "-O1", "-std=gnu2x", "-Wno-everything",
                                "-I" + str(ctx.source / "vendor/stb/ds"), "-I" + str(ctx.source / "vendor/stb/vorbis"),
                                str(c_file), "-o", str(binary), "-lm"], capture_output=True, text=True)
        if build.returncode != 0:
            report.add("audio: decode every embedded sound", "FAIL", ["harness doesn't build: " + build.stderr[-300:]])
            return
        sounds = work / "sounds"
        sounds.mkdir()
        count = dump_audio(ctx.game, sounds)
        files = sorted(str(p) for p in sounds.glob("*.ogg"))
        result = subprocess.run([str(binary)] + files, capture_output=True, text=True)
        total = re.search(r"total=(\d+) mixed=(\d+) bad=(\d+)", result.stdout)
        bad_lines = [l for l in result.stdout.splitlines() if l.startswith("BAD")]
        ok = bool(total) and int(total.group(3)) == 0 and int(total.group(1)) == count and count > 0
        lines = ["%s sounds decoded, %s of them Theora+Vorbis mixed files that need the demuxer, %s failed" % (
            total.group(1), total.group(2), total.group(3)) if total else "no result from the harness"]
        lines += bad_lines[:10]
        report.add("audio: decode every embedded sound", "PASS" if ok else "FAIL", lines)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def parse_scenario(path):
    meta = {"name": path.stem, "shots": [], "debug": False, "roundtrip": False, "rooms": None, "rooms_visit": None,
            "exit": None, "speed": 8, "seed": 1}
    for line in path.read_text().splitlines():
        m = re.match(r"@(\S+)\s*(.*)$", line)
        if not m:
            continue
        key, rest = m.group(1), m.group(2).split()
        if key == "exit":
            meta["exit"] = int(rest[0])
        elif key == "shot":
            meta["shots"].append((int(rest[0]), rest[1] if len(rest) > 1 else rest[0]))
        elif key == "debug":
            meta["debug"] = True
        elif key == "roundtrip":
            meta["roundtrip"] = True
        elif key == "rooms":
            meta["rooms"] = rest
        elif key == "rooms-visit":
            meta["rooms_visit"] = rest
        elif key in ("speed", "seed"):
            meta[key] = int(rest[0])
    if meta["exit"] is None:
        raise SystemExit("%s: missing '@exit <frame>'" % path)
    return meta


def compile_input(scn, out_json):
    Path(out_json).write_text(json.dumps(scenario_compiler.compile_scenario(Path(scn).read_text())))


def play(ctx, meta, scn, work, record_to=None):
    sandbox, game = prepare_sandbox(ctx)
    try:
        inputs = work / "inputs.json"
        compile_input(scn, inputs)
        cmd = [str(ctx.runner), "--playback-inputs", str(inputs), "--seed", str(meta["seed"]), "--speed", str(meta["speed"]),
               "--exit-at-frame", str(meta["exit"]), "--disable-log-colours"]
        if meta["debug"]:
            cmd.append("--debug")
        if record_to:
            cmd += ["--record-inputs", str(record_to)]
        if meta["shots"]:
            cmd += ["--screenshot", str(work / "shot_%d.png")]
            for frame, _ in meta["shots"]:
                cmd += ["--screenshot-at-frame", str(frame)]
        cmd.append(str(game))
        code, log, timed_out = run_logged(cmd, timeout=900)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    rooms = re.findall(r"Room changed: \S+ \(room \d+\) -> (\S+) \(room \d+\)", log)
    warnings = [l for l in log.splitlines() if l.startswith("Warning:")]
    errors = [l for l in log.splitlines() if ERROR_LINE.search(l) and not l.startswith("Warning: VM:")]
    shots = {}
    for frame, label in meta["shots"]:
        png = work / ("shot_%d.png" % frame)
        shots[label] = sha256(png) if png.exists() and png.stat().st_size > 0 else None
    (work / "log.txt").write_text(log)
    return {"code": code, "timed_out": timed_out, "rooms": rooms, "warnings": warnings, "errors": errors, "shots": shots}


def judge_warnings(warnings, allow):
    bad = []
    for w in warnings:
        m = re.search(r'(Unknown|Stubbed) function "(\w+)"', w)
        if m and m.group(2) in allow:
            continue
        bad.append(w)
    return bad


def scenarios(ctx, report, visited_rooms):
    allow = json.loads((HERE / "allowlist.json").read_text())["functions"]
    baseline_file = HERE / "baseline.json"
    baseline = json.loads(baseline_file.read_text()) if baseline_file.exists() else {}
    fingerprint = ctx.fingerprint
    new_baseline = {"fingerprint": fingerprint, "shots": {}}
    use_baseline = baseline.get("fingerprint") == fingerprint and not ctx.update_baseline

    for scn in sorted((HERE / "scenarios").glob("*.scn")):
        meta = parse_scenario(scn)
        if meta["roundtrip"]:
            continue
        runs, lines, failures = [], [], []
        for attempt in (1, 2):
            work = ctx.report_dir / meta["name"] / ("run%d" % attempt)
            work.mkdir(parents=True, exist_ok=True)
            started = time.time()
            runs.append(play(ctx, meta, scn, work))
            r = runs[-1]
            lines.append("run %d: %.0fs, exit %s, %d room changes, %d screenshots" % (
                attempt, time.time() - started, r["code"], len(r["rooms"]), sum(1 for h in r["shots"].values() if h)))
            if r["timed_out"] or r["code"] != 0:
                failures.append("run %d: exit code %s%s" % (attempt, r["code"], " (timed out)" if r["timed_out"] else ""))
            if r["errors"]:
                failures.append("run %d: error lines: %s" % (attempt, " | ".join(r["errors"][:3])))
            for w in judge_warnings(r["warnings"], allow)[:5]:
                failures.append("run %d: unexpected warning: %s" % (attempt, w))
            missing = [label for label, h in r["shots"].items() if not h]
            if missing:
                failures.append("run %d: screenshots missing: %s" % (attempt, ", ".join(missing)))

        first, second = runs
        if meta["rooms"] is not None and first["rooms"] != meta["rooms"]:
            failures.append("room sequence differs: got %s, want %s" % (" ".join(first["rooms"]), " ".join(meta["rooms"])))
        if meta["rooms_visit"] is not None:
            absent = sorted(set(meta["rooms_visit"]) - set(first["rooms"]))
            if absent:
                failures.append("rooms never entered: " + " ".join(absent))
        visited_rooms.update(first["rooms"])

        if first["rooms"] != second["rooms"]:
            failures.append("not deterministic: room sequences differ between runs")
        for label in first["shots"]:
            if first["shots"][label] != second["shots"].get(label):
                failures.append("not deterministic: screenshot '%s' differs between runs" % label)
        if not failures:
            shots = "%d screenshots byte-identical, " % len(first["shots"]) if first["shots"] else ""
            lines.append("deterministic across 2 runs: %sidentical room sequence (%s)" % (
                shots, " > ".join(first["rooms"][:12]) + (" ..." if len(first["rooms"]) > 12 else "")))

        new_baseline["shots"][meta["name"]] = first["shots"]
        if use_baseline and meta["name"] in baseline.get("shots", {}):
            if first["shots"]:
                changed = [l for l, h in first["shots"].items() if baseline["shots"][meta["name"]].get(l) != h]
                if changed:
                    failures.append("differs from baseline: " + ", ".join(changed))
                else:
                    lines.append("matches baseline (%d screenshots)" % len(first["shots"]))
        elif first["shots"] and not ctx.update_baseline:
            lines.append("no baseline for this machine, runner build and game data (run with --update-baseline to record one)")

        report.add("scenario: " + meta["name"], "FAIL" if failures else "PASS", lines + failures)

    if ctx.update_baseline:
        baseline_file.write_text(json.dumps(new_baseline, indent=1))
        print("baseline written: %s" % baseline_file)


def roundtrip(ctx, report):
    for scn in sorted((HERE / "scenarios").glob("*.scn")):
        meta = parse_scenario(scn)
        if not meta["roundtrip"]:
            continue
        work = ctx.report_dir / meta["name"]
        work.mkdir(parents=True, exist_ok=True)
        recorded = work / "recorded.json"
        play(ctx, meta, scn, work, record_to=recorded)
        source = scenario_compiler.compile_scenario(scn.read_text())
        got = json.loads(recorded.read_text()) if recorded.exists() else {}
        problems = []
        for frame, entry in source.items():
            want = entry.get("mouse")
            if not want:
                continue
            have = got.get(frame, {}).get("mouse", {})
            for key in ("x", "y"):
                if key in want and abs(have.get(key, 1e18) - want[key]) > 1e-6:
                    problems.append("frame %s %s: want %s, got %s" % (frame, key, want[key], have.get(key)))
            for key in ("pressed", "released"):
                if want.get(key, []) != have.get(key, []):
                    problems.append("frame %s %s: want %s, got %s" % (frame, key, want.get(key), have.get(key)))
        events = sum(1 for e in source.values() if e.get("mouse"))
        report.add("roundtrip: " + meta["name"], "FAIL" if problems else "PASS",
                   problems or ["%d recorded frames reproduce the %d scripted mouse frames exactly" % (len(got), events)])


class Context:
    pass


def default_steam_resources():
    env = os.environ.get("VA11_STEAM_RESOURCES")
    if env:
        return Path(env)
    link = DATA_DIR / "game.ios"
    if link.exists():
        return link.resolve().parent
    raise SystemExit("can't find the game: run install.sh once, or pass --steam-resources <folder>/Contents/Resources")


def main():
    parser = argparse.ArgumentParser(description="Checks the Butterscotch-based app against your copy of VA-11 Hall-A.")
    parser.add_argument("what", nargs="?", default="all", choices=["all", "audit", "audio", "scenarios", "roundtrip"])
    parser.add_argument("--runner", default=str(REPO / "build" / "dist" / "butterscotch"))
    parser.add_argument("--steam-resources", help="the game's Contents/Resources folder (default: the one the app uses)")
    parser.add_argument("--overrides", help="a folder of overrides to check, like the app's overrides folder")
    parser.add_argument("--source", default=str(REPO / "build" / "butterscotch"), help="patched Butterscotch source tree (for the stub list and decoder)")
    parser.add_argument("--report-dir", default=str(HERE / "report" / "latest"))
    parser.add_argument("--update-baseline", action="store_true", help="record this run's screenshots as the baseline")
    parser.add_argument("--no-gui", action="store_true", help="skip the checks that open the game window")
    args = parser.parse_args()

    ctx = Context()
    ctx.runner = Path(args.runner)
    ctx.steam_resources = Path(args.steam_resources) if args.steam_resources else default_steam_resources()
    ctx.overrides = Path(args.overrides) if args.overrides else None
    ctx.source = Path(args.source)
    ctx.update_baseline = args.update_baseline
    ctx.report_dir = Path(args.report_dir)
    if not ctx.runner.exists():
        raise SystemExit("runner not found: %s (install first with install.sh (or ./build.sh), or pass --runner)" % ctx.runner)
    if not (ctx.steam_resources / "game.ios").exists():
        raise SystemExit("game.ios not found in %s" % ctx.steam_resources)
    shutil.rmtree(ctx.report_dir, ignore_errors=True)
    ctx.report_dir.mkdir(parents=True)

    base_sandbox, ctx.game = prepare_sandbox(ctx)
    mac = platform.mac_ver()[0]
    ctx.fingerprint = "macOS %s|%s|runner %s|game %s" % (mac, platform.machine(), sha256(ctx.runner)[:10], sha256(ctx.game)[:10])

    print("Criteria (fixed before running):")
    for name, text in CRITERIA:
        print("  %-10s %s" % (name, text))
    print()

    report = Report()
    visited = {"languageselect"}
    wants = (args.what,) if args.what != "all" else ("audit", "audio", "scenarios", "roundtrip")
    started = time.time()
    try:
        if "audit" in wants:
            audit(ctx, report)
        if "audio" in wants:
            audio(ctx, report)
        if args.no_gui:
            report.add("scenarios and roundtrip", "SKIP", ["--no-gui: these open the game window"])
        else:
            if "scenarios" in wants:
                scenarios(ctx, report, visited)
                rooms_out = run_plain([str(ctx.runner), "--headless", "--print-rooms", str(ctx.game)])
                all_rooms = re.findall(r"^\[\d+\] (\S+)", rooms_out, re.M)
                absent = [r for r in all_rooms if r not in visited]
                report.add("room coverage", "INFO", ["%d of %d rooms entered by the scenarios" % (len(all_rooms) - len(absent), len(all_rooms)),
                                                      "not entered: " + (" ".join(absent) or "none")])
            if "roundtrip" in wants:
                roundtrip(ctx, report)
    finally:
        shutil.rmtree(base_sandbox, ignore_errors=True)

    meta = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "machine": ctx.fingerprint, "took": "%.0fs" % (time.time() - started)}
    if ctx.overrides:
        meta["overrides"] = str(ctx.overrides)
    (ctx.report_dir / "report.md").write_text(report.markdown(meta))
    print("\n%s. Report: %s" % ("FAILED" if report.failed else "All checks passed", ctx.report_dir / "report.md"))
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
