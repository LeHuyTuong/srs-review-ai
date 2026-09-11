# Liquid Glass — Implementation Spec for the Flutter Team

**Target:** iOS 26 / iPadOS 26 "Liquid Glass" (announced WWDC25), implemented in Flutter.
**Status:** Research-derived specification. Apple publishes **no numeric blur/saturation/tint tokens**;
every number below is either `sourced` (from Apple text) or `derived` (reverse-engineered from
shipping DOM/UIKit inspection or from third-party implementations). Treat `derived` values as
**starting points to tune**, not canonical constants.

**Primary sources**

- [HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [WWDC25 219 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 356 — Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Technology Overviews — Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass) / [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color)
- Flutter: [BackdropFilter](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html), [ImageFilter.blur](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.blur.html), [TileMode](https://api.flutter.dev/flutter/dart-ui/TileMode.html)
- Analysis: [STRV — How to apply Liquid Glass](https://www.strv.com/blog/how-to-apply-liquid-glass-to-your-app), [cupertino_liquid_glass ARCHITECTURE](https://github.com/erenmalkoc/cupertino_liquid_glass/blob/main/doc/ARCHITECTURE.md), [WWDC25 284 — Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/)

---

## 1. What Liquid Glass is (Apple's framing)

- **A digital "meta-material", not a texture.** Apple explicitly says it is *not* a recreation of a
  physical material: it is a new digital meta-material that **dynamically bends, shapes and
  concentrates light in real time**, where previous materials only *scattered* light. ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/))
- **Lensing is the defining visual.** "Lensing" — the warping/bending of light through a transparent
  object — is what communicates presence, motion and form, and gives separation from content without
  opacity. ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/))
- **It is the floating functional layer, not a surface treatment.** Liquid Glass belongs primarily to
  the **navigation/control layer** (tab bars, sidebars, toolbars, floating controls) that floats above
  content; content-layer surfaces keep standard materials (ultra-thin/thin/regular/thick). ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
- **It is adaptive, not fixed.** The material has no inherent color; it derives color from what is
  behind it, adapts luminosity and contrast for legibility, and changes light/dark style contextually.
  Tint is applied *selectively* to emphasize controls. ([HIG Color](https://developer.apple.com/design/human-interface-guidelines/color))
- **Motion and material are one system.** Elements do not fade — they **materialize by modulating
  lensing**, and respond to touch by "flexing and energizing with light", with a gel-like flexibility.
  ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/))

Two variants: **Regular** (default; legibility first, text-heavy controls) and **Clear** (more
translucent, for visually rich media, may need a dimming layer). Apple says do not mix them in one
design context. ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))

---

## 2. Measurable parameter table

> Column **Src**: `sourced` = stated in Apple documentation/session; `derived` = reverse-engineered
> from shipping implementations or third-party analyses.

| # | Parameter | Light mode | Dark mode | Src |
|---|---|---|---|---|
| 1 | Backdrop blur, compact controls (pills, buttons, FAB) | `sigma 8–12 px` | same | derived |
| 2 | Backdrop blur, panels (nav bar, toolbar, sheet) | `sigma 16–24 px` | same | derived |
| 3 | Backdrop blur, large surfaces (sidebar, menu) | `sigma 24–32 px` | same | derived |
| 4 | Inspected reference blur (one Apple surface) | `2 px` + brightness/contrast lift | same | derived |
| 5 | Backdrop saturation boost | `+180 %` (`saturate(180%)`) | same | derived |
| 6 | Backdrop brightness / contrast lift | `1.06` / `1.04` | same | derived |
| 7 | Tint layer (color wash) | `#FFFFFF @ 0.40` | `#1C1C20 @ 0.30` | derived |
| 8 | Base fill opacity (the glass body itself) | `0.12–0.15` | `0.12–0.15` | derived |
| 9 | Tint for *prominent* control (accent wash) | accent `@ 0.55–0.70` | accent `@ 0.45–0.60` | derived |
| 10 | Stroke (specular rim) width | `1.0 px` (0.5 px small, ≤1.5 px large) | same | derived |
| 11 | Rim highlight opacity (top-left, gradient) | white `@ 0.20–0.26` | white `@ 0.10–0.18` | derived |
| 12 | Rim gradient stops | `white 0.0 → transparent 0.55` | `white 0.0 → transparent 0.45` | derived |
| 13 | Inner/top highlight (inset, "lip") | white `@ 0.35`, blur `2–4 px`, offset `y=1` | white `@ 0.18` | derived |
| 14 | Drop shadow | `y=8, blur=24, #000 @ 0.10` | `y=6, blur=22, #000 @ 0.34` | derived |
| 15 | Shadow, small/elevated control | `y=2, blur=8, #000 @ 0.08` | `y=2, blur=8, #000 @ 0.26` | derived |
| 16 | Corner radius, small control (pill/FAB) | `h/2` (full pill) or `16 px` | same | derived |
| 17 | Corner radius, standard panel | `24 px` | same | derived |
| 18 | Corner radius, large surface | `32 px` | same | derived |
| 19 | Inspected reference radius | `22 px` | same | derived |
| 20 | **Concentric nesting rule** | `innerRadius = outerRadius − padding` (floor at 0 → square inner corner) | same | sourced |
| 21 | Clear-variant dimming layer (over bright media) | `#000 @ 0.35` | n/a | sourced |
| 22 | Clear-variant base fill opacity | `0.06–0.10` | `0.06–0.10` | derived |
| 23 | Text/icon on glass — minimum contrast | `4.5:1` (normal text), `3:1` (≥18.66 px bold / ≥24 px) | same | sourced (WCAG) |

**Concentric rule (row 20) — mandatory geometry.** Nested rounded rects must be geometrically
concentric, not independently rounded. With a 24 px outer radius and 12 px padding, the inner radius
is **12 px**. If `outer − padding ≤ 0`, the inner corner is **square (0)**, never negative.
SwiftUI expresses this natively via `ConcentricRectangle` / `.rect(cornerRadius: .concentric)` with a
`.containerShape`; Flutter must compute it by hand.
([concentricCornerRadii](https://developer.apple.com/documentation/swiftui/geometryproxy/concentriccornerradii), [concentric corner style](https://developer.apple.com/documentation/swiftui/edge/corner/style/concentric))

**Composite order** (bottom → top). Getting this order wrong is the most common "it looks muddy" cause:

1. Capture backdrop → Gaussian blur (rows 1–4)
2. Saturation boost (row 5) + brightness/contrast lift (row 6)
3. Tint wash (row 7) and/or accent tint (row 9)
4. Base fill (row 8)
5. Specular rim stroke (rows 10–12) + inner lip highlight (row 13)
6. Drop shadow *behind* the surface (rows 14–15)
7. Foreground content, with adaptive polarity (row 23)

---

## 3. Behavioral rules

1. **Glass belongs to the floating navigation/control layer only.** Tab bars, toolbars, sidebars,
   floating action clusters, transient controls. Never to content: not cards, not list rows, not table
   views, not paragraphs, not full-screen page backgrounds. ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
2. **Never stack glass on glass.** Do not put a glass control on a glass surface, and do not apply the
   material both to a container and the controls inside it. Use fills, transparency or vibrancy for the
   upper element instead. Stacking compounds blur, produces muddy noise, and multiplies render cost.
   ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/))
3. **Must re-tint over busy content.** Because the material derives its color from behind it, a fixed
   tint fails over varied backdrops. Sample/inspect the backdrop luminance and shift the tint and
   foreground polarity accordingly: switch to the dark style + dimming when dark content moves under a
   surface. Small controls (nav bar, tab bar) may flip light/dark independently; large surfaces (menus,
   sidebars) should *not* flip — adapt their glyphs instead, because a large-area flip is distracting.
4. **Text-on-glass must meet contrast against the *composited* result**, not the nominal color. Target
   ≥4.5:1 for body text, ≥3:1 for large text/icons. If a text run cannot be guaranteed legible over the
   busiest possible backdrop, put it on an opaque-enough backing or use Regular instead of Clear.
5. **Simplify rather than cover.** If a bar is crowded, remove secondary actions into menus; do not add
   more glass. ([WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/))
6. **Preserve source→surface relationships.** A sheet/action sheet should visibly emerge from the
   control that invoked it; use dimming when a modal task must take focus.

### Accessibility responses

| Setting | Required behavior |
|---|---|
| **Reduce Transparency** (`MediaQuery.of(context).disableTransparency` / `accessibleNavigation` sibling — Flutter exposes `MediaQueryData` platform brightness & accessibility flags; on iOS read `UIAccessibilityIsReduceTransparencyEnabled`) | Make glass **near-opaque**: raise base fill to `~0.92–1.0`, **drop the backdrop blur entirely**, keep the rim stroke. Do *not* remove the layout or the tint identity. Apple: this reduces transparency and blur, making areas more opaque. |
| **Increase Contrast** | **Strengthen the rim stroke** (`1.0 → 1.5 px`, highlight opacity `+0.15`), darken/lighten the tint wash away from the backdrop, and push text to full-opacity label colors. Translucency may remain. Apple: this sharpens borders/definition rather than removing glass. |
| **Both enabled** | Maximum legibility: opaque fill **and** strong rim. This is the "least glassy" result and is the expected, correct outcome. |
| **Reduce Motion** | Disable morph/lensing transitions and spring overshoot; substitute short opacity cross-fades (≤120 ms). Keep all glass *rendering* static. |

Note the two settings are **not equivalent** and neither "fixes" the other. Also, on iOS 26 the
dedicated *Settings → Display & Brightness → Liquid Glass* (Clear/Tinted) choice is only selectable when
both Reduce Transparency and Increase Contrast are off.

---

## 4. Motion

Apple does not publish spring constants. Behavior to reproduce: glass **materializes by modulating
lensing rather than fading**, flexes on touch, and morphs shape between related glass elements.

**Spring values for Flutter `SpringDescription` / `SpringSimulation`** (derived; Apple's duration/bounce
API is perceptual — [WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)):

| Interaction | Duration | Bounce (→ damping) | Scale / transform |
|---|---|---|---|
| Standard morph (bar collapse, control expand) | `0.35–0.45 s` | `0.10–0.18` | `1.00 → 1.00` (shape morph, no scale) |
| Materialize in / out | `0.40 s` | `0.12` | `scale 0.94 → 1.00`, opacity `0 → 1` |
| Press-down feedback | `0.16–0.25 s` | `0.12` | `scale 1.00 → 0.96–0.98` |
| Release / spring-back | `0.30 s` | `0.18` | `scale → 1.00` |
| Playful (rare, non-control) | `0.45–0.60 s` | `0.20–0.30` | — |

Hard rules:
- **Cap bounce ≤ 0.35** for controls — above that it reads toy-like.
- Map Apple's `bounce` to Flutter directly: `SpringDescription.withDampingRatio(mass: 1, stiffness: 180–260, ratio: 1 − bounce)`. Bounce `0.12` ≈ ratio `0.88`; bounce `0.18` ≈ ratio `0.82`.
- **Animate transform and opacity only — never layout.** No `AnimatedContainer` on width/height/padding,
  no `LayoutBuilder`-driven size animation, no animating `BackdropFilter.filter`. Wrap the animatee in
  `Transform.scale` / `Transform.translate` / `Opacity` (or `SlideTransition`) so the frame stays on the
  raster/composite path.
- **Never animate the blur filter itself.** Animating `ImageFilter.blur` sigma forces a fresh offscreen
  capture + full blur per frame. To fade glass, animate the child's opacity and a static-blur surface.
- Respect Reduce Motion: `MediaQuery.of(context).disableAnimations` → duration `≤120 ms`, no overshoot.
- Use `AnimationController` + `SpringSimulation` (via `controller.animateWith(...)`) rather than a
  hand-rolled curve when you need real overshoot; a plain `Curves.easeOutBack` is an acceptable cheaper
  approximation but overshoots less predictably.

---

## 5. Flutter mapping

### 5.1 Canonical widget stack

```dart
ClipRRect(
  borderRadius: BorderRadius.circular(outerRadius),
  child: BackdropFilter(
    filter: ui.ImageFilter.blur(
      sigmaX: sigma, sigmaY: sigma,
      tileMode: TileMode.decal,          // edge correctness, NOT a perf switch
      bounds: Offset.zero & size,        // "bounded blur" — the iOS frosted-glass mode
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        gradient: LinearGradient(colors: [
          tint.withValues(alpha: 0.15),  // light: white 0.40 / dark: #1C1C20 0.30
          tint.withValues(alpha: 0.12),
        ]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1.0),
        boxShadow: [BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Colors.black.withValues(alpha: 0.10))],
      ),
      child: content,
    ),
  ),
)
```

**Key API finding:** `ImageFilter.blur(bounds: ...)` enables **bounded blur mode** — out-of-rect samples
become transparent black and the weighted sum is divided by effective alpha, "typically used when the
blur must be strictly contained within a clipped region, such as for **iOS-style frosted glass
effects**". This is the correct primitive for Liquid Glass; prefer it over `TileMode` juggling
([ImageFilter.blur docs](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.blur.html)).

### 5.2 Component responsibilities

| Concern | Flutter primitive |
|---|---|
| Backdrop blur | `BackdropFilter` + `ImageFilter.blur(sigmaX, sigmaY, bounds:)` |
| Rounded containment | `ClipRRect` (must clip — **without a clip the filter covers the whole screen**) |
| Fill + tint + shadow | `DecoratedBox` / `Container` with `BoxDecoration` |
| Gradient **stroke** (specular rim) | `CustomPainter` drawing a `RRect.deflate(strokeWidth/2)` with a `LinearGradient` shader as `PaintingStyle.stroke`, **or** a `DecoratedBox` with a gradient `Border` |
| Specular edge / refraction sheen | `ShaderMask` (or `FragmentShader` via `CustomPainter` for animated sheen) |
| Spring motion | `AnimationController` + `SpringSimulation` via `controller.animateWith(...)` |
| Cheap single-widget blur (not backdrop) | `ImageFiltered` — Flutter docs say "performance will be improved dramatically" vs `BackdropFilter` |
| Grouping many blurs | `BackdropGroup` + `BackdropFilter.grouped` (engine filters **once**) |

### 5.3 Performance caveats — `BackdropFilter` is expensive

Flutter's own docs: *"This effect is relatively expensive, especially if the filter is non-local, such
as a blur."* It must capture the painted scene, run a non-local blur and composite it back; with no
ancestor clip it processes the **full screen**. On Flutter web (CanvasKit/SkWasm) this is the #1 jank
source in glass UIs. ([BackdropFilter docs](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html))

Mitigations, in priority order:

1. **Always bound it.** `ClipRRect`/`ClipRect` tight to the surface, plus `ImageFilter.blur(bounds:)`. Never an unclipped `BackdropFilter`.
2. **Limit simultaneous blurs.** Budget: **≤3** blurred surfaces on screen at once; ≤1 per conceptual layer. A scrolling list of glass rows is a defect — use one blur behind the list.
3. **Group repeated blurs.** `BackdropGroup(child: BackdropFilter.grouped(...))` makes the engine perform the filtering once for a shared `BackdropKey` (Apple's own docs show a 60-item list doing this). Note: **overlapping** filters must *not* share a key.
4. **Never animate the filter.** Animate opacity/transform of the glass child instead.
5. **`TileMode.decal` is edge correctness, not speed.** It only makes out-of-bounds samples transparent black (killing edge color-bleed); it does **not** remove the offscreen capture, blur kernel or compositing. Don't treat it as an optimization.
6. **Prefer `ImageFiltered`** whenever you are blurring one widget rather than the scene behind it.
7. **Static pre-blurred fallback.** For web/low-end: snapshot the backdrop once (`RepaintBoundary` + `toImage()`), or ship a pre-blurred image/gradient asset, or drop to an opaque tint. Gate on `kIsWeb` and device tier.
8. **Reduce sigma** — cost scales with kernel size; `sigma 32` is ~4× the work of `sigma 8` over the same area.
9. Test on the real renderer and on real hardware; do not judge from a desktop Chrome profile.

---

## 6. Anti-patterns — common mistakes when copying Liquid Glass

1. **Glass everywhere.** Blurring cards, list rows, table views and page backgrounds. Liquid Glass is the
   *navigation layer*; content must stay on standard materials, or hierarchy collapses.
   ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
2. **Glass-on-glass stacking.** A translucent toolbar over a translucent card over a translucent page.
   Compounds blur into muddy noise and multiplies render cost. One glass surface per conceptual layer.
3. **Treating transparency as contrast.** Hard-coded white text with low-alpha fill that "looks fine in
   the mockup", then fails over wallpaper, media, dark mode or a user setting. Measure the **composited**
   contrast (≥4.5:1), never the nominal color.
4. **Using Clear by default.** Clear is for visually rich media and is intentionally more transparent; it
   needs a dimming layer. Regular is the safe default for text-heavy controls, alerts and sidebars, and
   the two variants should not be mixed in one context.
5. **Tinting everything.** If every control has a custom tint, nothing signals priority. Reserve tint for
   prominent actions; put broader color in the content layer. ([HIG Color](https://developer.apple.com/design/human-interface-guidelines/color))
6. **Floating essential text/forms/errors directly over blur.** Aesthetic translucency is not a reliable
   text backing. Put critical information on a stable, sufficiently opaque surface.
7. **Ignoring accessibility fallbacks.** No handling for Reduce Transparency, Increase Contrast, Reduce
   Motion, or the system Clear/Tinted choice. Shipping only the pretty path is a defect, not a polish gap.
8. **Copying the look without the behavior.** A static `backdrop-filter`/`BackdropFilter` recipe that
   never re-tints, never adapts luminosity, and never flips polarity. Liquid Glass is *adaptive*; the
   static recipe is glassmorphism, not Liquid Glass.
9. **Treating blur as free.** Sticky headers over scrolling content, many simultaneous blurs, high sigma,
   animated filters. Budget ≤3 simultaneous blurs and never animate the filter.
10. **Designing for the hero screenshot.** Glass is most convincing over rich imagery and *least*
    predictable there. Test light/dark wallpapers, video frames, long text, scrolling, Dynamic Type,
    keyboard movement, VoiceOver focus, and low-power conditions.
11. **Independent corner radii on nested shapes.** Violates the concentric rule
    (`inner = outer − padding`, floor 0). Non-concentric nesting is instantly visible as "off" curvature.
12. **Animating layout.** Growing/shrinking a glass surface via width/height forces relayout + a fresh
    backdrop capture each frame. Animate transform/opacity only.

---

## Appendix — quick token block

```dart
// Derived starting tokens. Tune per component. NOT Apple-published constants.
const glassBlurCompact = 10.0;   // sigma, pills/buttons
const glassBlurPanel   = 20.0;   // sigma, nav/toolbar/sheet
const glassBlurLarge   = 28.0;   // sigma, sidebar/menu
const glassSaturation  = 1.80;   // +180%
const glassBrightness  = 1.06;
const glassContrast    = 1.04;
const glassFillLight   = 0.13;   // base body opacity
const glassFillDark    = 0.13;
const glassTintLight   = Color(0x66FFFFFF); // #FFF @ 0.40
const glassTintDark    = Color(0x4D1C1C20); // #1C1C20 @ 0.30
const glassStrokeWidth = 1.0;
const glassRimLight    = 0.22;   // white alpha, light mode
const glassRimDark     = 0.14;   // white alpha, dark mode
const glassRadiusSmall = 16.0;
const glassRadiusPanel = 24.0;
const glassRadiusLarge = 32.0;
double concentric(double outer, double padding) =>
    (outer - padding).clamp(0.0, double.infinity);
```
