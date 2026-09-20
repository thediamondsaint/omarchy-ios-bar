import QtQuick
import QtQuick.Shapes
import qs.Commons

// iOS-status-bar style vector icons for the Omarchy bar.
//
// Every icon is drawn on a 24x24 grid with one stroke weight, round caps/joins and filled
// "SF Symbols"-like shapes, scaled to the bar's icon canvas. Colours come from the caller
// (theme foreground / accent). Use as the `iconComponent` of a BarIconButton:
//
//   iconComponent: Component { IosIcon { kind: "wifi"; level: 0.6; color: root.bar.foreground } }
//
// kind: wifi | ethernet | bluetooth | volume | headphones | display | robot | chevronLeft
//       weather: sun | moon | cloud | partlySun | partlyMoon | rain | sleet | storm | snow | fog
// level:   0..1  (wifi bars, volume waves)
// muted:   volume shows an x instead of waves
// slashed: diagonal slash (off / disconnected)
Item {
  id: root

  property string kind: ""
  property real level: 1
  property bool muted: false
  property bool slashed: false
  property color color: Color.foreground
  property real dimOpacity: 0.32     // opacity of inactive bars / waves
  // Every icon is scaled so its *ink* is the same height (a wifi fan fills less of the grid than a
  // bluetooth rune), and strokes have the same pixel weight across all icons.
  // The bar's icon canvas size; falls back to Omarchy 4.0.4's value if a newer Omarchy renames it.
  readonly property real canvas: (Style.bar && Style.bar.iconCanvas) ? Style.bar.iconCanvas : 19
  property real inkTarget: canvas * 0.66            // visual height of every icon, px
  property real strokePx: canvas * 0.072            // stroke width, px
  readonly property var inkH:  ({ wifi: 18.738, ethernet: 15.0, bluetooth: 20.0, volume: 17.2, headphones: 18.0, display: 17.971, robot: 18.893, chevronLeft: 16.174, sun: 20, moon: 20, cloud: 20, partlySun: 20, partlyMoon: 20, rain: 20, sleet: 20, storm: 20, snow: 20, fog: 20 })
  readonly property var inkCx: ({ wifi: 12.0, ethernet: 12.0, bluetooth: 11.75, volume: 12.6, headphones: 12.0, display: 12.0, robot: 12.0, chevronLeft: 11.4, sun: 12, moon: 12, cloud: 12, partlySun: 12, partlyMoon: 12, rain: 12, sleet: 12, storm: 12, snow: 12, fog: 12 })
  readonly property var inkCy: ({ wifi: 12.673, ethernet: 12.0, bluetooth: 13.595, volume: 15.086, headphones: 12.1, display: 15.011, robot: 12.68, chevronLeft: 15.411, sun: 12, moon: 12, cloud: 12, partlySun: 12, partlyMoon: 12, rain: 12, sleet: 12, storm: 12, snow: 12, fog: 12 })
  property bool centered: true
  // Drawn icons are centred geometrically; the bar's text glyphs sit lower in their canvas.
  // Same calibrated nudge as the battery so everything shares one centre line.
  property real nudge: canvas * 0.19

  readonly property real unit: inkTarget / (inkH[kind] || 24)
  readonly property real weight: strokePx / unit                   // stroke width in grid units
  implicitWidth: 24 * unit
  implicitHeight: 24 * unit
  width: implicitWidth
  height: implicitHeight
  anchors.centerIn: centered ? parent : undefined
  anchors.verticalCenterOffset: centered ? nudge : 0

  function tint(o) {
    return Qt.rgba(color.r, color.g, color.b, color.a * (o === undefined ? 1 : o))
  }

  // ---- geometry helpers ----------------------------------------------------
  function pol(cx, cy, r, a) { return [cx + r * Math.sin(a), cy - r * Math.cos(a)] }
  function f(n) { return n.toFixed(2) }

  // Annular sector (or wedge when r0 <= 0) opening upward, symmetric about the vertical, +/- a radians.
  function sector(cx, cy, r0, r1, a) {
    var p1 = pol(cx, cy, r1, -a), p2 = pol(cx, cy, r1, a)
    var d = "M" + f(p1[0]) + " " + f(p1[1]) + " A" + r1 + " " + r1 + " 0 0 1 " + f(p2[0]) + " " + f(p2[1])
    if (r0 <= 0) return d + " L" + cx + " " + cy + " Z"
    var p3 = pol(cx, cy, r0, a), p4 = pol(cx, cy, r0, -a)
    return d + " L" + f(p3[0]) + " " + f(p3[1]) + " A" + r0 + " " + r0 + " 0 0 0 " + f(p4[0]) + " " + f(p4[1]) + " Z"
  }

  // Upper intersection point of two circles (used to build the cloud outline from three lobes).
  function inter(x1, y1, r1, x2, y2, r2) {
    var dx = x2 - x1, dy = y2 - y1, d = Math.sqrt(dx * dx + dy * dy)
    var a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    var h = Math.sqrt(Math.max(0, r1 * r1 - a * a))
    var xm = x1 + a * dx / d, ym = y1 + a * dy / d
    var p1 = [xm + h * dy / d, ym - h * dx / d], p2 = [xm - h * dy / d, ym + h * dx / d]
    return p1[1] < p2[1] ? p1 : p2
  }
  // Counter-clockwise (on screen) arc from p to q on the circle centred (cx, cy).
  function arcCcw(cx, cy, r, p, q) {
    var a1 = Math.atan2(p[1] - cy, p[0] - cx), a2 = Math.atan2(q[1] - cy, q[0] - cx)
    var delta = (a1 - a2) % (2 * Math.PI)
    if (delta < 0) delta += 2 * Math.PI
    return " A" + f(r) + " " + f(r) + " 0 " + (delta > Math.PI ? 1 : 0) + " 0 " + f(q[0]) + " " + f(q[1])
  }
  // A cloud made of three lobes on a flat base, scaled by k about (12,12) and shifted by (dx, dy).
  function cloud(dx, dy, k) {
    function m(x, y) { return [12 + (x - 12) * k + dx, 12 + (y - 12) * k + dy] }
    var L = m(6.9, 14.3), T = m(11.6, 10.7), R = m(16.9, 14.3)
    var rl = 3.8 * k, rt = 5.2 * k, rr = 3.8 * k
    var pTR = inter(T[0], T[1], rt, R[0], R[1], rr)     // where the top and right lobes meet
    var pLT = inter(L[0], L[1], rl, T[0], T[1], rt)     // where the left and top lobes meet
    var bl = [L[0], L[1] + rl], br = [R[0], R[1] + rr]
    return "M" + f(bl[0]) + " " + f(bl[1]) + " L" + f(br[0]) + " " + f(br[1]) +
           arcCcw(R[0], R[1], rr, br, pTR) + arcCcw(T[0], T[1], rt, pTR, pLT) + arcCcw(L[0], L[1], rl, pLT, bl) + " Z"
  }
  function circle(cx, cy, r) {
    return "M" + f(cx - r) + " " + f(cy) + " a" + r + " " + r + " 0 1 0 " + f(2 * r) + " 0 a" + r + " " + r + " 0 1 0 " + f(-2 * r) + " 0 Z"
  }
  function rays(cx, cy, r0, r1, angles) {
    var d = ""
    for (var i = 0; i < angles.length; i++) {
      var a = angles[i] * Math.PI / 180
      d += "M" + f(cx + r0 * Math.cos(a)) + " " + f(cy + r0 * Math.sin(a)) + " L" + f(cx + r1 * Math.cos(a)) + " " + f(cy + r1 * Math.sin(a)) + " "
    }
    return d
  }

  function build(kind, level, muted, slashed) {
    var s = []
    var dim = root.dimOpacity
    if (kind === "wifi") {
      var bars = level > 0 ? Math.max(1, Math.min(3, Math.ceil(level * 3 - 0.001))) : 0
      var radii = [[0, 5.2], [7.8, 11.2], [13.8, 17.2]]
      for (var i = 0; i < 3; i++)
        s.push({ d: sector(12, 19.5, radii[i][0], radii[i][1], Math.PI / 4), fill: true, stroke: true, w: 1.1, o: i < bars ? 1 : dim })
      if (slashed) s.push({ d: "M3.6 3.6 L20.4 20.4", stroke: true, w: 2.2, o: 1 })
    } else if (kind === "ethernet") {
      s.push({ d: "M4 5.6 H20 A1.6 1.6 0 0 1 21.6 7.2 V15.2 H18.4 V18.4 H5.6 V15.2 H2.4 V7.2 A1.6 1.6 0 0 1 4 5.6 Z", stroke: true, o: 1 })
      s.push({ d: "M8.4 9 V12 M12 9 V12 M15.6 9 V12", stroke: true, w: 1.6, o: 1 })
    } else if (kind === "bluetooth") {
      s.push({ d: "M6.5 7.5 L17 16.5 L12 21 V3 L17 7.5 L6.5 16.5", stroke: true, o: slashed ? dim : 1 })
      if (slashed) s.push({ d: "M4.2 3.6 L19.8 20.4", stroke: true, w: 2.2, o: 1 })
    } else if (kind === "volume") {
      s.push({ d: "M2.6 9.7 H6 L11 5.5 V18.5 L6 14.3 H2.6 Z", fill: true, stroke: true, w: 1.2, o: 1 })
      if (muted || slashed) {
        s.push({ d: "M14.6 8.8 L21 15.2 M21 8.8 L14.6 15.2", stroke: true, o: 1 })
      } else {
        var waves = ["M14.12 9.19 A4.2 4.2 0 0 1 14.12 14.81",
                     "M16.80 6.78 A7.8 7.8 0 0 1 16.80 17.22",
                     "M19.47 4.37 A11.4 11.4 0 0 1 19.47 19.63"]
        var th = [0.001, 0.34, 0.67]
        for (var w = 0; w < 3; w++)
          s.push({ d: waves[w], stroke: true, o: level >= th[w] && level > 0 ? 1 : dim })
      }
    } else if (kind === "headphones") {
      s.push({ d: "M4.2 15.5 V12.2 A7.8 7.8 0 0 1 19.8 12.2 V15.5", stroke: true, o: 1 })
      s.push({ d: "M4.6 14 H7 V20.4 H4.6 A1.6 1.6 0 0 1 3 18.8 V15.6 A1.6 1.6 0 0 1 4.6 14 Z", fill: true, stroke: true, w: 1.0, o: 1 })
      s.push({ d: "M19.4 14 H17 V20.4 H19.4 A1.6 1.6 0 0 0 21 18.8 V15.6 A1.6 1.6 0 0 0 19.4 14 Z", fill: true, stroke: true, w: 1.0, o: 1 })
    } else if (kind === "display") {
      s.push({ d: "M5.6 4.6 H18.4 A2.2 2.2 0 0 1 20.6 6.8 V14.6 A2.2 2.2 0 0 1 18.4 16.8 H5.6 A2.2 2.2 0 0 1 3.4 14.6 V6.8 A2.2 2.2 0 0 1 5.6 4.6 Z", stroke: true, o: 1 })
      s.push({ d: "M12 17 V20.4 M8.6 20.6 H15.4", stroke: true, o: 1 })
    } else if (kind === "robot") {
      s.push({ d: "M8.4 8.6 H15.6 A4.4 4.4 0 0 1 20 13 V15 A4.4 4.4 0 0 1 15.6 19.4 H8.4 A4.4 4.4 0 0 1 4 15 V13 A4.4 4.4 0 0 1 8.4 8.6 Z", stroke: true, o: 1 })
      s.push({ d: "M12 8.6 V5.6 M1.8 12.6 V15.4 M22.2 12.6 V15.4", stroke: true, o: 1 })
      s.push({ d: "M12 2.5 m-1.4 0 a1.4 1.4 0 1 0 2.8 0 a1.4 1.4 0 1 0 -2.8 0 Z", fill: true, o: 1 })
      s.push({ d: "M9.3 13.8 m-1.3 0 a1.3 1.3 0 1 0 2.6 0 a1.3 1.3 0 1 0 -2.6 0 Z", fill: true, o: 1 })
      s.push({ d: "M14.7 13.8 m-1.3 0 a1.3 1.3 0 1 0 2.6 0 a1.3 1.3 0 1 0 -2.6 0 Z", fill: true, o: 1 })
    } else if (kind === "chevronLeft") {
      s.push({ d: "M14.8 5 L8 12 L14.8 19", stroke: true, w: 2.2, o: 1 })
    } else if (kind === "sun") {
      s.push({ d: circle(12, 12, 4.3), stroke: true, o: 1 })
      s.push({ d: rays(12, 12, 7.4, 9.6, [0, 45, 90, 135, 180, 225, 270, 315]), stroke: true, o: 1 })
    } else if (kind === "moon") {
      s.push({ d: "M12.5 3.5 A8.5 8.5 0 1 0 20.5 13.6 A6.6 6.6 0 0 1 12.5 3.5 Z", stroke: true, o: 1 })
    } else if (kind === "partlySun") {
      // cloud low right; sun peeking top-left as an arc that stays clear of the cloud
      s.push({ d: cloud(2.7, 4.0, 0.80), stroke: true, o: 1 })
      var sx = 8.2, sy = 7.6, sr = 3.3
      var a0 = 105 * Math.PI / 180, a1 = 350 * Math.PI / 180
      s.push({ d: "M" + f(sx + sr * Math.cos(a0)) + " " + f(sy + sr * Math.sin(a0)) + " A" + sr + " " + sr + " 0 1 1 " +
                  f(sx + sr * Math.cos(a1)) + " " + f(sy + sr * Math.sin(a1)), stroke: true, o: 1 })
      s.push({ d: rays(sx, sy, 5.5, 7.3, [180, 225, 270, 315]), stroke: true, o: 1 })
    } else if (kind === "partlyMoon") {
      s.push({ d: cloud(2.7, 4.0, 0.80), stroke: true, o: 1 })
      // small crescent top-left (the moon outline scaled down; stroke compensated so weight stays equal)
      s.push({ d: "M12.5 3.5 A8.5 8.5 0 1 0 20.5 13.6 A6.6 6.6 0 0 1 12.5 3.5 Z", stroke: true, o: 1, sc: 0.46, tx: 1.6, ty: 0.9, w: 2 / 0.46 })
    } else if (kind === "cloud") {
      s.push({ d: cloud(0, 0, 1.0), stroke: true, o: 1 })
    } else if (kind === "rain" || kind === "sleet") {
      s.push({ d: cloud(0, -2.6, 0.9), stroke: true, o: 1 })
      s.push({ d: "M8.4 17.2 L7.2 20.6 M12.4 17.2 L11.2 20.6 M16.4 17.2 L15.2 20.6", stroke: true, o: 1 })
    } else if (kind === "storm") {
      s.push({ d: cloud(0, -2.8, 0.9), stroke: true, o: 1 })
      s.push({ d: "M12.8 14.6 L10.2 18.2 H13.6 L11.2 21.8", stroke: true, o: 1 })
    } else if (kind === "snow") {
      s.push({ d: cloud(0, -2.6, 0.9), stroke: true, o: 1 })
      s.push({ d: "M8 18.4 L8 18.5 M12 20.8 L12 20.9 M16 18.4 L16 18.5 M12 16.6 L12 16.7", stroke: true, w: 2.6, o: 1 })
    } else if (kind === "fog") {
      s.push({ d: cloud(0, -3.2, 0.86), stroke: true, o: 1 })
      s.push({ d: "M5.5 17.6 H18.5 M8 21 H16", stroke: true, o: 1 })
    }
    return s
  }

  readonly property var specs: build(kind, level, muted, slashed)

  Item {
    width: 24
    height: 24
    x: (12 - (root.inkCx[root.kind] || 12)) * root.unit
    y: (12 - (root.inkCy[root.kind] || 12)) * root.unit
    transform: Scale { xScale: root.unit; yScale: root.unit }

    Repeater {
      model: root.specs
      delegate: Shape {
        id: layer
        required property var modelData
        width: 24
        height: 24
        x: layer.modelData.tx !== undefined ? layer.modelData.tx : 0
        y: layer.modelData.ty !== undefined ? layer.modelData.ty : 0
        scale: layer.modelData.sc !== undefined ? layer.modelData.sc : 1
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: layer.modelData.stroke ? root.tint(layer.modelData.o) : "transparent"
          strokeWidth: layer.modelData.w !== undefined ? layer.modelData.w * root.weight / 2 : root.weight
          fillColor: layer.modelData.fill ? root.tint(layer.modelData.o) : "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          PathSvg { path: layer.modelData.d }
        }
      }
    }
  }
}
