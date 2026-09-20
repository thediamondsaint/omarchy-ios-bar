#!/usr/bin/env python3
"""Put the iOS icon into one Omarchy bar widget, structurally.

This is the single source of truth for what the icons change: `patches/*.patch` are generated from
this script against Omarchy 4.0.4 (see tools/make-patches.sh) and the installer falls back to this
script whenever your Omarchy's copy of a widget differs from that one.

The edit is done by structure, not by context lines: find the widget's BarIconButton block by its
`id`, replace that block's `text:` binding with an `iconComponent`, insert whatever the icon needs
above the block, and add any missing import. Unrelated changes anywhere else in the file are fine.

  apply-widget.py WIDGET FILE [--dry-run] [--print]
  WIDGET: power network bluetooth audio monitor agents tray weather

Exit status: 0 patched / already patched / would patch, 1 the file does not fit, 2 usage error.
"""
import os
import re
import sys

# The battery is drawn from the widget's own state, so it needs a block of definitions above the button.
POWER_PRELUDE = '''\
// ---- iPhone-style battery -------------------------------------------------
// Same visual height as the other bar icons; ~2:1 like a phone battery.
// Bar icon sizes; fall back to Omarchy 4.0.4's values if a newer Omarchy renames them.
readonly property real barCanvas: (Style.bar && Style.bar.iconCanvas) ? Style.bar.iconCanvas : 19
readonly property real barSlot: (Style.bar && Style.bar.iconSlot) ? Style.bar.iconSlot : 27
readonly property real bodyH: barCanvas * 0.70
readonly property real bodyW: bodyH * 1.9
readonly property real nubW: Math.max(1.5, bodyH * 0.11)
readonly property real iphoneW: bodyW + nubW + Style.space(1)
readonly property bool pluggedIn: batteryPresent && !discharging
// Charging colour comes from the theme's `green` (colors.toml); falls back to the accent colour.
property string themeGreen: ""
readonly property color chargeColor: themeGreen !== "" ? themeGreen : Color.accent
FileView {
  id: themeColorsFile
  path: Color.currentThemePath + "/colors.toml"
  watchChanges: false
  printErrors: false
  onLoaded: {
    var m = text().match(/^\\s*green\\s*=\\s*["']?(#[0-9A-Fa-f]{6})/m)
    root.themeGreen = m ? m[1] : ""
  }
}
// Re-read after a theme switch (the shell updates these when the palette changes).
Connections {
  target: Color
  function onAccentChanged() { themeColorsFile.reload() }
  function onBackgroundChanged() { themeColorsFile.reload() }
  function onForegroundChanged() { themeColorsFile.reload() }
}
// Green while plugged in, red at 20% or less on battery, otherwise the bar's foreground colour.
readonly property color iphoneFill: (charging || (batteryFull && pluggedIn)) ? chargeColor
                                  : (discharging && batteryFraction <= 0.2) ? Color.urgent
                                  : batteryFillColor
function contrastOn(c) {
  return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#101012" : "#ffffff"
}

// The neighbouring icons are text glyphs, whose ink sits a bit below the geometric centre of their
// canvas. Measured on the bar: ~0.19 x the icon canvas. Nudge the drawn battery down to line up.
readonly property real glyphInkDrop: barCanvas * 0.19

// Charge bolt (while charging) + percentage number.
component BatteryLabel: Row {
  property color tint: "white"
  spacing: Style.space(1)
  Text {
    visible: root.charging
    anchors.verticalCenter: parent.verticalCenter
    text: String.fromCodePoint(0xF0E7)
    color: parent.tint
    font.family: Style.font.family
    font.pixelSize: root.bodyH * 0.55
  }
  Text {
    visible: root.showPercentage
    anchors.verticalCenter: parent.verticalCenter
    text: Math.round(root.batteryFraction * 100)
    color: parent.tint
    font.family: Style.font.family
    font.pixelSize: root.bodyH * 0.68
    font.bold: true
  }
}

component IphoneBattery: Item {
  id: ib
  width: root.iphoneW
  height: root.bodyH
  anchors.centerIn: parent
  anchors.verticalCenterOffset: root.glyphInkDrop
  readonly property real inset: Math.max(1, root.bodyH * 0.10)
  readonly property real innerW: root.bodyW - 2 * inset
  readonly property real innerH: root.bodyH - 2 * inset
  readonly property real fillW: root.batteryFraction <= 0 ? 0 : Math.max(innerH, innerW * root.batteryFraction)

  Rectangle {  // body outline
    width: root.bodyW
    height: root.bodyH
    radius: root.bodyH * 0.30
    color: "transparent"
    border.width: Math.max(1, root.bodyH * 0.09)
    border.color: Util.alpha(root.batteryFillColor, 0.42)
  }
  Rectangle {  // terminal nub
    x: root.bodyW + 0.5
    y: (root.bodyH - height) / 2
    width: root.nubW
    height: root.bodyH * 0.38
    radius: width
    color: Util.alpha(root.batteryFillColor, 0.42)
  }
  Item {
    id: inner
    x: ib.inset
    y: ib.inset
    width: ib.innerW
    height: ib.innerH

    Rectangle {  // charge level
      width: ib.fillW
      height: parent.height
      radius: root.bodyH * 0.22
      color: root.iphoneFill
      Behavior on width { NumberAnimation { duration: 200 } }
    }
    Item {  // label over the empty part
      x: ib.fillW
      width: inner.width - ib.fillW
      height: inner.height
      clip: true
      Item {
        x: -ib.fillW
        width: inner.width
        height: inner.height
        BatteryLabel { anchors.centerIn: parent; tint: root.batteryFillColor }
      }
    }
    Item {  // label over the filled part (contrasting colour)
      width: ib.fillW
      height: inner.height
      clip: true
      Item {
        width: inner.width
        height: inner.height
        BatteryLabel { anchors.centerIn: parent; tint: root.contrastOn(root.iphoneFill) }
      }
    }
  }
}
Component { id: iphoneBattery; IphoneBattery {} }
'''

# block_id:  the `id:` of the BarIconButton to edit.
# icon:      what the button's `iconComponent` becomes (indented to the button's body).
# prelude:   inserted just above the button block (same indent), for anything the icon needs.
# props:     other bindings of the button to replace, {name: new value}.
# lines:     file-wide single-line replacements, [(match regex, replacement)]; missed lines are not an error.
# imports:   imports to add if the file does not have them.
# needs:     regexes the file must contain, else this widget is left alone (a missing symbol here would
#            mean an icon that cannot show the right thing).
# needs_file: files that must sit next to the widget (imported by the prelude/icon).
#
# Every binding reads defensively: where a property of an older/newer Omarchy may be missing, the icon
# falls back to a sensible visible state rather than to a blank slot in the bar.
SPECS = {
    "power": dict(
        block_id="button",
        prelude=POWER_PRELUDE,
        text='vertical ? root.batteryIcon() : ""',
        icon="vertical ? null : iphoneBattery",
        props={"slotSize": "vertical ? barSlot : Math.max(barSlot, root.iphoneW + (barSlot - barCanvas))"},
        lines=[(r"^(\s*)readonly property bool showPercentage:.*$",
                r'\1readonly property bool showPercentage: setting("showPercentage", true) === true'),
               (r"^(\s*)readonly property real openPanelIndicatorWidth:.*$",
                r"\1readonly property real openPanelIndicatorWidth: !button.vertical ? root.iphoneW : 0")],
        imports=["import Quickshell.Io", "import qs.Commons"],
        needs=[(r"property .*\bbatteryFraction\b", "a batteryFraction property"),
               (r"function batteryIcon\b", "a batteryIcon() function"),
               (r"property .*\bbatteryFillColor\b", "a batteryFillColor property"),
               (r"property .*\bcharging\b", "a charging property"),
               (r"property .*\bdischarging\b", "a discharging property")],
        marker="iphoneFill",
        kit=False,
    ),
    "network": dict(
        block_id="button",
        icon='''\
Component {
  // iOS-style Wi-Fi fan (bars follow signal strength), ethernet port, or a slashed fan when offline.
  IosIcon {
    kind: root.kind === "ethernet" ? "ethernet" : "wifi"
    level: root.signalStrength === undefined ? 1 : (root.signalStrength >= 0 ? root.signalStrength / 100 : 0)
    slashed: root.kind === "disconnected"
    color: button.active && button.useActiveColor ? button.activeColor : button.foreground
  }
}''',
        imports=["import qs.Commons"],
    ),
    "bluetooth": dict(
        block_id="button",
        icon='''\
Component {
  // iOS-style bluetooth rune: slashed when the adapter is off, accent-coloured while a device is connected.
  IosIcon {
    kind: "bluetooth"
    slashed: !!root.adapter && !root.adapter.enabled
    color: (root.connectedDevices && root.connectedDevices.length > 0) ? Color.accent
         : (root.bar ? root.bar.foreground : Color.foreground)
  }
}''',
        imports=["import qs.Commons"],
    ),
    "audio": dict(
        block_id="button",
        # Mirror the stock widget: with no output device the stock glyph is empty and the button
        # collapses, so the icon has to disappear with it instead of leaving a blank slot.
        prelude='''\
// iOS-style speaker: waves follow the volume, an x when muted, headphones when the sink is a headset.
readonly property bool iosHasOutput: root.sink === undefined ? true : !!(root.sink && root.sink.audio)
Component {
  id: iosAudioIcon
  IosIcon {
    kind: (root.isHeadphones && root.sink && root.isHeadphones(root.sink)) ? "headphones" : "volume"
    level: root.outputVolume === undefined ? 1 : root.outputVolume
    muted: !!root.outputMuted
    color: button.foreground
  }
}
''',
        icon="root.iosHasOutput ? iosAudioIcon : null",
        imports=["import qs.Commons"],
    ),
    "monitor": dict(
        block_id="button",
        icon='Component { IosIcon { kind: "display"; color: button.foreground } }',
        imports=["import qs.Commons"],
    ),
    "agents": dict(
        block_id="button",
        icon='''\
Component {
  IosIcon { kind: "robot"; color: button.active && button.useActiveColor ? button.activeColor : button.foreground }
}''',
        imports=["import qs.Commons"],
    ),
    "tray": dict(
        # The tray has one of these for a horizontal bar and one for a vertical bar; both get the icon,
        # and the vertical one turns with the glyph it replaces (BarIconButton.textRotation).
        block_id="expandIcon",
        icon='Component { IosIcon { kind: "chevronLeft"; color: expandIcon.foreground; rotation: expandIcon.textRotation || 0 } }',
        imports=["import qs.Commons"],
    ),
    "weather": dict(
        block_id="button",
        prelude='''\
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
''',
        icon='Component { IosIcon { kind: root.weatherKind; color: button.foreground } }',
        imports=['import "Model.js" as Model', "import qs.Commons"],
        needs=[(r"\bpanelLoader\b", "the panelLoader that holds the weather label")],
        needs_file=[("Model.js", r"function iconForCode\b", "an iconForCode() function")],
    ),
}

for _w, _s in SPECS.items():
    _s.setdefault("marker", "IosIcon")
    _s.setdefault("kit", True)       # needs IosIcon.qml next to it
    _s.setdefault("text", '""')
    _s.setdefault("prelude", None)
    _s.setdefault("props", {})
    _s.setdefault("lines", [])
    _s.setdefault("needs", [])
    _s.setdefault("needs_file", [])


class Unfit(Exception):
    """This widget file is not shaped the way the icon needs."""


def block_spans(src, block_id):
    """Every `BarIconButton { ... }` whose direct properties include `id: <block_id>`, as (start, end, body_start).

    A widget can hold more than one: the tray has one button for a horizontal bar and one for a
    vertical bar, and both have to get the icon or a side bar keeps the old glyph.
    """
    found = []
    for m in re.finditer(r"\bBarIconButton\s*\{", src):
        depth, i = 0, m.end() - 1
        while i < len(src):
            depth += (src[i] == "{") - (src[i] == "}")
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
                direct.append(body[line_start:j])
                line_start = j + 1
        if any(re.match(r"\s*id:\s*" + re.escape(block_id) + r"\s*$", ln) for ln in direct):
            found.append((m.start(), i + 1, m.end()))
    return found


def block_span(src, block_id):
    """The first such block, or None."""
    found = block_spans(src, block_id)
    return found[0] if found else None


def prop_span(src, start, end, name):
    """Character span of the block's own (top-level) `<name>:` binding, following simple multi-line expressions."""
    depth, offset = 0, start
    lines = src[start:end].split("\n")
    for idx, ln in enumerate(lines):
        if depth == 0 and re.match(r"\s*" + re.escape(name) + r":\s*\S", ln):
            s, e, j, expr = offset, offset + len(ln), idx, ln
            while j + 1 < len(lines):
                stripped = expr.rstrip()
                opens = stripped.count("(") - stripped.count(")") + stripped.count("[") - stripped.count("]")
                nxt = lines[j + 1]
                if not (stripped.endswith(("?", ":", "&&", "||", "+", ",", "(")) or opens > 0
                        or re.match(r"\s*(\?|:|&&|\|\||\+)", nxt)):
                    break
                j += 1
                e += 1 + len(lines[j])
                expr += "\n" + lines[j]
            return s, e
        depth += ln.count("{") - ln.count("}")
        offset += len(ln) + 1
    return None


def indent_of(text):
    return re.match(r"\s*", text).group(0)


def reindent(text, ind):
    return "\n".join((ind + ln) if ln.strip() else ln for ln in text.split("\n"))


def check_fit(src, path, spec):
    for pattern, what in spec["needs"]:
        if not re.search(pattern, src):
            raise Unfit("this Omarchy's widget has no %s" % what)
    folder = os.path.dirname(os.path.abspath(path))
    for name, pattern, what in spec["needs_file"]:
        sibling = os.path.join(folder, name)
        if not os.path.exists(sibling):
            raise Unfit("%s is not next to the widget" % name)
        if pattern and not re.search(pattern, open(sibling, encoding="utf-8").read()):
            raise Unfit("%s has no %s" % (name, what))


def add_imports(src, imports):
    have = set(re.findall(r"^import .*$", src, re.M))
    add = [i for i in imports if i not in have]
    if not add:
        return src
    last = None
    for m in re.finditer(r"^import .*$", src, re.M):
        last = m
    if last is None:
        raise Unfit("the file has no import lines")
    return src[:last.end()] + "\n" + "\n".join(add) + src[last.end():]


def patch_block(out, spec, index):
    """Put the icon into the index-th matching button of `out` and return the new text."""
    b_start, b_end, body_start = block_spans(out, spec["block_id"])[index]
    t = prop_span(out, body_start, b_end, "text")
    if not t:
        raise Unfit("the button has no text: binding")
    t_start, t_end = t
    ind = indent_of(out[t_start:t_end])
    out = out[:t_start] + ind + "text: " + spec["text"] + "\n" + \
        ind + "iconComponent: " + reindent(spec["icon"], ind).lstrip() + out[t_end:]

    # other bindings of the same button (e.g. the battery's wider slot)
    for name, value in spec["props"].items():
        b_start, b_end, body_start = block_spans(out, spec["block_id"])[index]
        p = prop_span(out, body_start, b_end, name)
        if p:
            out = out[:p[0]] + indent_of(out[p[0]:p[1]]) + name + ": " + value + out[p[1]:]
        else:
            out = out[:body_start] + "\n" + ind + name + ": " + value + out[body_start:]
    return out


def patch(src, path, spec):
    blocks = block_spans(src, spec["block_id"])
    if not blocks:
        raise Unfit("no BarIconButton with id: %s" % spec["block_id"])
    check_fit(src, path, spec)

    out = src
    for index in range(len(blocks)):
        out = patch_block(out, spec, index)

    if spec["prelude"]:
        b_start = block_spans(out, spec["block_id"])[0][0]
        line_start = out.rfind("\n", 0, b_start) + 1
        out = out[:line_start] + reindent(spec["prelude"], indent_of(out[line_start:b_start])) + "\n" + out[line_start:]

    for pattern, replacement in spec["lines"]:
        out = re.sub(pattern, replacement, out, count=1, flags=re.M)

    return add_imports(out, spec["imports"])


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = [a for a in argv[1:] if a.startswith("--")]
    if len(args) != 2 or args[0] not in SPECS:
        print(__doc__)
        return 2
    widget, path = args
    spec = SPECS[widget]
    src = open(path, encoding="utf-8").read()
    if spec["marker"] in src:
        print("already patched: %s" % path)
        return 0
    try:
        out = patch(src, path, spec)
    except Unfit as e:
        print("%s: %s" % (path, e), file=sys.stderr)
        return 1
    if "--print" in flags:
        sys.stdout.write(out)
        return 0
    if "--dry-run" in flags:
        print("would patch: %s" % path)
        return 0
    open(path, "w", encoding="utf-8").write(out)
    print("patched: %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
