#!/usr/bin/env python3
"""Adaptive installer for one widget: puts the iOS icon into a widget file without relying on exact context lines.

`patches/*.patch` are exact diffs against Omarchy 4.0.4 and stop applying as soon as a nearby line changes in another
Omarchy build. This script does the same edit structurally instead: it finds the widget's BarIconButton block by its `id`,
replaces that block's `text:` binding with an `iconComponent`, and adds the import. It tolerates unrelated changes
anywhere else in the file.

  apply-widget.py WIDGET FILE [--dry-run]     WIDGET: network bluetooth audio monitor agents tray weather
Exit status: 0 patched / already patched / would patch, 1 anchors not found, 2 usage error.
"""
import re
import sys

# block_id: the `id:` of the BarIconButton to edit. component: the icon definition (indented later).
SPECS = {
    "network": dict(block_id="button", component='''\
// iOS-style Wi-Fi fan (bars follow signal strength), ethernet port, or a slashed fan when offline.
iconComponent: Component {
  IosIcon {
    kind: root.kind === "ethernet" ? "ethernet" : "wifi"
    level: root.signalStrength >= 0 ? root.signalStrength / 100 : 0
    slashed: root.kind === "disconnected"
    color: button.foreground
  }
}'''),
    "bluetooth": dict(block_id="button", component='''\
// iOS-style bluetooth rune: slashed when the adapter is off, accent-coloured while a device is connected.
iconComponent: Component {
  IosIcon {
    kind: "bluetooth"
    slashed: !!root.adapter && !root.adapter.enabled
    color: root.connectedDevices.length > 0 ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
  }
}'''),
    "audio": dict(block_id="button", component='''\
// iOS-style speaker: waves follow the volume, an x when muted, headphones when the sink is a headset.
iconComponent: Component {
  IosIcon {
    visible: !!(root.sink && root.sink.audio)
    kind: root.isHeadphones(root.sink) ? "headphones" : "volume"
    level: root.outputVolume
    muted: root.outputMuted
    color: button.foreground
  }
}'''),
    "monitor": dict(block_id="button", component='''\
iconComponent: Component { IosIcon { kind: "display"; color: button.foreground } }'''),
    "agents": dict(block_id="button", component='''\
iconComponent: Component {
  IosIcon { kind: "robot"; color: button.active && button.useActiveColor ? button.activeColor : button.foreground }
}'''),
    "tray": dict(block_id="expandIcon", component='''\
iconComponent: Component { IosIcon { kind: "chevronLeft"; color: expandIcon.foreground } }'''),
    "weather": dict(block_id="button", extra_imports=['import "Model.js" as Model'], prelude='''\
// Which drawn icon to show: match the widget's own weather glyph back to its weather code.
readonly property string weatherKind: {
  var label = panelLoader.item ? panelLoader.item.label : ""
  var table = [[113, false, "sun"], [113, true, "moon"], [116, false, "partlySun"], [116, true, "partlyMoon"],
               [119, false, "cloud"], [143, false, "fog"], [143, true, "fog"], [200, false, "storm"],
               [176, false, "rain"], [176, true, "rain"], [266, false, "rain"], [182, false, "sleet"],
               [179, false, "snow"], [179, true, "snow"], [329, false, "snow"]]
  for (var i = 0; i < table.length; i++)
    if (Model.iconForCode(table[i][0], table[i][1]) === label) return table[i][2]
  return "cloud"
}
''', component='''\
iconComponent: Component { IosIcon { kind: root.weatherKind; color: button.foreground } }'''),
}

IMPORT_KIT = 'import "../ioskit"'


def block_span(src, block_id):
    """(start, end) of the `BarIconButton { ... }` whose direct properties include `id: <block_id>`."""
    for m in re.finditer(r"\bBarIconButton\s*\{", src):
        depth, i = 0, m.end() - 1
        while i < len(src):
            c = src[i]
            depth += (c == "{") - (c == "}")
            if depth == 0:
                break
            i += 1
        body = src[m.end():i]
        # only look at direct properties (depth 0 inside the block)
        d, direct, line_start = 0, [], 0
        for j, ch in enumerate(body):
            if ch == "{":
                d += 1
            elif ch == "}":
                d -= 1
            if d == 0 and ch == "\n":
                direct.append(body[line_start:j]); line_start = j + 1
        if any(re.match(r"\s*id:\s*" + re.escape(block_id) + r"\s*$", ln) for ln in direct):
            return m.start(), i + 1, m.end()
    return None


def text_line_span(src, start, end):
    """Character span of the block's own (top-level) `text:` binding, following simple multi-line expressions."""
    depth, pos = 0, start
    lines = src[start:end].split("\n")
    offset = start
    for idx, ln in enumerate(lines):
        line_depth = depth
        if line_depth == 0 and re.match(r"\s*text:\s*\S", ln):
            s, e, j = offset, offset + len(ln), idx
            expr = ln
            while True:
                stripped = expr.rstrip()
                opens = stripped.count("(") - stripped.count(")") + stripped.count("[") - stripped.count("]")
                nxt = lines[j + 1] if j + 1 < len(lines) else ""
                cont = stripped.endswith(("?", ":", "&&", "||", "+", ",", "(")) or opens > 0 or \
                    re.match(r"\s*(\?|:|&&|\|\||\+)", nxt)
                if not cont or j + 1 >= len(lines):
                    break
                j += 1
                e += 1 + len(lines[j])
                expr += "\n" + lines[j]
            return s, e
        depth += ln.count("{") - ln.count("}")
        offset += len(ln) + 1
    return None


def indent_of(line):
    return re.match(r"\s*", line).group(0)


def patch(src, spec):
    span = block_span(src, spec["block_id"])
    if not span:
        return None, "could not find the BarIconButton with id: %s" % spec["block_id"]
    b_start, b_end, body_start = span
    t = text_line_span(src, body_start, b_end)
    if not t:
        return None, "could not find the button's text: binding"
    t_start, t_end = t
    ind = indent_of(src[t_start:t_end])
    comp = "\n".join((ind + ln) if ln else ln for ln in spec["component"].split("\n"))
    new_text = ind + 'text: ""\n' + comp
    out = src[:t_start] + new_text + src[t_end:]
    if "prelude" in spec:
        line_start = out.rfind("\n", 0, b_start) + 1
        block_ind = indent_of(out[line_start:b_start])
        pre = "\n".join((block_ind + ln) if ln else ln for ln in spec["prelude"].split("\n"))
        out = out[:line_start] + pre + "\n" + out[line_start:]
    imports = [IMPORT_KIT] + spec.get("extra_imports", [])
    have = set(re.findall(r"^import .*$", out, re.M))
    add = [i for i in imports if i not in have]
    if add:
        last = None
        for m in re.finditer(r"^import qs\..*$", out, re.M):
            last = m
        if last is None:
            for m in re.finditer(r"^import .*$", out, re.M):
                last = m
        if last is None:
            return None, "no import lines found"
        out = out[:last.end()] + "\n" + "\n".join(add) + out[last.end():]
    return out, None


def main(argv):
    if len(argv) < 3 or argv[1] not in SPECS:
        print(__doc__); return 2
    widget, path, dry = argv[1], argv[2], "--dry-run" in argv
    src = open(path, encoding="utf-8").read()
    if "IosIcon" in src:
        print("already patched: %s" % path); return 0
    out, err = patch(src, SPECS[widget])
    if err:
        print("%s: %s" % (path, err), file=sys.stderr); return 1
    if dry:
        print("would patch: %s" % path); return 0
    open(path, "w", encoding="utf-8").write(out)
    print("patched: %s" % path); return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
