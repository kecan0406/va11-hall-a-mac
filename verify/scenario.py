import json
import sys

KEYS = {
    "enter": 13, "space": 32, "esc": 27, "tab": 9, "backspace": 8,
    "left": 37, "up": 38, "right": 39, "down": 40,
    "pageup": 33, "pagedown": 34,
    "shift": 16, "ctrl": 17, "alt": 18,
}
KEYS.update({"f%d" % n: 111 + n for n in range(1, 13)})
BUTTONS = {"left": 1, "right": 2, "middle": 3}
HOLD_FRAMES = 3


def key_code(name):
    if name in KEYS:
        return KEYS[name]
    if len(name) == 1 and name.isalnum():
        return ord(name.upper())
    raise ValueError("unknown key: " + name)


def expand_frames(token):
    if ".." not in token:
        return [int(token)]
    span, _, step = token.partition("/")
    first, _, last = span.partition("..")
    return list(range(int(first), int(last) + 1, int(step or 1)))


def compile_scenario(text):
    frames = {}

    def frame(n):
        return frames.setdefault(n, {"keysPressed": [], "keysReleased": []})

    def mouse(n):
        return frame(n).setdefault("mouse", {"pressed": [], "released": []})

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("@"):
            continue
        parts = line.split()
        try:
            action, args = parts[1], parts[2:]
            for n in expand_frames(parts[0]):
                if action == "move":
                    m = mouse(n)
                    m["x"], m["y"] = float(args[0]), float(args[1])
                elif action == "click":
                    button = BUTTONS[args[0] if args else "left"]
                    mouse(n)["pressed"].append(button)
                    mouse(n + HOLD_FRAMES)["released"].append(button)
                elif action == "warp":
                    frame(n)["warp"] = args[0]
                elif action == "key":
                    for code in [key_code(name) for name in args[0].split("+")]:
                        frame(n)["keysPressed"].append(code)
                        frame(n + HOLD_FRAMES)["keysReleased"].append(code)
                else:
                    raise ValueError("unknown action: " + action)
        except (IndexError, KeyError, ValueError) as e:
            raise SystemExit("scenario line %d: %s (%s)" % (lineno, raw.strip(), e))

    start = mouse(0)
    start.setdefault("x", 0.0)
    start.setdefault("y", 0.0)

    return {str(n): frames[n] for n in sorted(frames)}


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: scenario.py <scenario.scn> <out.json>")
    with open(sys.argv[1]) as f:
        recording = compile_scenario(f.read())
    with open(sys.argv[2], "w") as f:
        json.dump(recording, f, indent=1)
    print("wrote %s (%d frames with input)" % (sys.argv[2], len(recording)))


if __name__ == "__main__":
    main()
