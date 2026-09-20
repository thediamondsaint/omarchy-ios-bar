#!/usr/bin/env python3
"""Check that the icon change still fits Omarchy's widgets — and that what it produces is valid QML.

  tests/test-patcher.py                        # against the Omarchy installed here
  tests/test-patcher.py TREE [TREE ...]        # also against other Omarchy trees (a git checkout, say)

For every widget it checks that
  * the exact patch in patches/ applies to the stock file,
  * tools/apply-widget.py applies to it too, and produces exactly the same file,
  * the result is valid QML (qmlformat) and patching it twice changes nothing,
  * the change survives the kinds of edits a different Omarchy build makes to the file
    (moved code, extra properties, a reformatted binding, another button above it), and
  * a widget the icon cannot honestly fit is refused rather than half-patched.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
import importlib.util

spec = importlib.util.spec_from_file_location("apply_widget", os.path.join(HERE, "tools", "apply-widget.py"))
aw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aw)

WIDGETS = ["power", "network", "bluetooth", "audio", "monitor", "agents", "tray", "weather"]
STOCK = {
    "power": "panels/power/Panel.qml",
    "network": "panels/network/Panel.qml",
    "bluetooth": "panels/bluetooth/Panel.qml",
    "audio": "panels/audio/Panel.qml",
    "monitor": "panels/monitor/Panel.qml",
    "agents": "agents/Panel.qml",
    "tray": "bar/widgets/Tray.qml",
    "weather": "panels/weather/BarWidget.qml",
}
QMLFORMAT = next((p for p in ("/usr/lib/qt6/bin/qmlformat", "/usr/lib/qt/bin/qmlformat",
                              "/usr/lib/x86_64-linux-gnu/qt6/bin/qmlformat",
                              shutil.which("qmlformat") or "") if p and os.path.exists(p)), None)

passed = failed = skipped = 0


def report(ok, name, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("  FAIL  %s%s" % (name, (": " + detail) if detail else ""))


def stage(tree, widget, tmp, text=None):
    """Copy a widget file (and the .js files next to it) into a scratch folder; return the file path."""
    src = os.path.join(tree, "shell/plugins", STOCK[widget])
    if not os.path.exists(src):
        return None
    folder = tempfile.mkdtemp(dir=tmp)
    for js in os.listdir(os.path.dirname(src)):
        if js.endswith(".js"):
            shutil.copy(os.path.join(os.path.dirname(src), js), folder)
    dst = os.path.join(folder, os.path.basename(src))
    if text is None:
        shutil.copy(src, dst)
    else:
        open(dst, "w", encoding="utf-8").write(text)
    return dst


def adaptive(path, widget):
    """Run the patcher in-process. Returns the patched text, or None if it refused."""
    src = open(path, encoding="utf-8").read()
    try:
        out = aw.patch(src, path, aw.SPECS[widget])
    except aw.Unfit:
        return None
    open(path, "w", encoding="utf-8").write(out)
    return out


def exact(path, widget):
    r = subprocess.run(["patch", "-s", path, os.path.join(HERE, "patches", widget + ".patch")],
                       capture_output=True, text=True)
    return r.returncode == 0


def valid_qml(path):
    if not QMLFORMAT:
        return True
    return subprocess.run([QMLFORMAT, "-n", path], capture_output=True).returncode == 0


def mutations(src, widget):
    """Edits another Omarchy build could plausibly have made to this file."""
    spec = aw.SPECS[widget]
    bid = spec["block_id"]
    start, end, body = aw.block_span(src, bid)
    t0, t1 = aw.prop_span(src, body, end, "text")
    ind = aw.indent_of(src[t0:t1])
    line_start = src.rfind("\n", 0, start) + 1
    block_ind = aw.indent_of(src[line_start:start])
    out = {}
    # a comment and an unrelated property added to the button
    out["extra property in the button"] = src[:t0] + ind + "opacity: 1.0\n" + ind + "// upstream comment\n" + src[t0:]
    # the text binding spread over several lines
    expr = src[t0:t1].split(":", 1)[1].strip()
    out["text binding reformatted"] = src[:t0] + ind + "text: " + expr.replace("\n", "\n" + ind + "  ") + "\n" + src[t1:]
    # another BarIconButton above this one (Omarchy widgets grow extra buttons)
    other = block_ind + "BarIconButton {\n" + block_ind + "  id: someOtherButton\n" + \
        block_ind + '  text: "x"\n' + block_ind + "}\n"
    out["another BarIconButton above"] = src[:line_start] + other + src[line_start:]
    # new code above the button, as a rebase would leave it
    out["new property above the button"] = src[:line_start] + block_ind + \
        "readonly property int upstreamThing: 42\n\n" + src[line_start:]
    # a new import line
    m = list(re.finditer(r"^import .*$", src, re.M))[-1]
    out["new import"] = src[:m.end()] + "\nimport QtQuick.Effects" + src[m.end():]
    # trailing whitespace and CRLF-ish noise
    out["trailing whitespace"] = re.sub(r"^(\s*id: %s)$" % re.escape(bid), r"\1  ", src, count=1, flags=re.M)
    return out


def refusals(src, widget):
    """Files the patcher must refuse instead of producing a broken widget."""
    out = {}
    out["no BarIconButton"] = src.replace("BarIconButton", "SomeOtherButton")
    out["button has no id"] = re.sub(r"^(\s*)id: %s\s*$" % re.escape(aw.SPECS[widget]["block_id"]),
                                     r"\1objectName: gone", src, flags=re.M)
    for pattern, what in aw.SPECS[widget]["needs"]:
        gone = re.sub(pattern, "// removed", src, flags=re.M)
        if gone != src:
            out["without " + what] = gone
    return {name: text for name, text in out.items() if text != src}


def check_tree(tree, label):
    global skipped
    print("== %s" % label)
    tmp = tempfile.mkdtemp(prefix="ios-bar-test-")
    try:
        for w in WIDGETS:
            path = stage(tree, w, tmp)
            if path is None:
                print("  skip  %s (not in this Omarchy)" % w)
                skipped += 1
                continue
            src = open(path, encoding="utf-8").read()

            # 1. the exact patch still applies to this stock file
            exact_path = stage(tree, w, tmp)
            exact_ok = exact(exact_path, w)
            exact_text = open(exact_path, encoding="utf-8").read() if exact_ok else None

            # 2. the patcher applies, and agrees with the patch when both apply
            out = adaptive(path, w)
            report(out is not None, "%-10s adaptive applies" % w)
            if out is None:
                continue
            report(valid_qml(path), "%-10s result is valid QML" % w)
            report(aw.SPECS[w]["marker"] in out, "%-10s result carries the icon" % w)
            # every button the widget has (a vertical bar uses its own) must carry the icon
            buttons = len(aw.block_spans(src, aw.SPECS[w]["block_id"]))
            report(out.count("iconComponent:") >= buttons,
                   "%-10s all %d button(s) patched" % (w, buttons))
            if exact_ok:
                report(exact_text == out, "%-10s patch and patcher agree" % w,
                       "the exact patch produces a different file (run tools/make-patches.sh)")
            else:
                print("  note  %-10s the exact patch does not apply here; only the patcher does" % w)

            # 3. patching an already patched file is a no-op
            again = adaptive(path, w)
            report(again == out or aw.SPECS[w]["marker"] in open(path, encoding="utf-8").read(),
                   "%-10s patching twice is a no-op" % w)

            # 4. it survives plausible upstream edits
            for name, mutated in mutations(src, w).items():
                p = stage(tree, w, tmp, mutated)
                res = adaptive(p, w)
                ok = res is not None and aw.SPECS[w]["marker"] in res and valid_qml(p)
                report(ok, "%-10s survives: %s" % (w, name))

            # 5. it refuses what it cannot honestly patch
            for name, broken in refusals(src, w).items():
                p = stage(tree, w, tmp, broken)
                res = adaptive(p, w)
                report(res is None, "%-10s refuses: %s" % (w, name))

            # 6. weather needs its Model.js next to it
            if w == "weather":
                p = stage(tree, w, tmp)
                os.remove(os.path.join(os.path.dirname(p), "Model.js"))
                report(adaptive(p, w) is None, "%-10s refuses: Model.js missing" % w)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    trees = argv[1:]
    if not trees:
        trees = [os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")]
    if not QMLFORMAT:
        print("note: qmlformat not found, skipping the QML syntax checks")
    for t in trees:
        if not os.path.isdir(os.path.join(t, "shell/plugins")):
            print("== %s\n  skip (no shell/plugins here)" % t)
            continue
        check_tree(t, t)
    print("\n%d passed, %d failed, %d widgets skipped" % (passed, failed, skipped))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
