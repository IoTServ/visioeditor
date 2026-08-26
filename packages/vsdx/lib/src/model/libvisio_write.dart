/// Rewrite shape line appearance into cells / rows libvisio still collects.
///
/// LibreOffice Draw never reads Visio XML itself — `VisioImportFilter.cxx`
/// only calls `VisioDocument::isSupported` + `parse`. The VSDX token map has
/// no `CompoundType` and no `LineGradient`, no `FillGradient` /
/// `FillGradientEnabled`, `LineColorTrans` is absent and
/// `xmlStringToColour` forces Colour.a = 0, and unknown `LinePattern` ids
/// (custom draw.io arrays, 0xFE, …) fall through `_lineProperties` to a solid
/// stroke. A save therefore has to emit parallel Geometry rails, a built-in
/// pattern 2–23, or — when `User.veDashPattern` is not one of those ids —
/// MoveTo/LineTo dashes with LinePattern=1. A modern FillGradient whose
/// FillPattern was omitted (libvisio default 0) becomes classic FillPattern
/// 25–40 plus FillForegnd/FillBkgnd from the stops (resolved RGB or the
/// stop's theme slot) — otherwise Draw stays
/// hollow and an unfilled LineGradient ribbon would steal the body.
/// Opaque stops with more than two unique colours cannot use those two
/// cells, so a save bakes the same SoftEdges fill PNG at sigma 0 and
/// marks leftover Geometry NoFill — otherwise CompoundType 2–4 takes the
/// unfilled-ribbon path and LineColor covers that plate. Per-stop alpha
/// and FillForegndTrans / FillBkgndTrans on a 25–40 wash are the same
/// missing paint: `_fillAndShadowProperties` drops `draw:opacity` and
/// Draw ignores `librevenge:start-opacity` / `end-opacity`, so a save
/// bakes that PNG too — including a fully transparent stop that 25–40
/// would skip, stretching the remaining opaque colours from the box
/// edge. Two-colour opaque washes stay 25–40. FillPattern 2–24 hatch
/// FillForegndTrans is the same missing paint: `_fillAndShadowProperties`
/// drops `draw:opacity` when FillBkgndTrans is 1 and otherwise fades the
/// whole hatch-solid box from `max(fg,bg)`, so Draw keeps hard strokes
/// or turns an opaque FillBkgnd into glass while canvas / SVG only fade
/// the hatch lines. A save freezes those cells into FillForegnd /
/// FillBkgnd (toward the hatch background, or white when the background
/// is fully transparent) and writes Trans=0. Opaque hatches stay native.
/// Curve
/// commands (EllipticalArcTo, RelEllipticalArcTo, NURBS, spline, …) are
/// sampled so that plate follows the painted path — endpoint-only
/// polygons used to wash a pie as a triangle and a rounded rectangle as
/// the Width×Height box — and unpainted pixels composite onto opaque
/// white so Draw does not fill that box with Blue 2. Multiple NoFill=0
/// Geometry sections punch even-odd holes (libvisio's
/// `svg:fill-rule=evenodd`); a two-ring frame must not bake as a solid
/// Width×Height plate, including when a multi-stop LineGradient joins
/// that same fill PNG. For an
/// unfilled stroke with a line gradient or LineColorTrans, a filled ribbon
/// whose FillPattern 25–40 / FillForegndTrans libvisio *does* collect.
/// Opaque LineGradient stops with more than two unique colours cannot use
/// those two cells, so a save bakes the same SoftEdges stroke PNG at
/// sigma 0 (1-D uses a 2-D plate sized to the stroke ribbon). Per-stop
/// alpha and LineColorTrans on a two-colour wash would otherwise stay
/// opaque on that 25–40 ribbon. InfiniteLine
/// samples are clipped to the shape box first — perimeter sampling otherwise
/// spans hundreds of inches and the PNG collapses to one stop. Open
/// Begin/EndArrow on those washes go into the same PNG — Draw cannot
/// hang `draw:marker-*` on a Foreign plate — then Begin/EndArrow drop.
/// That ribbon cannot dash: built-in LinePattern
/// 2–23 (which `_lineProperties` *does* collect on a stroke) are flattened
/// to MoveTo/LineTo first, the same way custom `User.veDashPattern` already
/// is, so Draw keeps the gaps. Geometry-less Edraw labels that still carry
/// FillPattern=1 (no path for `m_currentFillGeometry`) write FillPattern=0
/// so Edraw does not fill the text box and hide white glyphs. Unfilled CompoundType 2–4 keep thick/thin contrast
/// the same way: each rail becomes a filled ribbon of that rail's width,
/// because LineWeight is shape-level and stroked rails would share the
/// thinnest width. Arrowed 1-D connectors that also need those
/// rewrites bake Begin/EndArrow as Geometry so Draw does not hang a
/// marker on every open rail. A plain stroke whose authored
/// BeginArrowSize disagrees with `_lineProperties`' line-weight formula
/// bakes the same way (`tokens.txt` has no BeginArrowSize). Marker ids
/// whose `_linePropertiesMarkerPath` is still a TODO stub (26, 31–34,
/// 36–38, 40, 43–45) bake at any size so Draw does not reuse a sibling
/// silhouette. Open arrow ids become filled ribbons of the original
/// weight so they survive a CompoundType rail rewrite. Character Highlight
/// is skipped by
/// `readCharIX` but `TextBkgnd` is collected and painted as
/// `fo:background-color`, so a uniform highlight with no authored
/// text-block fill is written there. Mixed run colours cannot share
/// one TextBkgnd, so a save inserts locked FillForegnd siblings that
/// carry each highlighted run (same advance as nowrap / curved-text),
/// stacks explicit newlines the same way canvas / SVG already wrap those
/// markers, wraps `User.veWordWrap` lines to TxtWidth with the same
/// word/space units shape-inside uses, and pins tab fields with the same
/// `visioTabFieldStart` canvas / SVG / libvisio `_fillTabSet` use. `TextDirection` is a
/// token the parser stores, but `_flushText` never emits
/// `style:writing-mode`, so Draw would keep a horizontal run; a save
/// folds canvas / SVG's −90° block rotation into `TxtAngle`, swaps
/// TxtWidth/TxtHeight and remaps margins, then writes TextDirection=0
/// so reopen does not rotate twice. Glueable labels with no TxtPin are
/// pinned to the route first; that tight plate then swaps width×height
/// so Draw's TextBkgnd stands up. `TxtAngle` stays 0 — Draw's
/// `librevenge:rotate` would lay the swapped box back down. Authored
/// TextBkgnd stays
/// native. Mixed Highlight on that rotated frame follows TxtAngle
/// about TxtPin. Connector labels use the same plates after a missing
/// TxtPin is pinned to the route — `readCharIX` would otherwise drop
/// every marker while canvas / SVG already paint them on the polyline.
/// `TextBkgndTrans` and layer
/// `ColorTrans` have no VSDX collector case (`xmlStringToColour` also
/// zeros alpha), so a save premultiplies those into RGB toward white.
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens —
/// `readCharIX` only stores `Font` and `Size` — so an Asian-only (or
/// complex-script-only) run whose Latin `Font` would tofu in Draw is
/// rewritten to the Asian / complex face, and a complex-only run writes
/// `ComplexScriptSize` into `Size`. A mixed Latin+CJK or Latin+Arabic
/// run is split so each script collects that face; leaving one `Font`
/// would keep Arial on 世界 / سلام while canvas / SVG already switch.
/// Character `LangID` is likewise absent
/// (`readCharIX` has no case; `tokens.txt` has no LangID), so a digit or
/// punctuation run that canvas / SVG already treat as RTL from LangID
/// (including tabbed digit runs)
/// prefixes U+200F. Strong Arabic / Hebrew letters already set Unicode
/// bidi, so those runs stay untouched. `_lineProperties` derives `stroke-linejoin`
/// from `LineCap` only (round cap → round join, otherwise miter), so an
/// explicit round / arcs join on a square/flat cap is baked with the same
/// RelQuadBezTo fillets as shape-level Rounding, and a bevel join becomes a
/// LineTo chamfer (including when the cap is round: Draw would otherwise
/// round the elbow, so the written LineCap is flattened to extended).
/// The same flatten applies to an explicit miter / miter-clip join on a
/// round cap: Draw would round-join from LineCap, while canvas / SVG keep
/// the sharp elbow. Straight edges have no join to fix and stay round-capped.
/// Sketch jiggle copies LineCap / `User.veLineJoin` onto those plates —
/// leftover Geometry is already NoLine — so the flatten runs on the
/// jiggle, not the leftover. `User.veMiterLimit` is not a token and
/// `_lineProperties` never emits `svg:stroke-miterlimit` (ODF defaults
/// to 4), so a save chamfers corners whose miter ratio exceeds a tighter
/// limit and drops the User row. Limits above 4 keep the canvas spike: a
/// save expands the unfilled stroke into a filled ribbon whose outline
/// uses that limit (Draw would otherwise bevel every ratio>4 elbow) and
/// drops the User row. Sketch jiggle copies that limit onto the plates
/// so the same ribbon keeps the spike; other bake plates stay skipped.
/// The Rounding cell stays 0 so Visio does not restroke. Character ColorTrans,
/// filled-shape LineColorTrans that cannot become a sibling ribbon, and
/// ShdwForegndTrans are not tokens —
/// `xmlStringToColour` also forces Colour.a = 0 — so a save premultiplies
/// those into RGB toward white and writes Trans=0. Theme-only Character
/// Color (canvas `_colourOrTheme`) is resolved through the document
/// theme, then Office, into that same blend — `ColorTrans` is not a
/// token, so leaving THEMEVAL() would paint the slot fully opaque.
/// Theme-bound colours with no transparency still keep THEMEVAL(), but
/// a save caches the resolved RGB in `V=` — libvisio's
/// `VSDFillStyle::override` applies that `V` after the theme, and
/// `V="0"` (palette black) is what Draw would otherwise paint.
/// Theme-only FillForegnd / FillBkgnd with FillForegndTrans /
/// FillBkgndTrans freeze into RGB and *keep* Trans — those cells *are*
/// tokens, so Draw still composites the wash, while THEMEVAL() plus
/// `QuickStyleFillColor` 9 paints faded black (`getThemeColour` stops
/// at 8, and `VSDFillStyle::override` applies explicit FillForegnd
/// after the theme).
/// Theme-only hard-edged ShdwForegndTrans bakes the same way —
/// `ShadowBlur` leftovers keep THEMEVAL() after the Gaussian PNG path.
/// A filled 2-D shape that
/// still paints a stroke bakes LineColorTrans / LineGradient / CompoundType
/// 1–4 rails / LinePattern 2–23 and `veDashPattern` dash ribbons / open-path
/// arrow Geometry / a long `veMiterLimit` spike as a locked sibling ribbon
/// whose FillForegndTrans Draw collects, then drops the source line so Draw
/// does not paint an opaque (or short-miter) stroke on top. Theme-only
/// LineColor freezes into that ribbon FillForegnd (document theme, then
/// Office) — a black fallback plus THEMEVAL painted grey, while canvas
/// already strokes `_colourOrTheme`. Page
/// `ConLineJump*` cells are not tokens either, so a save bakes hops as
/// ArcTo / MoveTo / LineTo and writes `ConLineJumpCode=1`. Geometry-less
/// glueable connectors have no path for libvisio's
/// `m_currentFillGeometry`; canvas / SVG already paint
/// `autoRoutedConnectorPolyline`, so a save writes that same elbow as
/// MoveTo/LineTo first — otherwise Draw stays blank. Absolute
/// `CubBezTo` / `QuadBezTo` become `RelCubBezTo` / `RelQuadBezTo`
/// (`tokens.txt` has no CubBezTo / QuadBezTo), but Rel* multiplies Y
/// by Height: a 1-D bow whose Height is 0 (BeginY=EndY) would collapse
/// to a straight chord while canvas / SVG already paint the cubic in
/// local inches. A save samples that bow as MoveTo/LineTo first.
/// A second save does not resample the polyline. Image
/// Transparency / Brightness / Contrast / Blur are likewise missing;
/// a save bakes them into a PNG and zeros the cells. Cropped Foreign
/// bitmaps overflow in Draw: libvisio emits `svg:width` from `ImgWidth`
/// and Draw does not clip to the Foreign box, while canvas / SVG already
/// clip. A save composites that window into a frame-sized PNG and resets
/// ImgOffset / ImgWidth / ImgHeight. Foreign
/// `EnhMetaFile` / `MetaFile` payloads are not a bitmap Draw paints —
/// libvisio emits `image/emf` / `image/wmf` and Draw fills the default
/// Blue 2 graphic style — so a save writes an opaque
/// `ForeignType=Bitmap` PNG. A thin DIB wrapper extracts that BMP; a
/// pure-vector metafile replays the same display list canvas / SVG
/// already paint — including ExtTextOut glyphs, GDI hatch brushes,
/// tiled DIB patterns and clips — so Draw cannot show Blue 2 through
/// unpainted pixels.
/// Foreign `Object` OLE packages are the same
/// missing paint: libvisio emits `object/ole` and Draw fills the
/// default Blue 2 graphic style, while canvas / SVG already replay the
/// `\x02OlePres000` WMF/EMF preview. A save unwraps that preview as
/// `ForeignType=MetaFile` / `EnhMetaFile`; the metafile bake then writes
/// PNG so Draw does not keep Blue 2. A second
/// save does not stack another preview.
/// Bitmap payloads with no libvisio `CompressionType` enum (WebP, ICO,
/// a PNG/JPEG sitting on a `.bin` part, headerless DIB) are labelled
/// `image/bmp` (`readForeignData` format 255) and Draw drops them, while
/// canvas / SVG already decode WebP / ICO. A save re-encodes those as
/// PNG `ForeignType=Bitmap`. A complete `BM` file stays native. A second
/// save does not stack another PNG.
/// Picture `SoftEdgesSize`
/// is not a token either: a 2-D Foreign bitmap bakes the same SourceAlpha
/// feather canvas / SVG use, then SoftEdgesSize is written 0. A cropped
/// picture is composited into the Foreign frame first so the halo sits on
/// the visible window, then ImgOffset / ImgWidth / ImgHeight fill that
/// frame and Draw does not crop the halo off. Geometry `SoftEdgesSize` is the
/// same missing token: a filled 2-D shape bakes a locked Foreign sibling
/// whose PNG alpha uses the same SourceAlpha feather canvas / SVG use
/// (resolved-RGB and theme-only FillGradient / classic 25–40 washes and
/// FillPattern 2–24 hatches are painted into that PNG so Draw does not
/// keep a hard fill, including an RGB hatch whose FillBkgnd is
/// theme-only and a theme-only FillForegnd hatch whose strokes freeze
/// through the document theme, then Office). A FillGradient whose
/// opaque stops use more than two unique colours uses that same plate
/// at sigma 0 — FillPattern 25–40 only interpolates FillForegnd /
/// FillBkgnd, so Draw would drop the middle colour. Theme-only FillForegnd /
/// LineColor / gradient
/// stops resolve through the document theme, then Office, into that PNG
/// so Draw keeps the feather. Then
/// SoftEdgesSize is written 0 and the source fill is dropped so the
/// plate is the body Draw paints. A hard-edged shadow on that fill
/// or on a LineGradient stroke PNG (`ShdwPattern` / `draw:shadow`)
/// cannot ride the Foreign plate — `_flushCurrentForeignData` emits
/// an empty graphic style — so a save bakes the same silhouette PNG
/// ShadowBlur uses, at sigma 0 (the stroke ring, not a filled box),
/// then ShdwPattern goes to 0. Two-colour washes keep native
/// `draw:shadow` on the filled 25–40 ribbon. A 1-D three-colour wash
/// bakes the same stroke-ring PNG on a 2-D plate. An oblique page
/// shears that ring — `ShdwObliqueAngle` is not a token.
/// An unfilled 2-D stroke with SoftEdges
/// bakes the same way from the stroke ring (padded so the outer half of
/// LineWeight and the blur halo are not clipped) and drops the source
/// line. Built-in LinePattern 2–23 and custom `veDashPattern` dashes are
/// painted into that PNG as per-dash ribbons so Draw keeps the gaps
/// (a solid ring would hide them). A filled 2-D shape that also paints a
/// solid stroke bakes fill and stroke into one padded plate and drops both,
/// so Draw does not keep a hard outline. Dashed strokes on a filled body
/// go into the same padded plate so Draw does not keep hard LinePattern
/// dashes on a feathered fill. Gradient / hatch fills with a solid or
/// dashed stroke join that plate so Draw does not keep a hard outline on
/// a feathered wash. CompoundType 1–4 rails join the same plate — they
/// are not a token either, so Draw would otherwise keep a single hard
/// stroke (or hard parallel rails) on a feathered fill. LineGradient is
/// likewise missing from `tokens.txt`, so a 2-D SoftEdges stroke with
/// resolved-RGB or theme-only stops samples that wash into the same
/// padded PNG and drops the source line — Draw would otherwise keep a
/// hard opaque outline (or a hard filled ribbon) on a feathered body.
/// Rounding is a
/// token Draw *does* collect, but the PNG silhouette used to stay a
/// sharp box, so a save dropped the fill and left square corners. The
/// same `filletPolyline` canvas / SVG / libvisio use is sampled into
/// that PNG (and into dash / compound ribbons) so Draw keeps the
/// fillets. `ShadowBlur` is likewise missing —
/// libvisio only emits a hard `draw:shadow` — so a filled 2-D shape with
/// blur bakes a locked Foreign sibling whose PNG is the Gaussian silhouette
/// canvas / SVG already paint, then ShdwPattern and ShadowBlur go to 0 so
/// Draw does not add a second hard copy. Theme-only colour
/// (canvas `_colourOrTheme`) resolves through the document theme, then
/// Office, into that same PNG so Draw keeps the blur. A Foreign picture
/// with blur bakes the same way from the image-frame silhouette canvas uses.
/// PageSheet `ShdwType` / `ShdwObliqueAngle` / `ShdwScaleFactor` are not
/// tokens at all — `readPageSheetProperties` only collects ShdwOffset* — so
/// a hard-edged shadow on an oblique page bakes the sheared, scaled
/// silhouette canvas `_applyPageShadowXform` paints into a locked NoLine
/// sibling whose FillForegndTrans Draw collects, then ShdwPattern goes to 0.
/// Theme-only colour resolves through the document theme, then Office,
/// into that sibling's FillForegnd so Draw keeps both the shear and the
/// slot. A blurred shadow on the same page rasterizes that sheared
/// silhouette into its Gaussian PNG instead, sized to the transformed
/// bounding box.
/// Character Overline is a token whose `readCharIX` case is empty, so a
/// save inserts U+0305 combining overlines and clears the cell, including
/// tabbed runs (U+0009 keeps its `tabIndices` stop) and field runs
/// (UTF-16 `<fld>` spans grow around each mark).
/// Character DoubleStrikethrough *is* collected (`style:text-line-through-type`
/// double) but Draw's drawing-text import paints it as a single strike,
/// while canvas / SVG already draw two bars. A save inserts U+0336
/// combining long-stroke overlays, keeps `Strikethrough` so Draw still
/// paints one bar, and clears DoubleStrikethrough — tabs keep their
/// `tabIndices` stop and `<fld>` UTF-16 spans grow around each mark.
/// Paragraph `SpLine=0` ("set solid") *is* a token, but
/// `_fillParagraphProperties` takes the percent branch whenever
/// `spLine <= 0` and emits `fo:line-height="0%"`. Draw then stacks every
/// wrapped line on one baseline, while canvas / SVG already treat 0 as
/// 1× Size. A save writes the run's Size as a positive SpLine so
/// libvisio takes the length branch. A second save does not change that
/// absolute cell.
/// Paragraph `HorzAlign=4` ("full" / distributed) *is* a token, but
/// `_fillParagraphProperties` emits illegal ODF `fo:text-align="full"`.
/// Draw's drawing-text import then falls back to left, while canvas /
/// SVG already map that cell to justify (Flutter has no last-line
/// stretch). A save writes `HorzAlign=3` so libvisio emits `justify`.
/// A second save does not change that cell.
/// Text-block `DefaultTabStop` *is* a token and the collector emits
/// `style:tab-stop-distance`, but Draw's drawing-text import ignores
/// that property and jumps 0.5" (ODF's default) while canvas / SVG
/// already use `visioTabFieldStart`. A save writes explicit Tabs stops
/// on that interval so Draw collects `style:tab-stops`. Authored
/// off-grid stops stay; a second save does not stack another grid.
/// Paragraph `Bullet` *is* a token and `_bulletFromParaFormat` resolves
/// `text:bullet-char`, but Draw's drawing-text import keeps only the
/// `text:min-label-width` inset, so a save writes the glyph into the
/// paragraph text, shifts any `<fld>` spans past that prefix, and folds
/// the label field into a hanging `IndLeft` / `IndFirst` on a rectangular
/// label. `BulletFontSize` / `BulletFont` are tokens too, but that same
/// drawing-text import never sizes `text:bullet-char`, so a rectangular
/// save whose marker Size or Font disagrees with the body splits the
/// prefix onto its own Character run. Curved Text and Shape Inside skip
/// that hanging indent and keep a single run — the glyph rides the
/// existing arc / outline plates at body Size. Glow*
/// cells are not tokens; an unfilled 1-D stroke bakes a
/// Gaussian PNG plate sized to the glow ribbon (a Foreign picture cannot
/// hang on a zero-height 1-D XForm, and a FillForegndTrans ribbon would
/// stay hard-edged), an unfilled 2-D stroke bakes a
/// Gaussian PNG ring, and a filled NoLine shape bakes a Gaussian PNG
/// sibling, then GlowSize is written 0. Theme-only colour
/// (canvas `_colourOrTheme`) resolves through the document theme, then
/// Office, into that same PNG so Draw keeps the blur. Filled shapes that
/// already paint a stroke keep their outline — stealing Line would drop
/// CompoundType / dashes that Draw *does* collect. That case bakes a
/// locked Gaussian PNG sibling (canvas `_drawGlow`). An unfilled 2-D
/// CompoundType stroke uses the
/// same PNG ring — canvas `_drawGlow` blurs the path, not the rails, so
/// skipping the bake would drop the halo (CompoundType is not a token).
/// A Foreign picture bakes the same Gaussian PNG ring
/// canvas `_drawGlow` paints around the image frame. Then `GlowSize` is
/// written 0.
/// `Letterspace` is not a token; canvas / SVG already fold FontScale into
/// tracking at 0.55×Size, and `readCharIX` *does* collect FontScale as
/// `style:text-scale`, so a save adds Letterspace into FontScale and
/// writes Letterspace 0. Page `PageColor` is not a token either
/// (`readPageSheetProperties` only stores size, scale, and ShdwOffset*) —
/// a save prepends a locked full-page plate so Draw paints the sheet.
/// `Reflection*` cells are likewise missing from `tokens.txt`, so a filled
/// 2-D shape bakes a locked sibling plate whose FillForegndTrans Draw
/// collects — unless the fill is a FillGradient whose opaque stops use
/// more than two unique colours, or a SoftEdges / hatch wash that already
/// bakes a fill PNG: FillPattern 25–40 would drop the middle stop, so
/// that mirror is the same SoftEdges fill PNG flipped, clipped, and faded.
/// An unfilled 2-D stroke bakes a locked PNG band of the mirrored
/// stroke (filling the mirror would paint an interior Draw leaves empty;
/// built-in LinePattern 2–23, `veDashPattern`, and CompoundType 1–4 rails
/// go into that band as ribbons so Draw does not keep a solid ring or
/// drop the mirror; a resolved-RGB or theme-only LineGradient is sampled
/// into the same band so Draw does not keep a solid LineColor ring;
/// theme-only LineColor resolves into that PNG so Draw keeps the
/// mirror), an unfilled 1-D
/// stroke bakes the same PNG band from its stroke ribbon (a Foreign plate
/// cannot use a zero-height 1-D XForm, and canvas `_drawReflection`
/// already inflates that degenerate bounds by half LineWeight),
/// and a Foreign picture bakes a locked Gaussian PNG sibling of
/// the same mirrored bitmap canvas / SVG already paint (cropped
/// pictures composite the Img* window into the frame first; FlipY
/// flips the bitmap before the mirror so the visual bottom is nearest,
/// and the plate LocPin follows `_reflectFillRing` without copying FlipY),
/// then
/// `ReflectionSize` is written 0. draw.io Sketch lives in
/// `User.veSketch*` rows libvisio never reads, so a save maps hachure /
/// cross-hatch / dots onto FillPattern 2–24 (`draw:fill=hatch`) and bakes
/// the two jiggle strokes as locked siblings, then writes `veSketch=0`.
/// Those copies keep LineGradient, which is not a token — FillPattern
/// 25–40 would drop a middle colour — so a later SoftEdges pass bakes
/// each jiggle into a stroke PNG. Two-colour washes stay a filled ribbon.
/// Glow* / Reflection* are not tokens either, so those copies also take
/// the stroke PNG halo / mirror the unfilled path already uses — otherwise
/// leftover Geometry is NoLine and Draw drops the effect.
/// SoftEdgesSize is the same missing token on those copies: leftover
/// Geometry is already NoLine, so a live size bakes the same stroke PNG
/// (1-D Sketch copies stay Height=0 and skip, matching canvas).
/// draw.io Glass is likewise `User.veGlass` (not a token), so a save inserts
/// a locked white top-light sibling whose FillForegndTrans Draw collects,
/// then writes `veGlass=0`. draw.io Shape Opacity is `User.veOpacity`
/// (not a token), so a save folds it into FillForegndTrans / line
/// transparency / image Transparency Draw actually collects, then drops
/// the User row. draw.io Label Border is `User.veLabelBorderColor`
/// (not a token), so a save inserts a locked NoFill sibling whose LineColor
/// Draw collects, then drops the User row. Glueable labels pin TxtPin
/// first so that stroke sits on the route plate, not the Begin–End box.
/// draw.io Label Padding is
/// `User.veLabelPadding` (not a token), so a save adds the pixel inset
/// into Left/Right/Top/BottomMargin (`fo:padding-*`) Draw collects, then
/// drops the User row. Glueable labels pin TxtPin first and grow that
/// tight plate so the pad sits around the glyphs, not inside the
/// Begin–End box. draw.io Curved Text is `User.veCurvedText`
/// (not a token), so a save inserts locked per-glyph siblings along the
/// same quadratic arc canvas / SVG already paint, hides the source
/// (`HideText` is a token) and drops the User row. Tab fields become
/// spaces so a `\t` does not skip the arc. Combining Overline / bidi
/// marks stay on the preceding glyph. FlipX / FlipY extra
/// text mirrors (canvas `_textFlip*`) are applied about TxtPin before
/// the shape XForm so Draw keeps the upright arc. draw.io Shape Inside is
/// `User.veShapeInside` (not a token), so a save inserts locked per-line
/// siblings in the same outline bands canvas / SVG already paint, hides
/// the source and drops the User row. FlipX / FlipY use the same TxtPin
/// extra-mirror. Open arrowheads no longer block Sketch jiggle: plates
/// drop Begin/EndArrow and the source keeps filled arrow Geometry. Glueable
/// 1-D labels with no `TxtPin` sit on the drawn-route midpoint on canvas /
/// SVG (TxtWidth is ignored there). Draw creates `m_txtxform` as soon as
/// TxtWidth exists, and `XForm` defaults `pinX`/`pinY` to 0 — the label
/// parks at the 1-D local origin, not the polyline. A missing `m_txtxform`
/// falls back to the Begin–End box. A save writes the midpoint into
/// `TxtPin` / a tight `TxtWidth` so left-align cannot drift.
/// draw.io Rotate with Edge is
/// `User.veAutoRotateLabel` (not a token), so a save writes the route
/// tangent into `TxtAngle` Draw collects and drops the User row.
/// Vertical connector labels keep that User row through the
/// `TextDirection` swap so the tangent still lands on the tall plate.
/// draw.io
/// Word Wrap is `User.veWordWrap` (not a token), so a save expands TxtWidth
/// to the unwrapped line plus margins (`svg:width` Draw wraps against),
/// including tab fields pinned with `visioTabFieldStart`, and drops the
/// User row. Glueable labels pin TxtPin first so that wider plate stays
/// on the route, not the Begin–End box. draw.io Flow Animation is `User.veFlowAnimation*`
/// (not a token), so a save flattens the same 8 CSS-px dash canvas / SVG
/// synthesise into MoveTo/LineTo and writes `veFlowAnimation=0`. Sketch
/// jiggle copies that User row onto the plates — leftover Geometry is
/// already NoLine — so the same flatten keeps the gaps. Arrowed
/// connectors that also flatten those dashes (or `veDashPattern`) bake
/// Begin/EndArrow as Geometry first so Draw does not hang a marker on
/// every open dash. draw.io collapsed containers are `User.veCollapsed`
/// (not a token), so a save writes Geometry `NoShow`, `HideText`,
/// `FillPattern=0` / `LinePattern=0`, and zero `ImgWidth` / `ImgHeight`
/// on every descendant — tokens Draw collects — and stores a restore
/// payload so Unfold can show them again. Merged-table `User.veCovered`
/// cells are the same missing token: canvas skips them while Draw would
/// paint the 0.01" park box, so a save applies those hide cells and
/// stores `veCoveredHidden` for Unmerge.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../export/compound_stroke.dart';
import '../export/line_jumps.dart';
import '../parser/emf_vector_parser.dart';
import '../parser/metafile_png.dart';
import '../parser/ole_preview.dart';
import '../parser/wmf_parser.dart';
import '../utils/color.dart';
import '../utils/gradient_math.dart';
import 'dash_pattern.dart';
import 'document.dart';
import 'effects.dart';
import 'fill.dart';
import 'geometry.dart';
import 'image.dart';
import 'layer.dart';
import 'line.dart';
import 'page.dart';
import 'path_tangent.dart';
import 'perimeter.dart';
import 'rich_text.dart';
import 'rounding.dart';
import 'shape.dart';
import 'shape_factory.dart';
import 'shape_inside.dart';
import 'sketch_style.dart';
import 'table.dart';
import 'theme.dart';
import 'user_property.dart';

/// `true` when a glueable 1-D connector has no drawable Geometry for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. libvisio emits a stroke
/// only when `readGeometry` filled `m_currentFillGeometry`; a Begin–End
/// XForm1D with no rows is not a path. Canvas / SVG already paint
/// [VsdxPage.autoRoutedConnectorPolyline] for `!hasGeometry` glueable
/// connectors. Master instances keep the stencil path — baking a local
/// elbow would hide that geometry.
bool shapeNeedsLibvisioConnectorRouteBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.isGlueableConnector) return false;
  if (shape.hasGeometry) return false;
  if (shape.masterId != null || shape.masterShapeId != null) return false;
  return shape.beginX != null &&
      shape.beginY != null &&
      shape.endX != null &&
      shape.endY != null;
}

/// Write the canvas / SVG auto-route as MoveTo/LineTo libvisio collects.
VsdxPage bakeConnectorRoutesForLibvisioWrite(VsdxPage page) {
  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    if (shapeNeedsLibvisioConnectorRouteBake(shape)) {
      final poly = page.autoRoutedConnectorPolyline(shape);
      if (poly.length >= 2) {
        final parentId = page.findParentId(shape.id);
        final frame = parentId == null
            ? poly
            : <Offset2D>[
                for (final p in poly) page.pageToLocalDeep(parentId, p),
              ];
        next = shape.reshapeAsPolyline(frame);
      }
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) next = next.copyWith(children: children);
    return next;
  }

  final shapes = <VsdxShape>[
    for (final shape in page.shapes) rewrite(shape),
  ];
  var same = shapes.length == page.shapes.length;
  if (same) {
    for (var i = 0; i < shapes.length; i++) {
      if (!identical(shapes[i], page.shapes[i])) {
        same = false;
        break;
      }
    }
  }
  if (same) return page;
  return page.copyWith(shapes: shapes);
}

/// `true` when CubBezTo / QuadBezTo would flatten in Rel* at this XForm.
bool shapeNeedsLibvisioDegenerateBezierBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!cubBezNeedsLibvisioPolylineBake(
    width: shape.width,
    height: shape.height,
  )) {
    return false;
  }
  for (final geometry in shape.geometries) {
    if (geometry.noShow) continue;
    for (final command in geometry.commands) {
      if (command is CubBezTo || command is QuadBezTo) return true;
    }
  }
  return false;
}

VsdxShape _sourceForLibvisioDegenerateBezierWrite(VsdxShape shape) {
  final geometries = <VsdxGeometry>[
    for (final geometry in shape.geometries)
      geometryForLibvisioWrite(
        geometry,
        width: shape.width,
        height: shape.height,
      ),
  ];
  var same = geometries.length == shape.geometries.length;
  if (same) {
    for (var i = 0; i < geometries.length; i++) {
      if (!identical(geometries[i], shape.geometries[i])) {
        same = false;
        break;
      }
    }
  }
  if (same) return shape;
  return shape.copyWith(geometries: geometries);
}

/// Sample Height=0 / Width=0 CubBezTo / QuadBezTo as LineTo Draw can stroke.
VsdxPage bakeDegenerateBezierForLibvisioWrite(VsdxPage page) {
  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    if (shapeNeedsLibvisioDegenerateBezierBake(shape)) {
      next = _sourceForLibvisioDegenerateBezierWrite(shape);
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) next = next.copyWith(children: children);
    return next;
  }

  final shapes = <VsdxShape>[
    for (final shape in page.shapes) rewrite(shape),
  ];
  var same = shapes.length == page.shapes.length;
  if (same) {
    for (var i = 0; i < shapes.length; i++) {
      if (!identical(shapes[i], page.shapes[i])) {
        same = false;
        break;
      }
    }
  }
  if (same) return page;
  return page.copyWith(shapes: shapes);
}

/// Rewrite hops and image adjustments the VSDX token map cannot collect.
VsdxDocument documentForLibvisioWrite(VsdxDocument document) {
  var pagesChanged = false;
  final pages = <VsdxPage>[];
  for (final page in document.pages) {
    final routed = bakeConnectorRoutesForLibvisioWrite(
      bakeDegenerateBezierForLibvisioWrite(page),
    );
    final next = bakeLineJumpsForLibvisioWrite(routed);
    pagesChanged |= !identical(next, page);
    pages.add(next);
  }
  final hopped = pagesChanged ? document.copyWith(pages: pages) : document;
  return bakeHatchTransForLibvisioWrite(
    bakeThemeRgbCacheForLibvisioWrite(
      bakePageColorForLibvisioWrite(
        bakeCoveredForLibvisioWrite(
          bakeCollapsedForLibvisioWrite(
            bakeShapeInsideForLibvisioWrite(
              bakeWordWrapForLibvisioWrite(
                bakeLabelBorderForLibvisioWrite(
                  bakeLabelPaddingForLibvisioWrite(
                    bakeFilledStrokeRibbonForLibvisioWrite(
                      bakeGeometrySoftEdgesForLibvisioWrite(
                        bakeReflectionForLibvisioWrite(
                          bakeImageAdjustmentsForLibvisioWrite(
                            bakeGlowPlateForLibvisioWrite(
                              bakeGlassForLibvisioWrite(
                                bakeSketchForLibvisioWrite(
                                  bakePageShadowForLibvisioWrite(
                                    bakeShadowForLibvisioWrite(
                                      bakeCurvedTextForLibvisioWrite(
                                        bakeShapeOpacityForLibvisioWrite(
                                          bakeSolidLineSpacingForLibvisioWrite(
                                            bakeDefaultTabStopForLibvisioWrite(
                                              bakeHorzAlignFullForLibvisioWrite(
                                                bakeMixedScriptFontForLibvisioWrite(
                                                  bakeLangIdRtlForLibvisioWrite(
                                                    bakeDoubleStrikethroughForLibvisioWrite(
                                                      bakeOverlineForLibvisioWrite(
                                                        bakeMixedHighlightForLibvisioWrite(
                                                          bakeLooseEdgeLabelForLibvisioWrite(
                                                            bakeAutoRotateLabelForLibvisioWrite(
                                                              bakeTextDirectionForLibvisioWrite(
                                                                bakeBulletGlyphForLibvisioWrite(
                                                                  bakeUnsupportedBitmapsForLibvisioWrite(
                                                                    bakeMetafileBitmapsForLibvisioWrite(
                                                                      bakeOlePreviewsForLibvisioWrite(
                                                                        hopped,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shape name of the full-page plate `PageColor` becomes for Draw.
const kLibvisioPageColorShapeName = 'LibvisioPageColor';

bool _pageColorShouldPaint(VsdxPage page) {
  final color = page.backgroundColor;
  if (color == null || color.alpha == 0) return false;
  if (color.value == VsdxColor.white.value) return false;
  return page.widthInches > 1e-9 && page.heightInches > 1e-9;
}

VsdxShape _pageColorPlateForLibvisioWrite(VsdxPage page) {
  final w = page.widthInches;
  final h = page.heightInches;
  final color = page.backgroundColor!;
  final existingId = page.shapes
      .where((s) => s.name == kLibvisioPageColorShapeName)
      .firstOrNull
      ?.id;
  return VsdxShapeFactory.rectangle(
    id: existingId ?? page.nextFreeShapeId(),
    pinX: w / 2,
    pinY: h / 2,
    width: w,
    height: h,
    name: kLibvisioPageColorShapeName,
    fill: VsdxFill(
      foreground: VsdxColor.argb(255, color.red, color.green, color.blue),
      pattern: 1,
      foregroundTransparency: (1 - color.alpha / 255).clamp(0.0, 1.0),
    ),
    line: const VsdxLine(pattern: 0),
  ).copyWith(
    locPinXInches: w / 2,
    locPinYInches: h / 2,
    locked: true,
  );
}

bool _pageColorPlateMatches(VsdxShape plate, VsdxShape expected) =>
    (plate.width - expected.width).abs() < 1e-9 &&
    (plate.height - expected.height).abs() < 1e-9 &&
    (plate.pinX - expected.pinX).abs() < 1e-9 &&
    (plate.pinY - expected.pinY).abs() < 1e-9 &&
    plate.fill.foreground?.value == expected.fill.foreground?.value &&
    (plate.fill.foregroundTransparency - expected.fill.foregroundTransparency)
            .abs() <
        1e-9 &&
    plate.line.pattern == 0;

/// `true` when [page] needs a full-page `PageColor` plate, or a stale plate
/// stripped, so Draw paints the sheet colour `readPageSheetProperties` skips.
bool pageNeedsLibvisioPageColorBake(VsdxPage page) {
  final existing =
      page.shapes.where((s) => s.name == kLibvisioPageColorShapeName).toList();
  if (!_pageColorShouldPaint(page)) return existing.isNotEmpty;
  if (existing.length != 1) return true;
  if (page.shapes.first.id != existing.single.id) return true;
  return !_pageColorPlateMatches(
    existing.single,
    _pageColorPlateForLibvisioWrite(page),
  );
}

VsdxPage bakePageColorPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioPageColorBake(page)) return page;
  final others = <VsdxShape>[
    for (final shape in page.shapes)
      if (shape.name != kLibvisioPageColorShapeName) shape,
  ];
  if (!_pageColorShouldPaint(page)) {
    return page.copyWith(shapes: others);
  }
  return page.copyWith(
    shapes: <VsdxShape>[_pageColorPlateForLibvisioWrite(page), ...others],
  );
}

/// Prepend (or strip) the full-page plate Draw uses in place of `PageColor`.
VsdxDocument bakePageColorForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakePageColorPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Name prefix of the sibling plate `Reflection*` becomes for Draw.
const kLibvisioReflectionShapeNamePrefix = 'LibvisioReflection.';

bool isLibvisioReflectionPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioReflectionShapeNamePrefix);

int? libvisioReflectionSourceId(VsdxShape plate) {
  if (!isLibvisioReflectionPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioReflectionShapeNamePrefix.length),
  );
}

double _combinedTransparency(double a, double b) =>
    1 - (1 - a.clamp(0.0, 1.0)) * (1 - b.clamp(0.0, 1.0));

double _paintY(VsdxShape shape, double localY) {
  final sy = shape.flipY ? -1.0 : 1.0;
  return sy * (localY - shape.effectiveLocPinY);
}

double _localYFromPaint(VsdxShape shape, double paintY) {
  final sy = shape.flipY ? -1.0 : 1.0;
  return shape.effectiveLocPinY + sy * paintY;
}

bool _ptsNear(Offset2D a, Offset2D b) =>
    (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;

Offset2D _intersectAtY(Offset2D a, Offset2D b, double y) {
  final dy = b.y - a.y;
  if (dy.abs() < 1e-15) return Offset2D(a.x, y);
  final t = (y - a.y) / dy;
  return Offset2D(a.x + t * (b.x - a.x), y);
}

/// Sutherland–Hodgman against `y >= ymin` (paint-space Y-up).
List<Offset2D> _clipKeepYAtLeast(
  List<Offset2D> pts,
  double ymin, {
  required bool closed,
}) {
  if (pts.length < 2) return const <Offset2D>[];
  var ring = pts;
  if (closed && ring.length >= 2 && _ptsNear(ring.first, ring.last)) {
    ring = ring.sublist(0, ring.length - 1);
  }
  if (ring.length < 2) return const <Offset2D>[];
  final out = <Offset2D>[];
  final n = closed ? ring.length : ring.length - 1;
  for (var i = 0; i < n; i++) {
    final start = ring[i];
    final end = closed ? ring[(i + 1) % ring.length] : ring[i + 1];
    final startIn = start.y >= ymin - 1e-12;
    final endIn = end.y >= ymin - 1e-12;
    if (closed) {
      if (endIn) {
        if (!startIn) out.add(_intersectAtY(start, end, ymin));
        out.add(end);
      } else if (startIn) {
        out.add(_intersectAtY(start, end, ymin));
      }
    } else {
      if (i == 0 && startIn) out.add(start);
      if (startIn && endIn) {
        out.add(end);
      } else if (startIn && !endIn) {
        out.add(_intersectAtY(start, end, ymin));
      } else if (!startIn && endIn) {
        out.add(_intersectAtY(start, end, ymin));
        out.add(end);
      }
    }
  }
  if (closed && out.length >= 2 && !_ptsNear(out.first, out.last)) {
    out.add(out.first);
  }
  return out.length >= 2 ? out : const <Offset2D>[];
}

List<VsdxPathCommand> _closedCommandsForRing(List<Offset2D> pts) {
  if (pts.length < 2) return const <VsdxPathCommand>[];
  var ring = pts;
  if (_ptsNear(ring.first, ring.last)) {
    ring = ring.sublist(0, ring.length - 1);
  }
  if (ring.length < 2) return const <VsdxPathCommand>[];
  return <VsdxPathCommand>[
    MoveTo(ring.first.x, ring.first.y),
    for (var i = 1; i < ring.length; i++) LineTo(ring[i].x, ring[i].y),
    LineTo(ring.first.x, ring.first.y),
  ];
}

List<Offset2D> _aabbRing(VsdxShape shape) => <Offset2D>[
      const Offset2D(0, 0),
      Offset2D(shape.width, 0),
      Offset2D(shape.width, shape.height),
      Offset2D(0, shape.height),
      const Offset2D(0, 0),
    ];

/// Stroke-inflated AABB for 1-D and Sketch-jiggle reflection plates;
/// other 2-D keeps the XForm box. Sketch copies of a 1-D source are
/// `is1D=false` with Height=0, so the XForm box cannot hang a Foreign
/// picture.
List<Offset2D> _reflectionSourceAabbRing(VsdxShape shape) {
  if (!shape.is1D && !isLibvisioSketchPlate(shape)) return _aabbRing(shape);
  final aabb = _polygonsAabb(_libvisioStrokeSilhouettePolygons(shape));
  if (aabb == null) return _aabbRing(shape);
  return <Offset2D>[
    Offset2D(aabb.minX, aabb.minY),
    Offset2D(aabb.maxX, aabb.minY),
    Offset2D(aabb.maxX, aabb.maxY),
    Offset2D(aabb.minX, aabb.maxY),
    Offset2D(aabb.minX, aabb.minY),
  ];
}

List<Offset2D> _reflectFillRing(
  List<Offset2D> local,
  VsdxShape shape, {
  required double dist,
  required double clipHeight,
}) {
  if (local.length < 2) return const <Offset2D>[];
  final paint = <Offset2D>[
    for (final p in local) Offset2D(p.x, _paintY(shape, p.y)),
  ];
  var bottom = paint.first.y;
  var top = paint.first.y;
  for (final p in paint) {
    if (p.y < bottom) bottom = p.y;
    if (p.y > top) top = p.y;
  }
  final span = top - bottom;
  final reflected = <Offset2D>[
    for (final p in paint) Offset2D(p.x, 2 * bottom - p.y - dist),
  ];
  final clipped = span <= 1e-9 || clipHeight >= span - 1e-9
      ? reflected
      : _clipKeepYAtLeast(
          reflected,
          bottom - dist - clipHeight,
          closed: true,
        );
  return <Offset2D>[
    for (final p in clipped) Offset2D(p.x, _localYFromPaint(shape, p.y)),
  ];
}

List<VsdxGeometry> _reflectionGeometriesForLibvisioWrite(VsdxShape shape) {
  final dist = math.max(shape.reflection.distanceInches, 0.0);
  final frac = shape.reflection.sizeInches.clamp(0.01, 1.0);
  final out = <VsdxGeometry>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noFill) continue;
    final pts = _strokedVertices(geometry, shape);
    if (pts == null || pts.length < 2) continue;
    var bottom = _paintY(shape, pts.first.y);
    var top = bottom;
    for (final p in pts) {
      final y = _paintY(shape, p.y);
      if (y < bottom) bottom = y;
      if (y > top) top = y;
    }
    final clipH = (top - bottom) * frac;
    final ring = _reflectFillRing(pts, shape, dist: dist, clipHeight: clipH);
    final commands = _closedCommandsForRing(ring);
    if (commands.length < 3) continue;
    out.add(
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: commands,
      ),
    );
  }
  if (out.isNotEmpty) return out;
  final fallback = _aabbRing(shape);
  var bottom = _paintY(shape, fallback.first.y);
  var top = bottom;
  for (final p in fallback) {
    final y = _paintY(shape, p.y);
    if (y < bottom) bottom = y;
    if (y > top) top = y;
  }
  final ring = _reflectFillRing(
    fallback,
    shape,
    dist: dist,
    clipHeight: (top - bottom) * frac,
  );
  final commands = _closedCommandsForRing(ring);
  if (commands.length < 3) return const <VsdxGeometry>[];
  return <VsdxGeometry>[
    VsdxGeometry(noFill: false, noLine: true, commands: commands),
  ];
}

/// `true` when Reflection* must become a sibling plate Draw actually fills.
///
/// `tokens.txt` has no ReflectionSize. Canvas / SVG already paint the mirror;
/// LibreOffice only sees Fill / Line / Geometry / ForeignData, so a filled
/// 2-D leaf bakes a NoLine sibling (FillForegndTrans is a token) unless
/// that fill cannot survive FillPattern 25–40 — more than two unique
/// opaque gradient colours, or a SoftEdges / hatch wash already destined
/// for a fill PNG — in which case the mirror is that PNG flipped and
/// clipped. An unfilled 2-D or 1-D stroke bakes a mirrored PNG band, and a Foreign
/// picture bakes a Gaussian PNG sibling, then the live cells go to 0.
/// Filled 1-D stays native — its FillPattern is already the body and a
/// zero-height plate cannot carry a fill mirror.
bool shapeNeedsLibvisioReflectionBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    if (shape.width.abs() <= 1e-9 && shape.height.abs() <= 1e-9) {
      return false;
    }
  } else if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) {
    return false;
  }
  if (!shape.is1D &&
      !isLibvisioSketchPlate(shape) &&
      _shapePaintsFill(shape, shape.geometries)) {
    return true;
  }
  if (_shapeCanLibvisioStrokeReflectionPng(shape)) return true;
  return _shapeCanLibvisioPictureReflectionPng(shape);
}

/// Filled 2-D whose body Draw cannot hold in FillPattern 25–40 / hatch
/// cells: mirror the same SoftEdges fill PNG canvas already paints.
bool _shapeNeedsLibvisioFillReflectionPng(VsdxShape shape) {
  if (shape.is1D) return false;
  if (!_shapePaintsFill(shape, shape.geometries)) return false;
  return _shapeNeedsLibvisioFillSoftEdgesBake(shape);
}

/// Unfilled 2-D and 1-D strokes: canvas `_drawReflection` strokes the
/// flipped path, so filling the mirror geometry would paint an interior
/// Draw leaves empty. A locked PNG band carries the mirrored stroke
/// instead. 1-D uses a 2-D plate sized to the stroke ribbon (canvas
/// inflates zero-area bounds by half LineWeight; a Foreign picture cannot
/// hang on a zero-height 1-D XForm). Built-in LinePattern 2–23, custom
/// `veDashPattern`, and CompoundType 1–4 rails are painted as ribbons so
/// Draw keeps the gaps / thick-thin contrast (a solid ring would hide
/// them; CompoundType is not a token, so skipping the bake would drop the
/// mirror). A resolved-RGB or theme-only LineGradient is sampled into
/// the same band (`tokens.txt` has no LineGradient; a solid LineColor
/// ring would hide the wash). Theme-only LineColor / gradient stops
/// resolve into that PNG the same way canvas `_colourOrTheme` does.
/// FlipY is applied when placing the plate (`_reflectFillRing`)
/// — copying FlipY onto the PNG would mirror the already-placed band
/// twice.
bool _shapeCanLibvisioStrokeReflectionPng(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  if (shape.children.isNotEmpty) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.hasGradient) {
    if (_softEdgesLineColorAt(shape) == null) return false;
  }
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    if (shape.width.abs() <= 1e-9 && shape.height.abs() <= 1e-9) {
      return false;
    }
  } else if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) {
    return false;
  }
  if (shape.line.compoundType != 0) {
    return _softEdgesCompoundRibbonPolygons(shape).isNotEmpty;
  }
  if (_shapeHasSoftEdgesDashes(shape)) {
    return _softEdgesDashRibbonPolygons(shape).isNotEmpty;
  }
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    return _solidStrokeRibbonPolygons(shape).isNotEmpty;
  }
  return _softEdgesStrokeSilhouetteKind(shape) != null;
}

/// Foreign pictures: canvas `_drawReflection` mirrors the bitmap even when
/// Fill and Line are off. Theme-bound pictures still bake — the pixels are
/// already in ForeignData.
bool _shapeCanLibvisioPictureReflectionPng(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.hasImage || shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  if (shape.line.hasLine) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  return true;
}

VsdxShape _reflectionPlateForLibvisioWrite(VsdxShape source,
    {required int id}) {
  final trans = source.reflection.transparency;
  return VsdxShape(
    id: id,
    name: '$kLibvisioReflectionShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _reflectionGeometriesForLibvisioWrite(source),
    fill: source.fill.copyWith(
      foregroundTransparency: _combinedTransparency(
        source.fill.foregroundTransparency,
        trans,
      ),
      backgroundTransparency: _combinedTransparency(
        source.fill.backgroundTransparency,
        trans,
      ),
    ),
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxImage? _imageForLibvisioWrite(ImageRegistry images, String? part) {
  if (part == null || part.isEmpty) return null;
  return images.findByPart(part) ??
      images.findByPart(part.startsWith('/') ? part.substring(1) : '/$part');
}

/// Local box of a Reflection PNG plate: the mirrored, `ReflectionSize`-clipped
/// band shifted down by `ReflectionDist`, grown by [padInches] on every side
/// so the blur halo and the outer stroke half are not clipped.
({double width, double height, double locPinX, double locPinY, double pad})
    _reflectionPlateLocalBox(VsdxShape shape, [double? padInches]) {
  final dist = math.max(shape.reflection.distanceInches, 0.0);
  final frac = shape.reflection.sizeInches.clamp(0.01, 1.0);
  final blur = math.max(shape.reflection.blurInches, 0.0);
  final pad = padInches ?? (blur > 1e-6 ? blur * 3 : 0.0);
  final sourceRing = _reflectionSourceAabbRing(shape);
  var bottom = _paintY(shape, sourceRing.first.y);
  var top = bottom;
  for (final p in sourceRing) {
    final y = _paintY(shape, p.y);
    if (y < bottom) bottom = y;
    if (y > top) top = y;
  }
  final clipH = math.max(top - bottom, 1e-6) * frac;
  final ring = _reflectFillRing(
    sourceRing,
    shape,
    dist: dist,
    clipHeight: clipH,
  );
  var minX = 0.0;
  var maxX = shape.width.abs();
  var minY = -dist - clipH;
  var maxY = -dist;
  if (ring.length >= 2) {
    minX = ring.first.x;
    maxX = minX;
    minY = ring.first.y;
    maxY = minY;
    for (final p in ring) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  final width = math.max(maxX - minX, 1e-6) + 2 * pad;
  final height = math.max(maxY - minY, 1e-6) + 2 * pad;
  return (
    width: width,
    height: height,
    locPinX: shape.effectiveLocPinX - (minX - pad),
    locPinY: shape.effectiveLocPinY - (minY - pad),
    pad: pad,
  );
}

({Uint8List png, double padInches})? _pictureReflectionPngForLibvisioWrite(
  VsdxShape shape,
  VsdxImage image,
) {
  final box = _reflectionPlateLocalBox(shape);
  final trans = _combinedTransparency(
    shape.imageTransparency,
    shape.reflection.transparency,
  );
  final png = bakePictureReflectionPng(
    image: image,
    sizeFraction: shape.reflection.sizeInches.clamp(0.01, 1.0),
    transparency: trans,
    blurSigmaPx: shape.reflection.blurInches * kLibvisioSoftEdgesPxPerInch,
    padInches: box.pad,
    displayWidthInches: shape.width.abs(),
    frameWidthInches: shape.width,
    frameHeightInches: shape.height,
    imgOffsetXInches: shape.imgOffsetXInches,
    imgOffsetYInches: shape.imgOffsetYInches,
    imgWidthInches: shape.imgWidthInches,
    imgHeightInches: shape.imgHeightInches,
    flipY: shape.flipY,
  );
  if (png == null) return null;
  return (png: png, padInches: box.pad);
}

({Uint8List png, double padInches})? _fillReflectionPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final fillPng = _softEdgesPngForLibvisioWrite(shape, theme);
  if (fillPng == null) return null;
  final box = _reflectionPlateLocalBox(shape);
  final png = bakePictureReflectionPng(
    image: VsdxImage(
      partName: '/visio/media/_lo_fill_reflection.png',
      bytes: fillPng,
      mimeType: 'image/png',
    ),
    sizeFraction: shape.reflection.sizeInches.clamp(0.01, 1.0),
    transparency: shape.reflection.transparency,
    blurSigmaPx: shape.reflection.blurInches * kLibvisioSoftEdgesPxPerInch,
    padInches: box.pad,
    displayWidthInches: shape.width.abs(),
    frameWidthInches: shape.width.abs(),
    frameHeightInches: shape.height.abs(),
    flipY: shape.flipY,
    opaqueBackground: true,
  );
  if (png == null) return null;
  return (png: png, padInches: box.pad);
}

({Uint8List png, double padInches})? _strokeReflectionPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  var ribbons = _softEdgesStrokeRibbonPolygons(shape);
  if (ribbons.isEmpty && (shape.is1D || isLibvisioSketchPlate(shape))) {
    ribbons = _solidStrokeRibbonPolygons(shape);
  }
  final kind = (shape.is1D || isLibvisioSketchPlate(shape))
      ? null
      : _softEdgesStrokeSilhouetteKind(shape);
  if (kind == null && ribbons.isEmpty) return null;
  final trans = _combinedTransparency(
    shape.line.transparency,
    shape.reflection.transparency,
  );
  final lineColorAt = shape.line.hasGradient
      ? _softEdgesGradientSampler(
          shape.line.gradient!,
          trans,
          shape.width.abs(),
          math.max(shape.height.abs(), 1e-6),
          theme,
        )
      : null;
  if (shape.line.hasGradient && lineColorAt == null) return null;
  final color = _lineRgbForLibvisioWrite(shape.line, theme);
  final alpha = lineColorAt != null
      ? 255
      : (color.alpha * (1 - trans)).round().clamp(0, 255);
  if (lineColorAt == null && alpha <= 0) return null;
  var originX = 0.0;
  var originY = 0.0;
  var w = shape.width.abs();
  var h = shape.height.abs();
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    final aabb = _polygonsAabb(ribbons);
    if (aabb == null) return null;
    originX = aabb.minX;
    originY = aabb.minY;
    w = math.max(aabb.maxX - aabb.minX, 1e-6);
    h = math.max(aabb.maxY - aabb.minY, 1e-6);
  }
  if (w <= 1e-9 || h <= 1e-9) return null;
  final minPx = (shape.is1D || isLibvisioSketchPlate(shape)) ? 16 : 8;
  var innerWidthPx = math.max(minPx, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx =
      math.max(minPx, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(minPx, (innerWidthPx * scale).round());
    innerHeightPx = math.max(minPx, (innerHeightPx * scale).round());
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final blurInches = math.max(shape.reflection.blurInches, 0.0);
  final padInches = _softEdgesStrokeExtentInches(shape) + blurInches * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final strokeWidthPx = weight / w * innerWidthPx;
  final frac = shape.reflection.sizeInches.clamp(0.01, 1.0);
  final bandHeightPx = math.max(1, (innerHeightPx * frac).round());
  var outer = const <({double x, double y})>[];
  var inner = const <({double x, double y})>[];
  var ribbonPx = const <List<({double x, double y})>>[];
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + (p.x - originX) / w * (innerWidthPx - 1),
        y: padPx + (1 - (p.y - originY) / h) * (innerHeightPx - 1),
      );
  if (ribbons.isNotEmpty) {
    ribbonPx = <List<({double x, double y})>>[
      for (final ribbon in ribbons)
        if (ribbon.length >= 3)
          <({double x, double y})>[
            for (final p in ribbon) toPx(p),
          ],
    ];
    if (ribbonPx.isEmpty) return null;
  } else if (kind == SoftEdgesSilhouetteKind.polygon) {
    final geom = _softEdgesStrokeGeometry(shape);
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    final half = weight / 2;
    final left = offsetPolyline(inches, half, closed: true);
    final right = offsetPolyline(inches, -half, closed: true);
    if (left.length < 3 || right.length < 3) return null;
    outer = <({double x, double y})>[for (final p in left) toPx(p)];
    inner = <({double x, double y})>[for (final p in right) toPx(p)];
  }
  final strokeColorAt = lineColorAt == null
      ? null
      : (double innerX, double innerY) =>
          lineColorAt(innerX, innerY, innerWidthPx, innerHeightPx);
  final png = bakeStrokedReflectionPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    bandHeightPx: bandHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    strokeWidthPx: strokeWidthPx,
    blurSigmaPx: blurInches / w * innerWidthPx,
    kind: kind ?? SoftEdgesSilhouetteKind.rectangle,
    outer: outer,
    inner: inner,
    ribbons: ribbonPx,
    flipVertical: shape.flipY,
    strokeColorAt: strokeColorAt,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

VsdxShape _reflectionPngPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double padInches,
  bool flipY = false,
}) {
  final box = _reflectionPlateLocalBox(source, padInches);
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX,
    pinY: source.pinY,
    width: box.width,
    height: box.height,
    imagePartName: imagePartName,
    name: '$kLibvisioReflectionShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: box.locPinX,
    locPinYInches: box.locPinY,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

int _maxShapeId(List<VsdxShape> shapes) {
  var maxId = 0;
  void walk(VsdxShape shape) {
    if (shape.id > maxId) maxId = shape.id;
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in shapes) {
    walk(shape);
  }
  return maxId;
}

void _collectReflectionPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioReflectionSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectReflectionPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioReflectionBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioReflectionPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioReflectionBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeReflectionTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
  required ImageRegistry images,
  required String Function(int shapeId) allocatePart,
  required void Function(VsdxImage image) addImage,
  required VsdxTheme theme,
}) {
  final out = <VsdxShape>[];
  final delayedReflection = <VsdxShape>[];
  final delayedSketch = <VsdxShape>[];
  var changed = false;
  void flushSketchGroup() {
    if (delayedReflection.isEmpty && delayedSketch.isEmpty) return;
    out.addAll(delayedReflection);
    out.addAll(delayedSketch);
    delayedReflection.clear();
    delayedSketch.clear();
  }

  for (final shape in shapes) {
    if (isLibvisioReflectionPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeReflectionTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
        images: images,
        allocatePart: allocatePart,
        addImage: addImage,
        theme: theme,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    VsdxShape? plate;
    if (shapeNeedsLibvisioReflectionBake(next)) {
      ({Uint8List png, double padInches})? payload;
      var pngPlateFlipY = false;
      if (_shapeCanLibvisioStrokeReflectionPng(next)) {
        payload = _strokeReflectionPngForLibvisioWrite(next, theme);
        // LocPin already follows FlipY via `_reflectFillRing`. Copying
        // FlipY onto the bitmap would mirror the band twice.
        pngPlateFlipY = false;
      } else if (_shapeCanLibvisioPictureReflectionPng(next)) {
        final sourceImage = _imageForLibvisioWrite(images, next.imagePartName);
        if (sourceImage != null) {
          payload = _pictureReflectionPngForLibvisioWrite(next, sourceImage);
          // LocPin already follows FlipY. Copying FlipY onto the bitmap
          // would mirror the band twice.
          pngPlateFlipY = false;
        }
      } else if (_shapeNeedsLibvisioFillReflectionPng(next)) {
        payload = _fillReflectionPngForLibvisioWrite(next, theme);
        pngPlateFlipY = false;
      } else {
        plate = _reflectionPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
        );
        if (plate.geometries.isEmpty) plate = null;
      }
      if (payload != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: payload.png,
            mimeType: 'image/png',
          ),
        );
        plate = _reflectionPngPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          imagePartName: part,
          padInches: payload.padInches,
          flipY: pngPlateFlipY,
        );
      }
      if (plate != null) {
        changed = true;
        // SoftEdges runs after this pass and may drop the fill that
        // `shapeNeedsLibvisioReflectionBake` keys off. Freeze Size=0 on
        // a fill-PNG leftover so the writer cannot resurrect Reflection*
        // (not a token) after the source is hollow.
        if (_shapeNeedsLibvisioFillReflectionPng(next)) {
          next = next.copyWith(
            reflection: next.reflection.copyWith(
              enabled: false,
              sizeInches: 0,
            ),
          );
        }
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            plate = candidate;
            break;
          }
        }
      }
    }
    if (isLibvisioSketchPlate(next)) {
      if (plate != null) delayedReflection.add(plate);
      delayedSketch.add(next);
      if (!identical(next, shape)) changed = true;
      continue;
    }
    flushSketchGroup();
    if (plate != null) out.add(plate);
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  flushSketchGroup();
  return changed ? out : shapes;
}

/// Insert (or strip) the sibling plates Draw uses in place of `Reflection*`.
/// Sketch jiggle copies Reflection* onto those plates; Foreign PNGs
/// composite onto opaque white, so a save hangs every Sketch mirror
/// under both jiggle strokes.
VsdxDocument bakeReflectionForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_reflection_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_reflection_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioReflectionBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectReflectionPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeReflectionTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
      images: registry,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
      theme: document.theme,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Cells Draw will collect. Size is 0 after a sibling-plate bake.
VsdxReflection reflectionForLibvisioWrite(VsdxShape shape) {
  if (!shapeNeedsLibvisioReflectionBake(shape)) return shape.reflection;
  return shape.reflection.copyWith(enabled: false, sizeInches: 0);
}

/// Name prefix of the sibling halo `Glow*` becomes when Line is already painted.
const kLibvisioGlowShapeNamePrefix = 'LibvisioGlow.';

bool isLibvisioGlowPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioGlowShapeNamePrefix);

int? libvisioGlowSourceId(VsdxShape plate) {
  if (!isLibvisioGlowPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioGlowShapeNamePrefix.length),
  );
}

bool _libvisioGlowEffectOn(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  final glow = shape.glow;
  if (!glow.enabled || glow.sizeInches <= 1e-12) return false;
  if (glow.transparency >= 1 - 1e-9) return false;
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    return shape.width.abs() > 1e-9 || shape.height.abs() > 1e-9;
  }
  return shape.width.abs() > 1e-9 && shape.height.abs() > 1e-9;
}

/// `true` when Glow* must become a sibling halo because Line is already in use
/// or because a filled NoLine 2-D / unfilled 2-D stroke can carry the blur
/// as a Gaussian PNG.
///
/// Same-shape `bakeGlowForLibvisio` steals Fill or Line when a PNG plate
/// cannot hang. A default rectangle has both, so Draw would lose the
/// outline if we reused Line. A locked sibling carries the halo as a
/// Gaussian PNG (canvas `_drawGlow`), including theme-only colour
/// resolved through the document theme then Office. Filled NoLine 2-D
/// uses the PNG so Draw does not keep a hard LineWeight outline.
/// Unfilled 2-D uses a PNG ring so Draw does not keep a hard
/// FillForegndTrans ribbon. An unfilled 1-D stroke uses a 2-D PNG plate
/// sized to the glow ribbon (Foreign cannot hang on a zero-height 1-D
/// XForm). Sketch jiggle copies Glow* onto those plates — leftover
/// Geometry is already NoLine — so the same ribbon PNG hangs on a
/// 2-D AABB (1-D Sketch copies are `is1D=false` with Height=0). A
/// Foreign picture uses the same ring around the image frame.
bool shapeNeedsLibvisioGlowPlateBake(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    return _shapeCanLibvisioGlowStrokePng(shape);
  }
  if (_shapeCanLibvisioGlowPng(shape)) return true;
  if (_shapeCanLibvisioGlowStrokePng(shape)) return true;
  if (_shapeCanLibvisioGlowPicturePng(shape)) return true;
  final paintsFill = _shapePaintsFill(shape, shape.geometries);
  if (!paintsFill && !shape.hasImage) return false;
  return shape.line.hasLine;
}

bool _shapeCanLibvisioGlowPng(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (shape.is1D || shape.hasImage) return false;
  if (!_shapePaintsFill(shape, shape.geometries)) return false;
  return _softEdgesSilhouetteKind(shape) != null;
}

/// Unfilled 2-D and 1-D with a stroke: canvas `_drawGlow` blurs a path
/// stroke, not a filled silhouette (that would paint the interior).
/// CompoundType rails are not a token, but the halo is still the path —
/// skipping the bake would drop the glow. 1-D uses a 2-D plate sized to
/// the glow ribbon (canvas inflates zero-area bounds by the glow stroke;
/// a Foreign picture cannot hang on a zero-height 1-D XForm). Sketch
/// jiggle plates use the same ribbon (open LinePattern=1 has no
/// `_softEdgesStrokeSilhouetteKind`). Theme-only colour resolves into
/// the PNG the same way canvas `_colourOrTheme` does.
bool _shapeCanLibvisioGlowStrokePng(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (shape.hasImage) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    return _glowStrokeRibbonPolygons(shape).isNotEmpty;
  }
  return _softEdgesStrokeSilhouetteKind(shape) != null;
}

/// Foreign pictures: canvas `_drawGlow` blurs the image-frame path even
/// when Fill and Line are off. The plate is 2-D, so a Gaussian PNG ring
/// can hang beside the bitmap. Theme-only colour resolves into that PNG.
bool _shapeCanLibvisioGlowPicturePng(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (!shape.hasImage || shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  return _foreignFrameSilhouetteKind(shape) != null;
}

bool _shapeNeedsLibvisioGlowPngBake(VsdxShape shape) =>
    _shapeCanLibvisioGlowPng(shape) ||
    _shapeCanLibvisioGlowStrokePng(shape) ||
    _shapeCanLibvisioGlowPicturePng(shape);

/// RGB canvas `_colourOrTheme` would paint. Theme-only Glow* is not a
/// token, so Draw never sees THEMEVAL() here — resolve the slot through
/// [theme], then Office, then the same amber fallback `_drawGlow` uses.
VsdxColor _glowRgbForLibvisioWrite(VsdxGlow glow, VsdxTheme theme) {
  if (glow.color != null) return glow.color!;
  final slot = glow.themeColorIndex;
  if (slot == null) return _kLibvisioGlowFallback;
  return theme.resolve(slot) ??
      VsdxTheme.office.resolve(slot) ??
      _kLibvisioGlowFallback;
}

/// RGB canvas `_colourOrTheme` would stroke. Theme-only LineColor still
/// has to freeze into a Reflection / SoftEdges PNG because those cells
/// are not tokens.
VsdxColor _lineRgbForLibvisioWrite(
  VsdxLine line, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (line.color != null) return line.color!;
  final slot = line.themeColorIndex;
  if (slot == null) return const VsdxColor(0xFF000000);
  return theme.resolve(slot) ??
      VsdxTheme.office.resolve(slot) ??
      const VsdxColor(0xFF000000);
}

/// RGB canvas `_fillColour` would paint. Theme-only FillForegnd still
/// has to freeze into a SoftEdges PNG because `SoftEdgesSize` is not a
/// token.
VsdxColor _fillRgbForLibvisioWrite(
  VsdxFill fill,
  VsdxTheme theme, {
  int? fillMatrix,
}) {
  if (fill.foreground != null) return fill.foreground!;
  final slot = fill.themeForegroundIndex;
  if (slot == null) return const VsdxColor(0xFFFFFFFF);
  return theme.resolveFill(slot, fillMatrix: fillMatrix) ??
      VsdxTheme.office.resolveFill(slot, fillMatrix: fillMatrix) ??
      VsdxTheme.office.resolve(slot) ??
      const VsdxColor(0xFFFFFFFF);
}

/// Hatch `FillBkgnd` canvas would sample. Theme-only background still
/// has to freeze into a SoftEdges PNG with the hatch foreground.
VsdxColor? _fillBackgroundRgbForLibvisioWrite(VsdxFill fill, VsdxTheme theme) {
  if (fill.background != null) return fill.background;
  final slot = fill.themeBackgroundIndex;
  if (slot == null) return null;
  return theme.resolve(slot) ?? VsdxTheme.office.resolve(slot);
}

/// RGB canvas `_colourOrTheme` would sample at a gradient stop. Theme-only
/// GradientStopColor is not a token (`FillGradient` / `LineGradient` never
/// reach `VSDContentCollector`), so SoftEdges / Reflection PNGs freeze the
/// slot through [theme], then Office.
VsdxColor? _gradientStopRgbForLibvisioWrite(
  VsdxGradientStop stop,
  VsdxTheme theme,
) {
  if (stop.color != null) return stop.color;
  final slot = stop.themeColorIndex;
  if (slot == null) return null;
  return theme.resolve(slot) ?? VsdxTheme.office.resolve(slot);
}

({Uint8List png, double padInches})? _glowPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final kind = _softEdgesSilhouetteKind(shape);
  if (kind == null) return null;
  final color = _glowRgbForLibvisioWrite(shape.glow, theme);
  final trans = _glowHaloTransparency(shape.glow).clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.glow.sizeInches / w * innerWidthPx;
  final padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  final polygon = <({double x, double y})>[];
  var evenOddPolygons = const <List<({double x, double y})>>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    final rings = _softEdgesFillPolygonsInches(shape);
    if (rings == null) return null;
    evenOddPolygons = _softEdgesRingsToPx(
      rings,
      w: w,
      h: h,
      widthPx: innerWidthPx,
      heightPx: innerHeightPx,
    );
    polygon.addAll(evenOddPolygons.first);
  }
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: kind,
    polygon: polygon,
    evenOddPolygons: evenOddPolygons,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

List<List<Offset2D>> _glowStrokeRibbonPolygons(VsdxShape shape) {
  return _solidStrokeRibbonPolygons(
    shape,
    halfWidth: math.max(shape.glow.sizeInches, 0.01),
  );
}

({double width, double height, double locPinX, double locPinY})
    _glowStrokePlateLocalBox(VsdxShape shape, double padInches) {
  final pad = padInches < 0 ? 0.0 : padInches;
  final aabb = _polygonsAabb(_glowStrokeRibbonPolygons(shape));
  if (aabb == null) {
    return (
      width: math.max(shape.width.abs(), 1e-6) + 2 * pad,
      height:
          math.max(2 * math.max(shape.glow.sizeInches, 0.01), 1e-6) + 2 * pad,
      locPinX: shape.effectiveLocPinX + pad,
      locPinY: shape.effectiveLocPinY + pad,
    );
  }
  return (
    width: math.max(aabb.maxX - aabb.minX, 1e-6) + 2 * pad,
    height: math.max(aabb.maxY - aabb.minY, 1e-6) + 2 * pad,
    locPinX: shape.effectiveLocPinX - (aabb.minX - pad),
    locPinY: shape.effectiveLocPinY - (aabb.minY - pad),
  );
}

({Uint8List png, double padInches})? _glow1dStrokePngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final ribbons = _glowStrokeRibbonPolygons(shape);
  final aabb = _polygonsAabb(ribbons);
  if (aabb == null) return null;
  final color = _glowRgbForLibvisioWrite(shape.glow, theme);
  final trans = _glowHaloTransparency(shape.glow).clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  if (alpha <= 0) return null;
  final originX = aabb.minX;
  final originY = aabb.minY;
  final w = math.max(aabb.maxX - aabb.minX, 1e-6);
  final h = math.max(aabb.maxY - aabb.minY, 1e-6);
  const minPx = 16;
  var innerWidthPx = math.max(minPx, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx =
      math.max(minPx, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(minPx, (innerWidthPx * scale).round());
    innerHeightPx = math.max(minPx, (innerHeightPx * scale).round());
  }
  final padInches = shape.glow.sizeInches * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final sigmaPx = shape.glow.sizeInches / w * innerWidthPx;
  final strokeWidthPx =
      math.max(shape.glow.sizeInches * 2, 0.02) / w * innerWidthPx;
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + (p.x - originX) / w * (innerWidthPx - 1),
        y: padPx + (1 - (p.y - originY) / h) * (innerHeightPx - 1),
      );
  final ribbonPx = <List<({double x, double y})>>[
    for (final ribbon in ribbons)
      if (ribbon.length >= 3)
        <({double x, double y})>[for (final p in ribbon) toPx(p)],
  ];
  if (ribbonPx.isEmpty) return null;
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    ribbons: ribbonPx,
    gaussianBlur: true,
  );
  if (png == null) return null;
  return (png: png, padInches: padInches);
}

({Uint8List png, double padInches})? _glowStrokePngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  if (shape.is1D || isLibvisioSketchPlate(shape)) {
    return _glow1dStrokePngForLibvisioWrite(shape, theme);
  }
  final kind = _softEdgesStrokeSilhouetteKind(shape) ??
      _foreignFrameSilhouetteKind(shape);
  if (kind == null) return null;
  final color = _glowRgbForLibvisioWrite(shape.glow, theme);
  final trans = _glowHaloTransparency(shape.glow).clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final strokeInches = math.max(shape.glow.sizeInches * 2, 0.02);
  final sigmaPx = shape.glow.sizeInches / w * innerWidthPx;
  final padInches = strokeInches / 2 + shape.glow.sizeInches * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final strokeWidthPx = strokeInches / w * innerWidthPx;
  var outer = const <({double x, double y})>[];
  var inner = const <({double x, double y})>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    final geom = _softEdgesStrokeGeometry(shape);
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    final half = strokeInches / 2;
    final left = offsetPolyline(inches, half, closed: true);
    final right = offsetPolyline(inches, -half, closed: true);
    if (left.length < 3 || right.length < 3) return null;
    ({double x, double y}) toPx(Offset2D p) => (
          x: padPx + p.x / w * (innerWidthPx - 1),
          y: padPx + (1 - p.y / h) * (innerHeightPx - 1),
        );
    outer = <({double x, double y})>[for (final p in left) toPx(p)];
    inner = <({double x, double y})>[for (final p in right) toPx(p)];
  }
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    kind: kind,
    outer: outer,
    inner: inner,
    gaussianBlur: true,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

List<VsdxGeometry> _glowPlateGeometriesForLibvisioWrite(VsdxShape shape) {
  final out = <VsdxGeometry>[
    for (final geometry in shape.geometries)
      if (!geometry.noShow && !geometry.noFill)
        geometry.copyWith(noFill: true, noLine: false),
  ];
  if (out.isNotEmpty) return out;
  return <VsdxGeometry>[
    VsdxGeometry(
      noFill: true,
      noLine: false,
      commands: <VsdxPathCommand>[
        const MoveTo(0, 0),
        LineTo(shape.width, 0),
        LineTo(shape.width, shape.height),
        LineTo(0, shape.height),
        const LineTo(0, 0),
      ],
    ),
  ];
}

VsdxShape _glowPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required VsdxTheme theme,
}) {
  return VsdxShape(
    id: id,
    name: '$kLibvisioGlowShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _glowPlateGeometriesForLibvisioWrite(source),
    fill: const VsdxFill(pattern: 0),
    line: _glowLineForLibvisio(
      source.line.copyWith(
        compoundType: 0,
        beginArrow: 0,
        endArrow: 0,
        pattern: 1,
      ),
      source.glow,
      theme,
    ),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _glowPngPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double padInches,
}) {
  final pad = padInches < 0 ? 0.0 : padInches;
  final box = (source.is1D || isLibvisioSketchPlate(source))
      ? _glowStrokePlateLocalBox(source, pad)
      : (
          width: source.width.abs() + pad * 2,
          height: source.height.abs() + pad * 2,
          locPinX: pad > 1e-12
              ? source.effectiveLocPinX + pad
              : source.locPinXInches,
          locPinY: pad > 1e-12
              ? source.effectiveLocPinY + pad
              : source.locPinYInches,
        );
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX,
    pinY: source.pinY,
    width: box.width,
    height: box.height,
    imagePartName: imagePartName,
    name: '$kLibvisioGlowShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: box.locPinX,
    locPinYInches: box.locPinY,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

void _collectGlowPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioGlowSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectGlowPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioGlowPlateBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioGlowPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioGlowPlateBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeGlowPlateTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
  required String Function(int shapeId) allocatePart,
  required void Function(VsdxImage image) addImage,
  required VsdxTheme theme,
}) {
  final out = <VsdxShape>[];
  final delayedGlow = <VsdxShape>[];
  final delayedSketch = <VsdxShape>[];
  var changed = false;
  void flushSketchGroup() {
    if (delayedGlow.isEmpty && delayedSketch.isEmpty) return;
    out.addAll(delayedGlow);
    out.addAll(delayedSketch);
    delayedGlow.clear();
    delayedSketch.clear();
  }

  for (final shape in shapes) {
    if (isLibvisioGlowPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeGlowPlateTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
        allocatePart: allocatePart,
        addImage: addImage,
        theme: theme,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    VsdxShape? plate;
    if (shapeNeedsLibvisioGlowPlateBake(next)) {
      if (_shapeNeedsLibvisioGlowPngBake(next)) {
        final payload = _shapeCanLibvisioGlowPng(next)
            ? _glowPngForLibvisioWrite(next, theme)
            : _glowStrokePngForLibvisioWrite(next, theme);
        if (payload != null) {
          final part = allocatePart(next.id);
          addImage(
            VsdxImage(
              partName: part,
              bytes: payload.png,
              mimeType: 'image/png',
            ),
          );
          plate = _glowPngPlateForLibvisioWrite(
            next,
            id: plateIds[next.id] ?? nextId(),
            imagePartName: part,
            padInches: payload.padInches,
          );
        }
      }
      if (plate == null && !_shapeNeedsLibvisioGlowPngBake(next)) {
        plate = _glowPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          theme: theme,
        );
      }
      if (plate != null && plate.geometries.isEmpty && !plate.hasImage) {
        plate = null;
      }
      if (plate != null) changed = true;
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            plate = candidate;
            break;
          }
        }
      }
    }
    if (isLibvisioSketchPlate(next)) {
      if (plate != null) delayedGlow.add(plate);
      delayedSketch.add(next);
      if (!identical(next, shape)) changed = true;
      continue;
    }
    flushSketchGroup();
    if (plate != null) out.add(plate);
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  flushSketchGroup();
  return changed ? out : shapes;
}

/// Insert (or keep) the sibling halos Draw uses when Glow cannot steal Line,
/// including the Gaussian PNG a filled NoLine 2-D, unfilled 2-D stroke,
/// or unfilled 1-D stroke uses. Sketch jiggle copies Glow* onto those
/// plates; their Foreign PNGs composite onto opaque white, so a save
/// hangs every Sketch glow under both jiggle strokes instead of
/// interleaving plates that would cover the first pass.
VsdxDocument bakeGlowPlateForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_glow_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_glow_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioGlowPlateBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectGlowPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeGlowPlateTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
      theme: document.theme,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Name prefix of the jiggle strokes `User.veSketch` becomes for Draw.
const kLibvisioSketchShapeNamePrefix = 'LibvisioSketch.';

/// Pixel density canvas / SVG use for draw.io jiggle, so the baked offsets
/// match the editor's two-pass Sketch treatment.
const kLibvisioSketchPxPerInch = 96.0;

bool isLibvisioSketchPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioSketchShapeNamePrefix);

int? libvisioSketchSourceId(VsdxShape plate) {
  if (!isLibvisioSketchPlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

/// Name prefix of the top-light sibling `User.veGlass` becomes for Draw.
const kLibvisioGlassShapeNamePrefix = 'LibvisioGlass.';

bool isLibvisioGlassPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioGlassShapeNamePrefix);

int? libvisioGlassSourceId(VsdxShape plate) {
  if (!isLibvisioGlassPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioGlassShapeNamePrefix.length),
  );
}

/// Name prefix of the text-frame stroke `User.veLabelBorderColor` becomes.
const kLibvisioLabelBorderShapeNamePrefix = 'LibvisioLabelBorder.';

/// Name prefix of the filled-shape stroke ribbon Draw uses for LineColorTrans.
const kLibvisioStrokeRibbonShapeNamePrefix = 'LibvisioStrokeRibbon.';

/// Pixel density canvas / SVG use for the 1px label-border hairline.
const kLibvisioLabelBorderPxPerInch = 96.0;

/// Pixel density canvas / SVG use for draw.io `labelPadding`.
const kLibvisioLabelPaddingPxPerInch = 96.0;

/// Name prefix of the feathered PNG sibling geometry SoftEdges becomes.
const kLibvisioSoftEdgesShapeNamePrefix = 'LibvisioSoftEdges.';

/// Pixel density of the SourceAlpha PNG geometry SoftEdges bakes for Draw.
const kLibvisioSoftEdgesPxPerInch = 96.0;

/// Name prefix of the Gaussian PNG sibling ShadowBlur becomes.
const kLibvisioShadowShapeNamePrefix = 'LibvisioShadow.';

bool isLibvisioSoftEdgesPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioSoftEdgesShapeNamePrefix);

int? libvisioSoftEdgesSourceId(VsdxShape plate) {
  if (!isLibvisioSoftEdgesPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioSoftEdgesShapeNamePrefix.length),
  );
}

/// Name prefix of the per-run siblings mixed Character Highlight becomes.
const kLibvisioHighlightShapeNamePrefix = 'LibvisioHighlight.';

bool isLibvisioHighlightPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioHighlightShapeNamePrefix);

int? libvisioHighlightSourceId(VsdxShape plate) {
  if (!isLibvisioHighlightPlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

/// `true` when a save already inserted Highlight siblings for [sourceId].
bool pageHasLibvisioHighlightPlate(VsdxPage page, int sourceId) {
  bool walk(VsdxShape shape) {
    if (libvisioHighlightSourceId(shape) == sourceId) return true;
    for (final child in shape.children) {
      if (walk(child)) return true;
    }
    return false;
  }

  for (final shape in page.shapes) {
    if (walk(shape)) return true;
  }
  return false;
}

/// Name prefix of the per-glyph siblings `User.veCurvedText` becomes.
const kLibvisioCurvedTextShapeNamePrefix = 'LibvisioCurved.';

bool isLibvisioCurvedTextPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioCurvedTextShapeNamePrefix);

int? libvisioCurvedTextSourceId(VsdxShape plate) {
  if (!isLibvisioCurvedTextPlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

/// Name prefix of the per-line siblings `User.veShapeInside` becomes.
const kLibvisioShapeInsideShapeNamePrefix = 'LibvisioShapeInside.';

/// Pixel density canvas / SVG use for draw.io `shapeInside` padding.
const kLibvisioShapeInsidePxPerInch = 96.0;

bool isLibvisioShapeInsidePlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioShapeInsideShapeNamePrefix);

int? libvisioShapeInsideSourceId(VsdxShape plate) {
  if (!isLibvisioShapeInsidePlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

bool isLibvisioShadowPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioShadowShapeNamePrefix);

int? libvisioShadowSourceId(VsdxShape plate) {
  if (!isLibvisioShadowPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioShadowShapeNamePrefix.length),
  );
}

bool isLibvisioLabelBorderPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioLabelBorderShapeNamePrefix);

int? libvisioLabelBorderSourceId(VsdxShape plate) {
  if (!isLibvisioLabelBorderPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioLabelBorderShapeNamePrefix.length),
  );
}

bool isLibvisioStrokeRibbonPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioStrokeRibbonShapeNamePrefix);

int? libvisioStrokeRibbonSourceId(VsdxShape plate) {
  if (!isLibvisioStrokeRibbonPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioStrokeRibbonShapeNamePrefix.length),
  );
}

/// `true` when [shape] is a render-only sibling a save added for Draw.
///
/// These plates carry an effect `tokens.txt` cannot express, so they appear
/// in the saved package (and therefore after a reopen) even though the
/// authoring model only had the effect cell. Round-trip checks should skip
/// them; a second save recognises and reuses them instead of stacking.
bool isLibvisioBakePlate(VsdxShape shape) =>
    isLibvisioSketchPlate(shape) ||
    isLibvisioGlowPlate(shape) ||
    isLibvisioReflectionPlate(shape) ||
    isLibvisioGlassPlate(shape) ||
    isLibvisioLabelBorderPlate(shape) ||
    isLibvisioStrokeRibbonPlate(shape) ||
    isLibvisioSoftEdgesPlate(shape) ||
    isLibvisioShadowPlate(shape) ||
    isLibvisioPageShadowPlate(shape) ||
    isLibvisioCurvedTextPlate(shape) ||
    isLibvisioShapeInsidePlate(shape) ||
    isLibvisioHighlightPlate(shape) ||
    shape.name == kLibvisioPageColorShapeName;

bool _isLibvisioBakePlate(VsdxShape shape) => isLibvisioBakePlate(shape);

bool shapeNeedsLibvisioSketchStrokeBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.sketchEffect) return false;
  if (!shape.line.hasLine) return false;
  return shape.width.abs() > 1e-12 || shape.height.abs() > 1e-12;
}

bool shapeNeedsLibvisioSketchFillBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  return shape.usesSketchPatternFill;
}

bool shapeNeedsLibvisioSketchBake(VsdxShape shape) =>
    shapeNeedsLibvisioSketchStrokeBake(shape) ||
    shapeNeedsLibvisioSketchFillBake(shape);

double _hatchAngleDelta(double a, double b) {
  var d = (a - b) % 180.0;
  if (d < 0) d += 180.0;
  if (d > 90.0) d = 180.0 - d;
  return d;
}

/// Classic FillPattern 2–24 whose hatch is closest to the sketch fill.
int? sketchFillPatternForLibvisioWrite(VsdxShape shape) {
  if (!shape.usesSketchPatternFill) return null;
  final dense = shape.sketchHachureGapPx / kLibvisioSketchPxPerInch < 0.075;
  final style = switch (shape.effectiveSketchFillStyle) {
    VsdxSketchFillStyle.crossHatch => VsdxHatchStyle.double,
    VsdxSketchFillStyle.dots => VsdxHatchStyle.triple,
    VsdxSketchFillStyle.hachure ||
    VsdxSketchFillStyle.auto ||
    VsdxSketchFillStyle.solid =>
      VsdxHatchStyle.single,
  };
  final angle = shape.sketchHachureAngleDegrees;
  var bestId = dense ? 13 : 6;
  var bestDelta = 1e9;
  for (var id = 2; id <= 24; id++) {
    final spec = libvisioHatchSpec(id);
    if (spec == null || spec.style != style) continue;
    if ((spec.distanceInches < 0.075) != dense) continue;
    final delta = _hatchAngleDelta(angle, spec.angleDegrees.toDouble());
    if (delta < bestDelta) {
      bestDelta = delta;
      bestId = id;
    }
  }
  return bestId;
}

VsdxPathCommand _translateSketchCommand(
  VsdxPathCommand command, {
  required double dx,
  required double dy,
  required double width,
  required double height,
}) {
  Offset2D shift(double x, double y, {bool relX = false, bool relY = false}) {
    final ox = relX ? (width.abs() < 1e-12 ? 0.0 : dx / width) : dx;
    final oy = relY ? (height.abs() < 1e-12 ? 0.0 : dy / height) : dy;
    return Offset2D(x + ox, y + oy);
  }

  return switch (command) {
    MoveTo(:final x, :final y) => MoveTo(shift(x, y).x, shift(x, y).y),
    LineTo(:final x, :final y) => LineTo(shift(x, y).x, shift(x, y).y),
    RelMoveTo(:final fx, :final fy) => RelMoveTo(
        shift(fx, fy, relX: true, relY: true).x,
        shift(fx, fy, relX: true, relY: true).y,
      ),
    RelLineTo(:final fx, :final fy) => RelLineTo(
        shift(fx, fy, relX: true, relY: true).x,
        shift(fx, fy, relX: true, relY: true).y,
      ),
    CubBezTo(:final x, :final y, :final x1, :final y1, :final x2, :final y2) =>
      CubBezTo(
        x: shift(x, y).x,
        y: shift(x, y).y,
        x1: shift(x1, y1).x,
        y1: shift(x1, y1).y,
        x2: shift(x2, y2).x,
        y2: shift(x2, y2).y,
      ),
    RelCubBezTo(
      :final fx,
      :final fy,
      :final fx1,
      :final fy1,
      :final fx2,
      :final fy2,
    ) =>
      RelCubBezTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fx1: shift(fx1, fy1, relX: true, relY: true).x,
        fy1: shift(fx1, fy1, relX: true, relY: true).y,
        fx2: shift(fx2, fy2, relX: true, relY: true).x,
        fy2: shift(fx2, fy2, relX: true, relY: true).y,
      ),
    QuadBezTo(:final x, :final y, :final x1, :final y1) => QuadBezTo(
        x: shift(x, y).x,
        y: shift(x, y).y,
        x1: shift(x1, y1).x,
        y1: shift(x1, y1).y,
      ),
    RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1) => RelQuadBezTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fx1: shift(fx1, fy1, relX: true, relY: true).x,
        fy1: shift(fx1, fy1, relX: true, relY: true).y,
      ),
    ArcTo(:final x, :final y, :final bow) =>
      ArcTo(x: shift(x, y).x, y: shift(x, y).y, bow: bow),
    RelArcTo(:final fx, :final fy, :final fbow) => RelArcTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fbow: fbow,
      ),
    EllipticalArcTo(
      :final x,
      :final y,
      :final controlX,
      :final controlY,
      :final angle,
      :final eccentricity,
    ) =>
      EllipticalArcTo(
        x: shift(x, y).x,
        y: shift(x, y).y,
        controlX: shift(controlX, controlY).x,
        controlY: shift(controlX, controlY).y,
        angle: angle,
        eccentricity: eccentricity,
      ),
    RelEllipticalArcTo(
      :final fx,
      :final fy,
      :final fcx,
      :final fcy,
      :final angle,
      :final eccentricity,
    ) =>
      RelEllipticalArcTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fcx: shift(fcx, fcy, relX: true, relY: true).x,
        fcy: shift(fcx, fcy, relX: true, relY: true).y,
        angle: angle,
        eccentricity: eccentricity,
      ),
    EllipseCmd(
      :final cx,
      :final cy,
      :final aX,
      :final aY,
      :final bX,
      :final bY
    ) =>
      EllipseCmd(
        cx: shift(cx, cy).x,
        cy: shift(cx, cy).y,
        aX: shift(aX, aY).x,
        aY: shift(aX, aY).y,
        bX: shift(bX, bY).x,
        bY: shift(bX, bY).y,
      ),
    PolylineTo(
      :final x,
      :final y,
      :final vertices,
      :final relative,
      :final vertsRelative,
      :final vertsYRelative,
    ) =>
      PolylineTo(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        vertices: <Offset2D>[
          for (final v in vertices)
            shift(v.x, v.y, relX: vertsRelative, relY: vertsYRelative),
        ],
        relative: relative,
        vertsRelative: vertsRelative,
        vertsYRelative: vertsYRelative,
      ),
    InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative) =>
      InfiniteLineCmd(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        a: shift(a, b, relX: relative, relY: relative).x,
        b: shift(a, b, relX: relative, relY: relative).y,
        relative: relative,
      ),
    SplineStart(
      :final x,
      :final y,
      :final a,
      :final b,
      :final c,
      :final degree,
      :final relative,
    ) =>
      SplineStart(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        a: a,
        b: b,
        c: c,
        degree: degree,
        relative: relative,
      ),
    SplineKnot(:final x, :final y, :final knot, :final relative) => SplineKnot(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        knot: knot,
        relative: relative,
      ),
    NurbsTo(
      :final x,
      :final y,
      :final controlPoints,
      :final weights,
      :final knots,
      :final degree,
      :final relative,
      :final cpRelative,
      :final cpYRelative,
    ) =>
      NurbsTo(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        controlPoints: <Offset2D>[
          for (final p in controlPoints)
            shift(p.x, p.y, relX: cpRelative, relY: cpYRelative),
        ],
        weights: weights,
        knots: knots,
        degree: degree,
        relative: relative,
        cpRelative: cpRelative,
        cpYRelative: cpYRelative,
      ),
  };
}

VsdxGeometry _translateSketchGeometry(
  VsdxGeometry geometry,
  Offset2D offset,
  VsdxShape shape,
) {
  return geometry.copyWith(
    noFill: true,
    noLine: false,
    commandFormulas: const <Map<String, String>>[],
    commands: <VsdxPathCommand>[
      for (final command in geometry.commands)
        _translateSketchCommand(
          command,
          dx: offset.x,
          dy: offset.y,
          width: shape.width,
          height: shape.height,
        ),
    ],
  );
}

List<VsdxGeometry> _sketchStrokeGeometriesForLibvisioWrite(
  VsdxShape shape,
  Offset2D offset,
) {
  final fromLine = <VsdxGeometry>[
    for (final geometry in shape.geometries)
      if (!geometry.noShow && !geometry.noLine && !geometry.hitBox)
        _translateSketchGeometry(geometry, offset, shape),
  ];
  if (fromLine.isNotEmpty) return fromLine;
  return <VsdxGeometry>[
    for (final geometry in shape.geometries)
      if (!geometry.noShow && !geometry.noFill)
        _translateSketchGeometry(geometry, offset, shape),
  ];
}

VsdxShape _sketchPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required int pass,
  required Offset2D offset,
}) {
  return VsdxShape(
    id: id,
    name: '$kLibvisioSketchShapeNamePrefix$pass.${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _sketchStrokeGeometriesForLibvisioWrite(source, offset),
    fill: const VsdxFill(pattern: 0),
    line: source.line.copyWith(beginArrow: 0, endArrow: 0),
    glow: source.glow,
    reflection: source.reflection,
    userCells: _sketchPlateUserCells(source),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

/// Dash / Flow Animation User rows the jiggle must keep so write-time
/// flatten can see them. Leftover Geometry is already NoLine. Flow rows
/// copy only from a glueable source — Sketch plates are `is1D=false`.
List<VsdxUserCell> _sketchPlateUserCells(VsdxShape source) {
  const dashKeep = <String>{
    VsdxShape.userDashPattern,
    VsdxShape.userFixedDash,
  };
  const flowKeep = <String>{
    VsdxShape.userFlowAnimation,
    VsdxShape.userFlowAnimationDuration,
    VsdxShape.userFlowAnimationTiming,
    VsdxShape.userFlowAnimationDirection,
  };
  return <VsdxUserCell>[
    for (final cell in source.userCells)
      if (dashKeep.contains(cell.name) ||
          (source.supportsFlowAnimation && flowKeep.contains(cell.name)))
        cell,
  ];
}

VsdxShape _sourceForLibvisioSketchWrite(VsdxShape shape) {
  var next = shape;
  if (shapeNeedsLibvisioSketchStrokeBake(shape)) {
    var geoms = <VsdxGeometry>[
      for (final geometry in shape.geometries)
        geometry.noLine ? geometry : geometry.copyWith(noLine: true),
    ];
    var line = shape.line;
    if (_hasArrowheads(shape.line) && _shapeHasOpenLineEndings(shape)) {
      final arrows = bakeArrowGeometriesForLibvisio(shape);
      if (arrows.isNotEmpty) {
        geoms = <VsdxGeometry>[...geoms, ...arrows];
        line = line.copyWith(beginArrow: 0, endArrow: 0);
        if (!next.fill.hasFill) {
          next = next.copyWith(
            fill: VsdxFill(
              foreground: _lineRgbForLibvisioWrite(line),
              pattern: 1,
              foregroundTransparency: line.transparency.clamp(0.0, 1.0),
            ),
          );
        }
      }
    }
    next = next.copyWith(geometries: geoms, line: line);
  }
  final pattern = sketchFillPatternForLibvisioWrite(shape);
  if (pattern != null) {
    next = next.copyWith(
      fill: next.fill.copyWith(
        pattern: pattern,
        backgroundTransparency: 1,
        gradient: null,
      ),
    );
  }
  // Stroke Glow / Reflection already live on the jiggle plates. Freeze
  // them on a hollow leftover so the writer cannot resurrect Glow* /
  // Reflection* (not tokens) after Geometry is NoLine. A leftover that
  // still paints fill keeps the cells for the fill PNG pass.
  if (!_shapePaintsFill(next, next.geometries)) {
    next = next.copyWith(
      glow: next.glow.copyWith(enabled: false, sizeInches: 0),
      reflection: next.reflection.copyWith(enabled: false, sizeInches: 0),
    );
  }
  final others = <VsdxUserCell>[
    for (final cell in next.userCells)
      if (cell.name != VsdxShape.userSketchEffect) cell,
  ];
  return next.copyWith(
    userCells: <VsdxUserCell>[
      ...others,
      const VsdxUserCell(name: VsdxShape.userSketchEffect, value: '0'),
    ],
  );
}

void _collectSketchPlateIds(List<VsdxShape> shapes, Map<String, int> into) {
  for (final shape in shapes) {
    if (isLibvisioSketchPlate(shape)) into[shape.name] = shape.id;
    _collectSketchPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioSketchBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioSketchPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioSketchBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeSketchTree(
  List<VsdxShape> shapes, {
  required Map<String, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioSketchPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeSketchTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioSketchBake(next)) {
      final source = _sourceForLibvisioSketchWrite(next);
      out.add(source);
      if (shapeNeedsLibvisioSketchStrokeBake(next)) {
        final offsets = drawioSketchStrokeOffsets(
          next.id,
          next.sketchJiggle,
          pxPerInch: kLibvisioSketchPxPerInch,
        );
        for (var pass = 0; pass < offsets.length; pass++) {
          final name = '$kLibvisioSketchShapeNamePrefix$pass.${next.id}';
          final plate = _sketchPlateForLibvisioWrite(
            next,
            id: plateIds[name] ?? nextId(),
            pass: pass,
            offset: offsets[pass],
          );
          if (plate.geometries.isNotEmpty) {
            out.add(plate);
            changed = true;
          }
        }
      }
      changed = true;
      continue;
    }
    final kept = <VsdxShape>[];
    for (var pass = 0; pass < 2; pass++) {
      final name = '$kLibvisioSketchShapeNamePrefix$pass.${next.id}';
      final existingId = plateIds[name];
      if (existingId == null) continue;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept.add(candidate);
          break;
        }
      }
    }
    out.add(next);
    out.addAll(kept);
    if (kept.isNotEmpty || !identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeSketchPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioSketchBake(page)) return page;
  final plateIds = <String, int>{};
  _collectSketchPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeSketchTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the Sketch strokes / hatch Draw can actually collect.
VsdxDocument bakeSketchForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeSketchPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Canvas / SVG glass highlight uses `(1 - FillForegndTrans) * colour.alpha`.
double _glassFillOpacity(VsdxShape shape) {
  var alpha = 1 - shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final color = shape.fill.foreground;
  if (color != null) alpha *= color.alpha / 255.0;
  return alpha.clamp(0.0, 1.0);
}

/// `true` when `User.veGlass` must become a sibling Draw can actually fill.
///
/// libvisio never reads User rows. Fill is shape-level, so the white wave
/// cannot share the source; a locked NoLine sibling carries a white
/// FillForegndTrans sheen matching the canvas 0.9→0.1 top-light average,
/// then `veGlass` is written 0. A classic FillPattern 25–40 would move
/// those trans values onto gradient stops at parse, and a second save
/// would write opaque white.
bool shapeNeedsLibvisioGlassBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.glassEffect) return false;
  if (!shape.supportsGlassEffect) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  return _glassFillOpacity(shape) > 1e-9;
}

List<VsdxPathCommand> _glassHighlightCommands(VsdxShape shape) {
  final w = shape.width.abs() < 1e-12 ? 1.0 : shape.width;
  final h = shape.height.abs() < 1e-12 ? 1.0 : shape.height;
  final sw = math.max(0.0, shape.line.weightInches / 2);
  final x0 = -sw / w;
  final x1 = (w + sw) / w;
  final yTop = (h + sw) / h;
  return <VsdxPathCommand>[
    RelMoveTo(x0, yTop),
    RelLineTo(x0, 0.6),
    RelQuadBezTo(fx: x1, fy: 0.6, fx1: 0.5, fy1: 0.3),
    RelLineTo(x1, yTop),
    RelLineTo(x0, yTop),
  ];
}

VsdxFill _glassHighlightFill(VsdxShape source) {
  final alpha = _glassFillOpacity(source);
  return VsdxFill(
    foreground: VsdxColor.white,
    pattern: 1,
    foregroundTransparency: (1 - 0.55 * alpha).clamp(0.0, 1.0),
  );
}

VsdxShape _glassPlateForLibvisioWrite(VsdxShape source, {required int id}) {
  return VsdxShape(
    id: id,
    name: '$kLibvisioGlassShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: <VsdxGeometry>[
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: _glassHighlightCommands(source),
      ),
    ],
    fill: _glassHighlightFill(source),
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioGlassWrite(VsdxShape shape) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userGlassEffect) cell,
  ];
  return shape.copyWith(
    userCells: <VsdxUserCell>[
      ...others,
      const VsdxUserCell(name: VsdxShape.userGlassEffect, value: '0'),
    ],
  );
}

void _collectGlassPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioGlassSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectGlassPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioGlassBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioGlassPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioGlassBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeGlassTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioGlassPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeGlassTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioGlassBake(next)) {
      out.add(_sourceForLibvisioGlassWrite(next));
      final plate = _glassPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
      );
      out.add(plate);
      changed = true;
      continue;
    }
    out.add(next);
    final existingId = plateIds[next.id];
    if (existingId != null) {
      VsdxShape? kept;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept = candidate;
          break;
        }
      }
      if (kept != null) {
        out.add(kept);
        changed = true;
      }
    }
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeGlassPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioGlassBake(page)) return page;
  final plateIds = <int, int>{};
  _collectGlassPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeGlassTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the white top-light siblings Draw uses for `veGlass`.
VsdxDocument bakeGlassForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeGlassPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// `true` when a filled 2-D stroke must become a sibling ribbon Draw paints.
///
/// FillPattern is already the body, so LineColorTrans / LineGradient cannot
/// steal it the way an unfilled ribbon does. `_lineProperties` also never
/// emits `svg:stroke-miterlimit`. CompoundType is not a token either, so
/// skipping the bake would drop the wash onto hard parallel rails. Built-in
/// LinePattern 2–23 and custom `veDashPattern` become per-dash filled
/// ribbons so Draw keeps the gaps — a native dashed stroke would be
/// opaque. Open-path Begin/EndArrow become filled Geometry on that sibling
/// so Draw does not hang markers on a dropped line; the plate fill is the
/// stroke colour, so heads stay LineColor not FillPattern. A locked
/// NoLine sibling carries the stroke silhouette (FillForegndTrans /
/// FillGradient / CompoundType 1–4 rails / the long miter outline), then
/// the source line is dropped.
bool shapeNeedsLibvisioFilledStrokeRibbonBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.softEdgesInches > 1e-6) return false;
  if (!_shapePaintsFill(shape, shape.geometries)) return false;
  if (!shape.line.hasGradient &&
      shape.line.transparency <= 1e-9 &&
      !_shapeHasLibvisioMiterSpikeCorners(shape)) {
    return false;
  }
  return _filledStrokeRibbonGeometries(shape).isNotEmpty;
}

List<VsdxGeometry> _geometriesFromRibbonPolygons(
  List<List<Offset2D>> polygons,
) {
  final out = <VsdxGeometry>[];
  for (final poly in polygons) {
    if (poly.length < 3) continue;
    final commands = polylineCommands(poly, closed: true);
    if (commands.length < 3) continue;
    out.add(VsdxGeometry(noFill: false, noLine: true, commands: commands));
  }
  return out;
}

List<VsdxGeometry> _filledStrokeRibbonGeometries(VsdxShape shape) {
  late final List<VsdxGeometry> out;
  if (shape.line.compoundType != 0) {
    out = _geometriesFromRibbonPolygons(
      _softEdgesCompoundRibbonPolygons(shape),
    );
  } else if (_shapeHasSoftEdgesDashes(shape)) {
    out = _geometriesFromRibbonPolygons(_softEdgesDashRibbonPolygons(shape));
  } else {
    out = <VsdxGeometry>[];
    final weight =
        shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
    final half = weight / 2;
    final limit = _lineUsesMiterJoin(shape.line) ? shape.line.miterLimit : 4.0;
    for (final geometry in shape.geometries) {
      if (geometry.noShow || geometry.noLine) continue;
      final points = _strokedVertices(geometry, shape);
      if (points == null || points.length < 2) continue;
      final closed = polylineLooksClosed(points, noFill: geometry.noFill);
      final commands = strokeRibbonCommands(
        points,
        halfWidth: half,
        closed: closed,
        miterLimit: limit,
      );
      if (commands.length < 3) continue;
      out.add(VsdxGeometry(noFill: false, noLine: true, commands: commands));
    }
  }
  if (_openArrowheadsBlockStrokeBake(shape)) {
    out.addAll(bakeArrowGeometriesForLibvisio(shape));
  }
  return out;
}

({double minX, double minY, double maxX, double maxY})? _polygonsAabb(
  List<List<Offset2D>> polygons,
) {
  double? minX;
  double? minY;
  double? maxX;
  double? maxY;
  for (final poly in polygons) {
    for (final p in poly) {
      minX = minX == null ? p.x : math.min(minX, p.x);
      minY = minY == null ? p.y : math.min(minY, p.y);
      maxX = maxX == null ? p.x : math.max(maxX, p.x);
      maxY = maxY == null ? p.y : math.max(maxY, p.y);
    }
  }
  if (minX == null || minY == null || maxX == null || maxY == null) {
    return null;
  }
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

/// Closed outline of a solid stroke, used when dash/compound ribbons are empty.
List<List<Offset2D>> _solidStrokeRibbonPolygons(
  VsdxShape shape, {
  double? halfWidth,
}) {
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final half = halfWidth ?? weight / 2;
  final limit = _lineUsesMiterJoin(shape.line) ? shape.line.miterLimit : 4.0;
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final body = _filletSoftEdgesStrokePoints(points, shape, closed: closed);
    final left = offsetPolyline(
      body,
      half,
      closed: closed,
      miterLimit: limit,
    );
    final right = offsetPolyline(
      body,
      -half,
      closed: closed,
      miterLimit: limit,
    );
    if (left.length < 2 || right.length < 2) continue;
    out.add(<Offset2D>[...left, ...right.reversed]);
  }
  return out;
}

List<List<Offset2D>> _libvisioStrokeSilhouettePolygons(VsdxShape shape) {
  if (shape.line.compoundType > 0) {
    return _softEdgesCompoundRibbonPolygons(shape);
  }
  if (_shapeHasSoftEdgesDashes(shape)) {
    return _softEdgesDashRibbonPolygons(shape);
  }
  return _solidStrokeRibbonPolygons(shape);
}

/// Filled Begin/EndArrow polygons in shape-local inches.
List<List<Offset2D>> _arrowPolygonsForLibvisioWrite(VsdxShape shape) {
  if (!_hasArrowheads(shape.line)) return const <List<Offset2D>>[];
  final out = <List<Offset2D>>[];
  for (final geometry in bakeArrowGeometriesForLibvisio(shape)) {
    if (geometry.noShow) continue;
    final points = _strokedVertices(geometry, shape) ??
        _softEdgesPolygonInches(shape, geometry);
    if (points == null || points.length < 3) continue;
    out.add(points);
  }
  return out;
}

/// Stroke ribbon plus baked arrowheads — used only by LineGradient PNG.
List<List<Offset2D>> _lineGradientStrokePolygons(VsdxShape shape) => [
      ..._libvisioStrokeSilhouettePolygons(shape),
      ..._arrowPolygonsForLibvisioWrite(shape),
    ];

VsdxShape _strokeRibbonPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  VsdxTheme theme = VsdxTheme.empty,
}) {
  final fill = _fillFromLineStroke(source.line, theme) ??
      _opaqueFillFromLine(source.line);
  return VsdxShape(
    id: id,
    name: '$kLibvisioStrokeRibbonShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _filledStrokeRibbonGeometries(source),
    fill: fill,
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioFilledStrokeRibbonWrite(VsdxShape shape) {
  var line = shape.line.copyWith(
    pattern: 0,
    gradient: null,
    transparency: 0,
    compoundType: 0,
    beginArrow: 0,
    endArrow: 0,
  );
  var cells = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userDashPattern &&
          cell.name != VsdxShape.userFixedDash)
        cell,
  ];
  if (_shapeHasLibvisioMiterSpikeCorners(shape)) {
    line = line.copyWith(miterLimit: 4.0);
    cells = <VsdxUserCell>[
      for (final cell in cells)
        if (cell.name != VsdxShape.userMiterLimit) cell,
    ];
  }
  return shape.copyWith(line: line, userCells: cells);
}

void _collectStrokeRibbonPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioStrokeRibbonSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectStrokeRibbonPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioFilledStrokeRibbonBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioStrokeRibbonPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioFilledStrokeRibbonBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeFilledStrokeRibbonTree(
  List<VsdxShape> shapes, {
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioStrokeRibbonPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeFilledStrokeRibbonTree(
        shape.children,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioFilledStrokeRibbonBake(next)) {
      final plate = _strokeRibbonPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
        theme: theme,
      );
      if (plate.geometries.isEmpty) {
        out.add(next);
        continue;
      }
      out.add(_sourceForLibvisioFilledStrokeRibbonWrite(next));
      out.add(plate);
      changed = true;
      continue;
    }
    out.add(next);
    final existingId = plateIds[next.id];
    if (existingId != null) {
      VsdxShape? kept;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept = candidate;
          break;
        }
      }
      if (kept != null) {
        out.add(kept);
        changed = true;
      }
    }
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeFilledStrokeRibbonPageForLibvisioWrite(
  VsdxPage page, {
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (!pageNeedsLibvisioFilledStrokeRibbonBake(page)) return page;
  final plateIds = <int, int>{};
  _collectStrokeRibbonPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeFilledStrokeRibbonTree(
      page.shapes,
      theme: theme,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the stroke-silhouette siblings Draw uses when Fill is
/// already the body.
VsdxDocument bakeFilledStrokeRibbonForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeFilledStrokeRibbonPageForLibvisioWrite(
      page,
      theme: document.theme,
    );
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// libvisio never reads User rows. The 1px text-frame stroke canvas / SVG
/// paint from `User.veLabelBorderColor` is therefore a locked NoFill sibling
/// whose LineColor Draw collects, then the User row is dropped. Glueable
/// labels need a TxtPin / TxtWidth first (loose bake pins the route) so
/// the stroke sits on that plate, not the Begin–End box.
bool shapeNeedsLibvisioLabelBorderBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  final color = shape.labelBorderColor;
  if (color == null || color.alpha == 0) return false;
  if (shape.richText.textBlock.hideText) return false;
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  if (!hasText) return false;
  final block = shape.richText.textBlock;
  if (shape.is1D || shape.isGlueableConnector) {
    if (block.pinXInches == null && block.pinYInches == null) return false;
    if (block.widthInches == null) return false;
  }
  final tw = (block.widthInches ?? shape.width).abs();
  final th = (block.heightInches ?? shape.height).abs();
  return tw > 1e-9 && th > 1e-9;
}

Offset2D _parentFromLocal(VsdxShape shape, Offset2D local) {
  var dx = local.x - shape.effectiveLocPinX;
  var dy = local.y - shape.effectiveLocPinY;
  if (shape.flipX) dx = -dx;
  if (shape.flipY) dy = -dy;
  if (shape.angleRad != 0) {
    final cosA = math.cos(shape.angleRad);
    final sinA = math.sin(shape.angleRad);
    final rx = dx * cosA - dy * sinA;
    final ry = dx * sinA + dy * cosA;
    dx = rx;
    dy = ry;
  }
  return Offset2D(shape.pinX + dx, shape.pinY + dy);
}

/// Extra text FlipX / FlipY about TxtPin (canvas `_textFlip*`).
///
/// Shape XForm already Flip's geometry about LocPin. Canvas then mirrors
/// the text block again about TxtPin so labels stay upright. Apply this
/// before [_parentFromLocal] so glyph / band plates land on that upright
/// arc. When TxtPin coincides with LocPin the two mirrors cancel.
Offset2D _textFlipAboutPin(VsdxShape shape, Offset2D local) {
  if (!shape.flipX && !shape.flipY) return local;
  final block = shape.richText.textBlock;
  final pinX = block.pinXInches ?? shape.width / 2;
  final pinY = block.pinYInches ?? shape.height / 2;
  var dx = local.x - pinX;
  var dy = local.y - pinY;
  if (shape.flipX) dx = -dx;
  if (shape.flipY) dy = -dy;
  return Offset2D(pinX + dx, pinY + dy);
}

/// Apply `TxtAngle` about TxtPin (canvas: rotate, then FlipX/Y).
///
/// Mixed Highlight plates live in the text-block rectangle. Draw
/// rotates that rectangle about TxtPin; without this step a baked
/// TextDirection `TxtAngle` would leave plate centres on the unrotated
/// line while glyphs spin in place.
Offset2D _textRotateAboutPin(VsdxShape shape, Offset2D local) {
  final block = shape.richText.textBlock;
  if (block.angleRad.abs() <= 1e-12) return local;
  final pinX = block.pinXInches ?? shape.width / 2;
  final pinY = block.pinYInches ?? shape.height / 2;
  final dx = local.x - pinX;
  final dy = local.y - pinY;
  final cosA = math.cos(block.angleRad);
  final sinA = math.sin(block.angleRad);
  return Offset2D(
    pinX + dx * cosA - dy * sinA,
    pinY + dx * sinA + dy * cosA,
  );
}

VsdxShape _labelBorderPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
}) {
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final defaultFrame = block.pinXInches == null &&
      block.pinYInches == null &&
      block.widthInches == null &&
      block.heightInches == null &&
      block.angleRad.abs() < 1e-12;
  late final Offset2D pin;
  late final double? locPinX;
  late final double? locPinY;
  late final double angle;
  if (defaultFrame) {
    pin = Offset2D(source.pinX, source.pinY);
    locPinX = source.locPinXInches;
    locPinY = source.locPinYInches;
    angle = source.angleRad;
  } else {
    pin = _parentFromLocal(
      source,
      Offset2D(
        block.pinXInches ?? source.width / 2,
        block.pinYInches ?? source.height / 2,
      ),
    );
    locPinX = block.locPinXInches;
    locPinY = block.locPinYInches;
    angle = source.angleRad + block.angleRad;
  }
  return VsdxShape(
    id: id,
    name: '$kLibvisioLabelBorderShapeNamePrefix${source.id}',
    pinX: pin.x,
    pinY: pin.y,
    width: tw,
    height: th,
    locPinXInches: locPinX,
    locPinYInches: locPinY,
    angleRad: angle,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: const <VsdxGeometry>[
      VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          RelMoveTo(0, 0),
          RelLineTo(1, 0),
          RelLineTo(1, 1),
          RelLineTo(0, 1),
          RelLineTo(0, 0),
        ],
      ),
    ],
    fill: const VsdxFill(pattern: 0),
    line: VsdxLine(
      color: source.labelBorderColor,
      pattern: 1,
      weightInches: 1 / kLibvisioLabelBorderPxPerInch,
      cap: LineCap.extended,
    ),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioLabelBorderWrite(VsdxShape shape) =>
    shape.withLabelBorderColor(null);

void _collectLabelBorderPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioLabelBorderSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectLabelBorderPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioLabelBorderBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioLabelBorderPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioLabelBorderBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeLabelBorderTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioLabelBorderPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeLabelBorderTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioLabelBorderBake(next)) {
      out.add(_sourceForLibvisioLabelBorderWrite(next));
      final plate = _labelBorderPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
      );
      out.add(plate);
      changed = true;
      continue;
    }
    out.add(next);
    final existingId = plateIds[next.id];
    if (existingId != null) {
      VsdxShape? kept;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept = candidate;
          break;
        }
      }
      if (kept != null) {
        out.add(kept);
        changed = true;
      }
    }
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeLabelBorderPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioLabelBorderBake(page)) return page;
  final plateIds = <int, int>{};
  _collectLabelBorderPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeLabelBorderTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the text-frame stroke siblings Draw uses for Label Border.
VsdxDocument bakeLabelBorderForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeLabelBorderPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// `true` when `User.veLabelPadding` must fold into Margin cells Draw paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veLabelPadding` never becomes ODF padding. Left/Right/Top/
/// BottomMargin *are* collected (`VSDContentCollector` maps them to
/// `fo:padding-*`), so a save adds the pixel inset at 96 dpi and drops
/// the User row. Glueable labels need a TxtPin / TxtWidth first (loose
/// bake pins the route) and grow that tight plate so the pad sits
/// around the glyphs the way canvas / SVG already paint it.
bool shapeNeedsLibvisioLabelPaddingBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.labelPadding.isZero) return false;
  if (shape.richText.textBlock.hideText) return false;
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  if (!hasText) return false;
  if (shape.is1D || shape.isGlueableConnector) {
    final block = shape.richText.textBlock;
    if (block.pinXInches == null && block.pinYInches == null) return false;
    if (block.widthInches == null) return false;
  }
  return true;
}

VsdxShape bakeLabelPaddingShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeLabelPaddingShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioLabelPaddingBake(shape)) {
    final pad = shape.labelPadding;
    final block = shape.richText.textBlock;
    final px = kLibvisioLabelPaddingPxPerInch;
    final dL = pad.left / px;
    final dR = pad.right / px;
    final dT = pad.top / px;
    final dB = pad.bottom / px;
    var nextBlock = block.copyWith(
      marginLeftInches: block.marginLeftInches + dL,
      marginRightInches: block.marginRightInches + dR,
      marginTopInches: block.marginTopInches + dT,
      marginBottomInches: block.marginBottomInches + dB,
    );
    var formulas = shape.formulas;
    if (shape.is1D || shape.isGlueableConnector) {
      final tw = (block.widthInches ?? shape.width).abs();
      final th = (block.heightInches ?? shape.height).abs();
      final locX = block.locPinXInches ?? tw / 2;
      final locY = block.locPinYInches ?? th / 2;
      final newTw = tw + dL + dR;
      final newTh = th + dT + dB;
      nextBlock = nextBlock.copyWith(
        widthInches: newTw,
        heightInches: newTh,
        locPinXInches: locX + dL,
        locPinYInches: locY + dB,
      );
      formulas = Map<String, String>.of(shape.formulas)
        ..remove('TxtWidth')
        ..remove('TxtHeight')
        ..remove('TxtLocPinX')
        ..remove('TxtLocPinY');
    }
    next = shape
        .copyWith(
          richText: shape.richText.copyWith(textBlock: nextBlock),
          formulas: formulas,
        )
        .withLabelPadding(VsdxLabelPadding.zero);
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Fold `User.veLabelPadding` into Left/Right/Top/BottomMargin Draw collects.
VsdxDocument bakeLabelPaddingForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeLabelPaddingShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Conservative unwrapped advance so Draw's wrap-at-`svg:width` stays one
/// line. Latin uses 0.72 em (wider than DejaVu's ~0.70 bold) so a slightly
/// tight estimate cannot re-wrap in Draw. FontScale is a glyph width scale,
/// including Letterspace baked into [fontScaleForLibvisioWrite].
double nowrapTextAdvanceInches(String text, VsdxCharStyle style) {
  if (text.isEmpty) return 0;
  var fs = math.max(style.effectiveFontSizeInchesForText(text), 0.04);
  if (style.position != VsdxTextPosition.normal) fs *= 0.7;
  final scale = fontScaleForLibvisioWrite(style, text);
  var w = 0.0;
  for (final r in text.runes) {
    final chFs = isVisioComplexScriptRune(r) || isVisioAsianScriptRune(r)
        ? fs
        : fs * 0.72;
    w += chFs * scale;
  }
  return w;
}

double nowrapLabelAdvanceInches(VsdxShape shape) {
  if (shape.richText.runs.isNotEmpty) {
    var widest = 0.0;
    for (final line in _mixedHighlightLines(shape)) {
      final placed = _placeHighlightLine(line, shape);
      for (final p in placed) {
        final end = p.x + p.seg.width;
        if (end > widest) widest = end;
      }
    }
    return widest;
  }
  var widest = 0.0;
  var current = 0.0;
  void addRun(String text, VsdxCharStyle style) {
    final parts = text.split(RegExp(r'\r\n|\n|\r'));
    for (var i = 0; i < parts.length; i++) {
      current += nowrapTextAdvanceInches(parts[i], style);
      if (i < parts.length - 1) {
        if (current > widest) widest = current;
        current = 0;
      }
    }
  }

  if (shape.text != null && shape.text!.isNotEmpty) {
    addRun(shape.text!, VsdxCharStyle.defaults);
  }
  if (current > widest) widest = current;
  return widest;
}

/// Extra TxtWidth Draw needs so an unwrapped label stays one line.
double nowrapTxtWidthForLibvisioWrite(VsdxShape shape) {
  final block = shape.richText.textBlock;
  return nowrapLabelAdvanceInches(shape) +
      block.marginLeftInches +
      block.marginRightInches +
      0.06;
}

/// `true` when `User.veWordWrap=0` must expand TxtWidth so Draw does not wrap.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veWordWrap` never becomes ODF `fo:wrap-option`. TxtWidth *is*
/// collected (`svg:width` of the text object), and Draw wraps to that box,
/// so a save widens the frame to the unwrapped line and drops the User row.
/// Glueable labels need a TxtPin / TxtWidth first (loose bake pins the
/// route) so the expanded plate stays on the polyline, not the
/// Begin–End box. Vertical text and curved text stay native — their
/// layout is not a single horizontal measure. Tab fields use the
/// same `visioTabFieldStart` canvas / SVG / libvisio `_fillTabSet` use
/// so Draw keeps the stop on one unwrapped line.
bool shapeNeedsLibvisioWordWrapBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) {
    final block = shape.richText.textBlock;
    if (block.pinXInches == null && block.pinYInches == null) return false;
    if (block.widthInches == null) return false;
  }
  if (shape.wordWrap) return false;
  if (shape.curvedText) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  for (final cell in shape.userCells) {
    if (cell.name == VsdxShape.userShapeInside && cell.value == '1') {
      return false;
    }
  }
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  if (!hasText) return false;
  return nowrapTxtWidthForLibvisioWrite(shape) > 1e-9;
}

VsdxHorzAlign _nowrapAlign(VsdxShape shape) {
  if (shape.richText.runs.isEmpty) return VsdxHorzAlign.left;
  return shape.richText.runs.first.paraStyle.effectiveHorizontalAlign;
}

VsdxShape _sourceForLibvisioWordWrapWrite(VsdxShape shape) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userWordWrap) cell,
  ];
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final needed = nowrapTxtWidthForLibvisioWrite(shape);
  var nextBlock = block;
  var formulas = shape.formulas;
  if (needed > tw + 1e-9) {
    final pinX = block.pinXInches ?? shape.width / 2;
    final locX = block.locPinXInches ?? tw / 2;
    final left = pinX - locX;
    final right = left + tw;
    final align = _nowrapAlign(shape);
    late final double newLeft;
    switch (align) {
      case VsdxHorzAlign.right:
        newLeft = right - needed;
      case VsdxHorzAlign.center:
        newLeft = left - (needed - tw) / 2;
      case VsdxHorzAlign.left:
      case VsdxHorzAlign.justify:
      case VsdxHorzAlign.full:
        newLeft = left;
    }
    nextBlock = block.copyWith(
      widthInches: needed,
      locPinXInches: pinX - newLeft,
    );
    formulas = Map<String, String>.of(shape.formulas)
      ..remove('TxtWidth')
      ..remove('TxtLocPinX');
  }
  return shape.copyWith(
    userCells: others,
    richText: shape.richText.copyWith(textBlock: nextBlock),
    formulas: formulas,
  );
}

VsdxShape bakeWordWrapShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeWordWrapShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioWordWrapBake(shape)) {
    next = _sourceForLibvisioWordWrapWrite(shape);
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Expand TxtWidth so Draw keeps an unwrapped draw.io label on one line.
VsdxDocument bakeWordWrapForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) bakeWordWrapShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when a folded host still has descendants Draw would paint.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veCollapsed` never hides children. Geometry `NoShow`, `HideText`,
/// `FillPattern=0` / `LinePattern=0`, and zero-size Foreign images *are*
/// collected, so a save applies those and stores
/// [VsdxShape.userCollapsedHidden] for Unfold.
bool shapeNeedsLibvisioCollapsedHideBake(VsdxShape shape) {
  if (!shape.collapsed) {
    for (final child in shape.children) {
      if (shapeNeedsLibvisioCollapsedHideBake(child)) return true;
    }
    return false;
  }
  return _collapsedDescendantNeedsHide(shape);
}

bool _collapsedDescendantNeedsHide(VsdxShape shape) {
  for (final child in shape.children) {
    if (!child.libvisioCollapsedHidden) return true;
    if (_collapsedDescendantNeedsHide(child)) return true;
  }
  return false;
}

VsdxShape bakeCollapsedShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeCollapsedShapeForLibvisioWrite(child),
  ];
  var next = shape;
  var changed = false;
  if (children.length != shape.children.length) {
    changed = true;
  } else {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        changed = true;
        break;
      }
    }
  }
  if (changed) next = shape.copyWith(children: children);
  if (!next.collapsed || !_collapsedDescendantNeedsHide(next)) {
    return changed ? next : shape;
  }
  final hidden = <VsdxShape>[
    for (final child in next.children) child.hideSubtreeForLibvisioCollapsed(),
  ];
  return next.copyWith(children: hidden);
}

/// Hide folded-container descendants so Draw does not paint them.
VsdxDocument bakeCollapsedForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    var needs = false;
    for (final shape in page.shapes) {
      if (shapeNeedsLibvisioCollapsedHideBake(shape)) {
        needs = true;
        break;
      }
    }
    if (!needs) {
      pages.add(page);
      continue;
    }
    pages.add(
      page.copyWith(
        shapes: <VsdxShape>[
          for (final shape in page.shapes)
            bakeCollapsedShapeForLibvisioWrite(shape),
        ],
      ),
    );
    pagesChanged = true;
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when a covered (merged-away) table cell is still drawable in Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veCovered` never hides the 0.01" park rectangle. Geometry
/// `NoShow`, `HideText`, `FillPattern=0` / `LinePattern=0`, and zero-size
/// Foreign images *are* collected, so a save applies those and stores
/// [VsdxShape.userCoveredHidden] for Unmerge.
bool shapeNeedsLibvisioCoveredHideBake(VsdxShape shape) {
  if (TableOps.isCovered(shape) && !shape.libvisioCoveredHidden) return true;
  for (final child in shape.children) {
    if (shapeNeedsLibvisioCoveredHideBake(child)) return true;
  }
  return false;
}

VsdxShape bakeCoveredShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children) bakeCoveredShapeForLibvisioWrite(child),
  ];
  var next = shape;
  var changed = false;
  if (children.length != shape.children.length) {
    changed = true;
  } else {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        changed = true;
        break;
      }
    }
  }
  if (changed) next = shape.copyWith(children: children);
  if (!TableOps.isCovered(next) || next.libvisioCoveredHidden) {
    return changed ? next : shape;
  }
  return next.hideForLibvisioCovered();
}

/// Hide merged-away table cells so Draw does not paint their park boxes.
VsdxDocument bakeCoveredForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    var needs = false;
    for (final shape in page.shapes) {
      if (shapeNeedsLibvisioCoveredHideBake(shape)) {
        needs = true;
        break;
      }
    }
    if (!needs) {
      pages.add(page);
      continue;
    }
    pages.add(
      page.copyWith(
        shapes: <VsdxShape>[
          for (final shape in page.shapes)
            bakeCoveredShapeForLibvisioWrite(shape),
        ],
      ),
    );
    pagesChanged = true;
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Combining overline `readCharIX` skips (`case XML_OVERLINE: break`).
const kLibvisioCombiningOverline = '\u0305';

/// Marks that must ride on the previous curved-text glyph, not a plate.
bool _curvedTextClusterMark(int rune) =>
    _isCombiningMarkRune(rune) || rune == 0x200E || rune == 0x200F;

bool _isCombiningMarkRune(int rune) =>
    (rune >= 0x0300 && rune <= 0x036F) ||
    (rune >= 0x1AB0 && rune <= 0x1AFF) ||
    (rune >= 0x1DC0 && rune <= 0x1DFF) ||
    (rune >= 0x20D0 && rune <= 0x20FF) ||
    (rune >= 0xFE20 && rune <= 0xFE2F);

bool _runeTakesCombiningOverline(int rune) {
  if (rune == 0x0305) return false;
  if (rune == 0x09 || rune == 0x0A || rune == 0x0D) return false;
  if (rune == 0x20 || rune == 0xA0) return false;
  if (_isCombiningMarkRune(rune)) return false;
  return true;
}

/// Insert U+0305 after each visible glyph so Draw paints an overline.
String textWithCombiningOverline(String text) {
  if (text.contains(kLibvisioCombiningOverline)) return text;
  final buf = StringBuffer();
  for (final rune in text.runes) {
    buf.writeCharCode(rune);
    if (_runeTakesCombiningOverline(rune)) {
      buf.write(kLibvisioCombiningOverline);
    }
  }
  return buf.toString();
}

bool _runNeedsLibvisioOverlineBake(VsdxTextRun run) {
  if (!run.charStyle.overline) return false;
  if (run.text.isEmpty) return false;
  // Tabs stay in the string; U+0305 is skipped on U+0009 so tabIndices
  // still name the same stops. Field spans grow around each mark so
  // `<fld>` still covers the cached Value.
  if (run.text.contains(kLibvisioCombiningOverline)) return false;
  for (final rune in run.text.runes) {
    if (_runeTakesCombiningOverline(rune)) return true;
  }
  return false;
}

/// How many U+0305 marks [textWithCombiningOverline] inserts before [utf16Index].
int _combiningOverlineMarksBefore(String text, int utf16Index) {
  var n = 0;
  var i = 0;
  for (final rune in text.runes) {
    if (i >= utf16Index) break;
    if (_runeTakesCombiningOverline(rune)) n++;
    i += rune > 0xFFFF ? 2 : 1;
  }
  return n;
}

/// Grow `<fld>` UTF-16 ranges so they still cover each overlined glyph.
List<VsdxFieldSpan> _shiftFieldSpansForCombiningOverline(
  String text,
  List<VsdxFieldSpan> spans,
) {
  if (spans.isEmpty) return spans;
  return <VsdxFieldSpan>[
    for (final span in spans)
      VsdxFieldSpan(
        start: span.start + _combiningOverlineMarksBefore(text, span.start),
        length: span.length +
            _combiningOverlineMarksBefore(text, span.start + span.length) -
            _combiningOverlineMarksBefore(text, span.start),
        ix: span.ix,
      ),
  ];
}

/// Gap canvas / SVG leave between the bullet glyph and the body text.
///
/// `TextPosAfterBullet` is the *minimum* physical label field, so a wide
/// custom `BulletStr` pushes the body further right (canvas
/// `_paintParagraphBlock`, SVG `labelWidth`).
double libvisioBulletLabelWidth(VsdxParaStyle para, VsdxCharStyle body) {
  final bodyFont = body.fontSizeInches > 0 ? body.fontSizeInches : 0.14;
  final glyph = nowrapTextAdvanceInches(
    para.resolvedBulletGlyph,
    VsdxCharStyle.defaults.copyWith(
      fontSizeInches: para.effectiveBulletFontSizeInches(bodyFont),
    ),
  );
  final minimum =
      para.textPosAfterBulletInches > 0 ? para.textPosAfterBulletInches : 0.25;
  return math.max(minimum, glyph);
}

/// `true` when a `Bullet` list must become a literal glyph for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `Bullet` / `BulletStr` /
/// `BulletFont` / `BulletFontSize` / `TextPosAfterBullet` *are* tokens, and
/// `_bulletFromParaFormat` resolves the glyph into
/// `addOpenUnorderedListLevel`'s `text:bullet-char`, but Draw's drawing-text
/// import keeps only the `text:min-label-width` inset — the glyph itself is
/// never painted, and that inset is never sized from `BulletFontSize`.
/// Canvas / SVG do paint it, so a save writes the resolved character into
/// the paragraph text, shifts `<fld>` UTF-16 starts past that prefix, folds
/// the label field into `IndLeft` / `IndFirst` (a hanging indent Draw does
/// collect as `fo:margin-left` / `fo:text-indent`), and drops the Bullet
/// cells so reopening does not stack a second marker. When the marker Size
/// or Font disagrees with the body, a rectangular save also splits that
/// prefix onto its own Character run so Draw collects the canvas
/// `effectiveBulletFontSizeInches` / `BulletFont`. Curved Text / Shape
/// Inside skip the hanging indent so outline wrap still runs; the glyph is
/// already in the text those plates copy.
bool shapeNeedsLibvisioBulletGlyphBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (run.paraStyle.bullet != 0) return true;
  }
  return false;
}

/// Index of the paragraph each run starts in (Visio breaks at `\n`).
List<int> _libvisioParagraphIndexPerRun(List<VsdxTextRun> runs) {
  final out = <int>[];
  var index = 0;
  for (final run in runs) {
    out.add(index);
    index += '\n'.allMatches(run.text).length;
  }
  return out;
}

String _libvisioBulletPrefix(String glyph) => '$glyph ';

/// Prefix every paragraph [run] *starts* with the resolved bullet glyph.
///
/// [opensParagraph] is false when an earlier run already carries this
/// paragraph's glyph; the breaks inside [run] still open new ones.
String _libvisioBulletPrefixedText(
  String text,
  String glyph, {
  required bool opensParagraph,
}) {
  final parts = text.split('\n');
  final buf = StringBuffer();
  final prefix = _libvisioBulletPrefix(glyph);
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) buf.write('\n');
    final lead = i > 0 || opensParagraph;
    // An empty trailing paragraph would only contribute an orphan glyph.
    if (lead && parts[i].isNotEmpty) buf.write(prefix);
    buf.write(parts[i]);
  }
  return buf.toString();
}

/// Original UTF-16 indices where [_libvisioBulletPrefixedText] inserts.
List<int> _libvisioBulletPrefixInserts(
  String text, {
  required bool opensParagraph,
}) {
  final parts = text.split('\n');
  final inserts = <int>[];
  var offset = 0;
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) offset += 1;
    final lead = i > 0 || opensParagraph;
    if (lead && parts[i].isNotEmpty) inserts.add(offset);
    offset += parts[i].length;
  }
  return inserts;
}

/// Shift `<fld>` spans after inserting [insertedLength] at each [insertAt].
///
/// [insertAt] is in the pre-insert string; later indices are applied first
/// so earlier original offsets stay valid. A span that starts at the
/// insert moves after the prefix; a span that strictly contains it grows.
List<VsdxFieldSpan> _shiftFieldSpansAfterInserts(
  List<VsdxFieldSpan> spans,
  List<int> insertAt,
  int insertedLength,
) {
  if (spans.isEmpty || insertAt.isEmpty || insertedLength <= 0) {
    return spans;
  }
  final points = [...insertAt]..sort((a, b) => b.compareTo(a));
  var next = spans;
  for (final at in points) {
    next = <VsdxFieldSpan>[
      for (final span in next)
        if (span.start >= at)
          VsdxFieldSpan(
            start: span.start + insertedLength,
            length: span.length,
            ix: span.ix,
          )
        else if (span.start + span.length > at)
          VsdxFieldSpan(
            start: span.start,
            length: span.length + insertedLength,
            ix: span.ix,
          )
        else
          span,
    ];
  }
  return next;
}

/// Prefix every paragraph start with the resolved bullet glyph.
///
/// Canvas / SVG arc and outline layout never paint `text:bullet-char`,
/// so they reuse this string a save already bakes for Draw. Bullet cells
/// stay set — callers that write for Draw flatten them separately.
List<VsdxTextRun> libvisioBulletPrefixedRuns(List<VsdxTextRun> runs) {
  if (runs.every((run) => run.paraStyle.bullet == 0)) return runs;
  final paraOf = _libvisioParagraphIndexPerRun(runs);
  final firstRunOfPara = <int, int>{};
  for (var i = 0; i < runs.length; i++) {
    firstRunOfPara.putIfAbsent(paraOf[i], () => i);
  }
  final next = <VsdxTextRun>[];
  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    final para = run.paraStyle;
    if (para.bullet == 0) {
      next.add(run);
      continue;
    }
    final opensParagraph = firstRunOfPara[paraOf[i]] == i;
    final glyph = para.resolvedBulletGlyph;
    final prefix = _libvisioBulletPrefix(glyph);
    next.add(run.copyWith(
      text: _libvisioBulletPrefixedText(
        run.text,
        glyph,
        opensParagraph: opensParagraph,
      ),
      fieldSpans: _shiftFieldSpansAfterInserts(
        run.fieldSpans,
        _libvisioBulletPrefixInserts(
          run.text,
          opensParagraph: opensParagraph,
        ),
        prefix.length,
      ),
    ));
  }
  return next;
}

/// Character style Draw should collect for a baked list marker.
///
/// Canvas `_paintParagraphBlock` sizes the glyph from
/// [VsdxParaStyle.effectiveBulletFontSizeInches] and `BulletFont`, and
/// does not copy small-caps / super-sub / highlight onto the marker.
VsdxCharStyle _libvisioBulletGlyphCharStyle(
  VsdxParaStyle para,
  VsdxCharStyle body,
) {
  final bodyFont = body.fontSizeInches > 0 ? body.fontSizeInches : 0.14;
  final font = para.bulletFont?.trim();
  return body.copyWith(
    fontSizeInches: para.effectiveBulletFontSizeInches(bodyFont),
    fontFamily: (font != null && font.isNotEmpty) ? font : body.fontFamily,
    fontScale: 1,
    position: VsdxTextPosition.normal,
    textCase: VsdxTextCase.normal,
    style: VsdxFontStyle.regular,
    letterSpacingInches: 0,
    clearHighlight: true,
    underline: false,
    strikethrough: false,
    doubleUnderline: false,
    doubleStrikethrough: false,
    overline: false,
    clearComplexScriptSize: true,
  );
}

bool _libvisioBulletGlyphNeedsOwnCharRun(
  VsdxParaStyle para,
  VsdxCharStyle body,
) {
  final glyph = _libvisioBulletGlyphCharStyle(para, body);
  if ((glyph.fontSizeInches - body.fontSizeInches).abs() > 1e-9) {
    return true;
  }
  return (glyph.fontFamily ?? '') != (body.fontFamily ?? '');
}

List<VsdxFieldSpan> _libvisioFieldSpansInRange(
  List<VsdxFieldSpan> spans,
  int start,
  int length,
) {
  if (spans.isEmpty || length <= 0) return const <VsdxFieldSpan>[];
  final end = start + length;
  final out = <VsdxFieldSpan>[];
  for (final span in spans) {
    final s = math.max(span.start, start);
    final e = math.min(span.start + span.length, end);
    if (e > s) {
      out.add(VsdxFieldSpan(start: s - start, length: e - s, ix: span.ix));
    }
  }
  return out;
}

/// Split a prefixed bullet run so Draw collects marker Size / Font.
void _appendLibvisioBulletGlyphCharRuns({
  required List<VsdxTextRun> into,
  required VsdxTextRun original,
  required VsdxTextRun prefixed,
  required bool opensParagraph,
  required VsdxCharStyle body,
  required bool hanging,
  required VsdxParaStyle bakedPara,
}) {
  final para = original.paraStyle;
  if (!hanging || !_libvisioBulletGlyphNeedsOwnCharRun(para, body)) {
    into.add(prefixed.copyWith(paraStyle: bakedPara));
    return;
  }
  final prefix = _libvisioBulletPrefix(para.resolvedBulletGlyph);
  final inserts = _libvisioBulletPrefixInserts(
    original.text,
    opensParagraph: opensParagraph,
  );
  if (inserts.isEmpty) {
    into.add(prefixed.copyWith(paraStyle: bakedPara));
    return;
  }
  final glyphStyle = _libvisioBulletGlyphCharStyle(para, body);
  final text = prefixed.text;
  var origCursor = 0;
  var prefixedCursor = 0;
  var tabOffset = 0;

  void emit(int start, int length, VsdxCharStyle style) {
    if (length <= 0) return;
    final chunk = text.substring(start, start + length);
    final tabs = '\t'.allMatches(chunk).length;
    into.add(
      VsdxTextRun(
        text: chunk,
        charStyle: style,
        paraStyle: bakedPara,
        fieldSpans: _libvisioFieldSpansInRange(
          prefixed.fieldSpans,
          start,
          length,
        ),
        tabIndices: prefixed.tabIndices.skip(tabOffset).take(tabs).toList(),
      ),
    );
    tabOffset += tabs;
  }

  for (final at in inserts) {
    if (at > origCursor) {
      final len = at - origCursor;
      emit(prefixedCursor, len, original.charStyle);
      prefixedCursor += len;
      origCursor = at;
    }
    emit(prefixedCursor, prefix.length, glyphStyle);
    prefixedCursor += prefix.length;
  }
  if (prefixedCursor < text.length) {
    emit(
      prefixedCursor,
      text.length - prefixedCursor,
      original.charStyle,
    );
  }
}

VsdxShape _sourceForLibvisioBulletGlyphWrite(VsdxShape shape) {
  final runs = shape.richText.runs;
  final paraOf = _libvisioParagraphIndexPerRun(runs);
  // The body font of a paragraph comes from its first non-empty run, the
  // same run canvas / SVG size the glyph against.
  final bodyStyle = <int, VsdxCharStyle>{};
  final firstRunOfPara = <int, int>{};
  for (var i = 0; i < runs.length; i++) {
    firstRunOfPara.putIfAbsent(paraOf[i], () => i);
    if (runs[i].text.trim().isEmpty) continue;
    bodyStyle.putIfAbsent(paraOf[i], () => runs[i].charStyle);
  }
  final prefixed = libvisioBulletPrefixedRuns(runs);
  // Arc / outline wrap rejects a hanging indent; the glyph is already in
  // the text those plates copy, and those plates use body Size.
  final hanging = !shape.curvedText && !shape.shapeInside;
  final next = <VsdxTextRun>[];
  for (var i = 0; i < prefixed.length; i++) {
    final run = prefixed[i];
    final original = runs[i];
    final para = original.paraStyle;
    if (para.bullet == 0) {
      next.add(run);
      continue;
    }
    final body = bodyStyle[paraOf[i]] ?? VsdxCharStyle.defaults;
    final label = hanging ? libvisioBulletLabelWidth(para, body) : 0.0;
    final bakedPara = para.copyWith(
      bullet: 0,
      clearBulletStr: true,
      clearBulletFont: true,
      clearBulletFontSize: true,
      textPosAfterBulletInches: 0,
      indentLeftInches: para.indentLeftInches + label,
      indentFirstInches: para.indentFirstInches - label,
    );
    _appendLibvisioBulletGlyphCharRuns(
      into: next,
      original: original,
      prefixed: run,
      opensParagraph: firstRunOfPara[paraOf[i]] == i,
      body: body,
      hanging: hanging,
      bakedPara: bakedPara,
    );
  }
  final rich = shape.richText.copyWith(runs: next);
  return shape.copyWith(
    richText: rich,
    text: shape.text == null ? null : rich.plainText,
  );
}

VsdxShape bakeBulletGlyphShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeBulletGlyphShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shapeNeedsLibvisioBulletGlyphBake(shape)
      ? _sourceForLibvisioBulletGlyphWrite(shape)
      : shape;
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Write the bullet glyph Draw never paints from `text:bullet-char`.
VsdxDocument bakeBulletGlyphForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeBulletGlyphShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when Character Overline must become combining marks for Draw.
bool shapeNeedsLibvisioOverlineBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_runNeedsLibvisioOverlineBake(run)) return true;
  }
  return false;
}

VsdxShape bakeOverlineShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeOverlineShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioOverlineBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_runNeedsLibvisioOverlineBake(run))
          run.copyWith(
            text: textWithCombiningOverline(run.text),
            charStyle: run.charStyle.copyWith(overline: false),
            fieldSpans: _shiftFieldSpansForCombiningOverline(
              run.text,
              run.fieldSpans,
            ),
          )
        else
          run,
    ];
    next = shape.copyWith(
      text: VsdxRichText(runs: runs, textBlock: shape.richText.textBlock)
          .plainText,
      richText: shape.richText.copyWith(runs: runs),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Rewrite Overline into combining marks the text engine in Draw will paint.
VsdxDocument bakeOverlineForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) bakeOverlineShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Combining long stroke Draw needs because double line-through collapses
/// to a single bar.
const kLibvisioCombiningLongStroke = '\u0336';

bool _runeTakesCombiningLongStroke(int rune) {
  if (rune == 0x0336) return false;
  if (rune == 0x09 || rune == 0x0A || rune == 0x0D) return false;
  if (rune == 0x20 || rune == 0xA0) return false;
  if (_isCombiningMarkRune(rune)) return false;
  return true;
}

/// Insert U+0336 after each visible glyph so Draw's single strike plus
/// this overlay reads as two bars.
String textWithCombiningLongStroke(String text) {
  if (text.contains(kLibvisioCombiningLongStroke)) return text;
  final buf = StringBuffer();
  for (final rune in text.runes) {
    buf.writeCharCode(rune);
    if (_runeTakesCombiningLongStroke(rune)) {
      buf.write(kLibvisioCombiningLongStroke);
    }
  }
  return buf.toString();
}

bool _runNeedsLibvisioDoubleStrikethroughBake(VsdxTextRun run) {
  if (!run.charStyle.doubleStrikethrough) return false;
  if (run.text.isEmpty) return false;
  if (run.text.contains(kLibvisioCombiningLongStroke)) return false;
  for (final rune in run.text.runes) {
    if (_runeTakesCombiningLongStroke(rune)) return true;
  }
  return false;
}

int _combiningLongStrokeMarksBefore(String text, int utf16Index) {
  var n = 0;
  var i = 0;
  for (final rune in text.runes) {
    if (i >= utf16Index) break;
    if (_runeTakesCombiningLongStroke(rune)) n++;
    i += rune > 0xFFFF ? 2 : 1;
  }
  return n;
}

List<VsdxFieldSpan> _shiftFieldSpansForCombiningLongStroke(
  String text,
  List<VsdxFieldSpan> spans,
) {
  if (spans.isEmpty) return spans;
  return <VsdxFieldSpan>[
    for (final span in spans)
      VsdxFieldSpan(
        start: span.start + _combiningLongStrokeMarksBefore(text, span.start),
        length: span.length +
            _combiningLongStrokeMarksBefore(text, span.start + span.length) -
            _combiningLongStrokeMarksBefore(text, span.start),
        ix: span.ix,
      ),
  ];
}

/// `true` when Character DoubleStrikethrough must become a combining overlay.
bool shapeNeedsLibvisioDoubleStrikethroughBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_runNeedsLibvisioDoubleStrikethroughBake(run)) return true;
  }
  return false;
}

VsdxShape bakeDoubleStrikethroughShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeDoubleStrikethroughShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioDoubleStrikethroughBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_runNeedsLibvisioDoubleStrikethroughBake(run))
          run.copyWith(
            text: textWithCombiningLongStroke(run.text),
            charStyle: run.charStyle.copyWith(
              strikethrough: true,
              doubleStrikethrough: false,
            ),
            fieldSpans: _shiftFieldSpansForCombiningLongStroke(
              run.text,
              run.fieldSpans,
            ),
          )
        else
          run,
    ];
    next = shape.copyWith(
      text: VsdxRichText(runs: runs, textBlock: shape.richText.textBlock)
          .plainText,
      richText: shape.richText.copyWith(runs: runs),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Rewrite DoubleStrikethrough into a combining overlay Draw will paint.
VsdxDocument bakeDoubleStrikethroughForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeDoubleStrikethroughShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when Paragraph `HorzAlign=4` would collapse wrap to left in Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `_fillParagraphProperties`
/// emits `fo:text-align="full"` for that cell. ODF allows `justify`, not
/// `full`, so Draw's drawing-text import falls back to left. Canvas / SVG
/// already map `full` to justify (Flutter has no last-line stretch).
bool shapeNeedsLibvisioHorzAlignFullBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_paraNeedsLibvisioHorzAlignFullBake(run.paraStyle)) return true;
  }
  return false;
}

bool _paraNeedsLibvisioHorzAlignFullBake(VsdxParaStyle para) =>
    para.horizontalAlign == VsdxHorzAlign.full;

VsdxShape bakeHorzAlignFullShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeHorzAlignFullShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioHorzAlignFullBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_paraNeedsLibvisioHorzAlignFullBake(run.paraStyle))
          run.copyWith(
            paraStyle: run.paraStyle.copyWith(
              horizontalAlign: VsdxHorzAlign.justify,
            ),
          )
        else
          run,
    ];
    next = shape.copyWith(richText: shape.richText.copyWith(runs: runs));
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Rewrite `HorzAlign=4` into `justify` so Draw does not fall back to left.
VsdxDocument bakeHorzAlignFullForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeHorzAlignFullShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Draw's drawing-text import ignores `style:tab-stop-distance` and jumps
/// 0.5" — the ODF default, which matches Visio's DefaultTabStop when the
/// cell is omitted or 0.
const _kLibvisioDrawDefaultTabStopInches = 0.5;

double _libvisioTabIntervalInches(VsdxTextBlock block) {
  final stop = block.defaultTabStopInches;
  return stop > 1e-9 ? stop : _kLibvisioDrawDefaultTabStopInches;
}

bool _libvisioDefaultTabIntervalNeedsBake(double interval) =>
    (interval - _kLibvisioDrawDefaultTabStopInches).abs() > 1e-6;

bool _shapeHasTabChar(VsdxShape shape) {
  for (final run in shape.richText.runs) {
    if (run.text.contains('\t')) return true;
  }
  return false;
}

Set<int> _libvisioReferencedTabSetIndexes(VsdxShape shape) {
  final ix = <int>{};
  for (final run in shape.richText.runs) {
    var tabs = 0;
    for (final unit in run.text.codeUnits) {
      if (unit == 0x09) tabs++;
    }
    if (tabs == 0) continue;
    for (var i = 0; i < tabs; i++) {
      ix.add(i < run.tabIndices.length ? run.tabIndices[i] : 0);
    }
  }
  return ix;
}

int _libvisioTabCharCount(VsdxShape shape) {
  var tabs = 0;
  for (final run in shape.richText.runs) {
    for (final unit in run.text.codeUnits) {
      if (unit == 0x09) tabs++;
    }
  }
  return tabs;
}

double _libvisioDefaultTabGridEndInches(VsdxShape shape) {
  final block = shape.richText.textBlock;
  final width = (block.widthInches ?? shape.width).abs();
  final inner = math.max(
    0.0,
    width - block.marginLeftInches - block.marginRightInches,
  );
  final interval = _libvisioTabIntervalInches(block);
  final needed = interval * math.max(_libvisioTabCharCount(shape), 1);
  return math.max(inner, needed);
}

bool _libvisioTabOnDefaultGrid(double position, double interval) {
  if (interval <= 1e-9 || position <= 1e-9) return false;
  final n = (position / interval).round();
  if (n < 1) return false;
  return (n * interval - position).abs() < 1e-6;
}

VsdxTabSet _libvisioTabSetWithDefaultGrid(
  VsdxTabSet set,
  double interval,
  double end,
) {
  final stops = [...set.stops];
  var offGridMax = 0.0;
  var hasOffGrid = false;
  for (final stop in stops) {
    if (_libvisioTabOnDefaultGrid(stop.positionInches, interval)) continue;
    hasOffGrid = true;
    if (stop.positionInches > offGridMax) offGridMax = stop.positionInches;
  }
  final threshold = hasOffGrid ? offGridMax : 0.0;
  var added = 0;
  for (var n = 1; n <= 40; n++) {
    final p = n * interval;
    if (p > end + 1e-9) break;
    if (p <= threshold + 1e-9) continue;
    var exists = false;
    for (final stop in stops) {
      if ((stop.positionInches - p).abs() < 1e-6) {
        exists = true;
        break;
      }
    }
    if (exists) continue;
    stops.add(VsdxTabStop(positionInches: p));
    added++;
    if (stops.length >= 40) break;
  }
  if (added == 0) return set;
  stops.sort((a, b) => a.positionInches.compareTo(b.positionInches));
  return VsdxTabSet(ix: set.ix, stops: stops);
}

List<VsdxTabSet> _libvisioTabSetsWithDefaultGrid(VsdxShape shape) {
  final interval = _libvisioTabIntervalInches(shape.richText.textBlock);
  final end = _libvisioDefaultTabGridEndInches(shape);
  final byIx = <int, VsdxTabSet>{
    for (final set in shape.richText.tabSets) set.ix: set,
  };
  for (final ix in _libvisioReferencedTabSetIndexes(shape)) {
    byIx[ix] = _libvisioTabSetWithDefaultGrid(
      byIx[ix] ?? VsdxTabSet(ix: ix),
      interval,
      end,
    );
  }
  final keys = byIx.keys.toList()..sort();
  return [for (final k in keys) byIx[k]!];
}

/// `true` when `DefaultTabStop` would jump 0.5" in Draw instead of the cell.
///
/// LibreOffice only calls `VisioDocument::parse`. The collector emits
/// `style:tab-stop-distance` from that cell, but Draw's drawing-text
/// import ignores it and uses ODF's 0.5" default. Canvas / SVG already
/// advance with `visioTabFieldStart`. A save writes explicit Tabs stops
/// on the authored interval. Authored off-grid stops stay so a 3" left
/// tab is not stolen by a 2" grid. A second save does not stack more.
bool shapeNeedsLibvisioDefaultTabStopBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  if (!_shapeHasTabChar(shape)) return false;
  final interval = _libvisioTabIntervalInches(shape.richText.textBlock);
  if (!_libvisioDefaultTabIntervalNeedsBake(interval)) return false;
  final next = _libvisioTabSetsWithDefaultGrid(shape);
  if (next.length != shape.richText.tabSets.length) return true;
  for (var i = 0; i < next.length; i++) {
    if (next[i] != shape.richText.tabSets[i]) return true;
  }
  return false;
}

VsdxShape bakeDefaultTabStopShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeDefaultTabStopShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioDefaultTabStopBake(shape)) {
    next = shape.copyWith(
      richText: shape.richText.copyWith(
        tabSets: _libvisioTabSetsWithDefaultGrid(shape),
      ),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Rewrite `DefaultTabStop` into Tabs stops Draw will actually jump.
VsdxDocument bakeDefaultTabStopForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeDefaultTabStopShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when Paragraph `SpLine=0` would collapse wrapped lines in Draw.
///
/// libvisio `_fillParagraphProperties` emits `fo:line-height` as a
/// percentage whenever `spLine <= 0`. Solid spacing is stored as 0, so
/// Draw receives `0%` and stacks every line on one baseline. Canvas /
/// SVG already treat that cell as 1× Size.
bool shapeNeedsLibvisioSolidLineSpacingBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_paraNeedsLibvisioSolidLineSpacingBake(run.paraStyle)) return true;
  }
  return false;
}

bool _paraNeedsLibvisioSolidLineSpacingBake(VsdxParaStyle para) =>
    para.lineSpacingSolid && para.lineSpacingAbsoluteInches <= 1e-9;

double _solidLineSpacingInchesForLibvisioWrite(VsdxTextRun run) {
  final size = run.charStyle.effectiveFontSizeInchesForText(run.text);
  if (size > 1e-9) return size;
  return VsdxCharStyle.defaults.fontSizeInches;
}

VsdxShape bakeSolidLineSpacingShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeSolidLineSpacingShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioSolidLineSpacingBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_paraNeedsLibvisioSolidLineSpacingBake(run.paraStyle))
          run.copyWith(
            paraStyle: run.paraStyle.copyWith(
              lineSpacingSolid: false,
              lineSpacingAbsoluteInches:
                  _solidLineSpacingInchesForLibvisioWrite(run),
            ),
          )
        else
          run,
    ];
    next = shape.copyWith(richText: shape.richText.copyWith(runs: runs));
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Rewrite `SpLine=0` into a positive length Draw will not collapse.
VsdxDocument bakeSolidLineSpacingForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeSolidLineSpacingShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when mixed Character Highlight must become per-run plates for Draw.
///
/// `readCharIX` has `case XML_HIGHLIGHT: break;`. A uniform marker already
/// becomes TextBkgnd. Mixed colours cannot share that cell, so a save
/// inserts locked FillForegnd siblings that carry each highlighted run
/// using the same nowrap advance curved-text uses, then hides the source
/// label so Draw paints those glyphs above the body fill. Explicit
/// newlines stack the same way canvas / SVG already wrap those markers.
/// Word Wrap on also wraps to TxtWidth with the same word/space units.
/// Tab fields use `visioTabFieldStart` (libvisio `_fillTabSet`).
/// Vertical text is folded into `TxtAngle` first so plate centres
/// follow TxtPin. Glueable labels get a route TxtPin first, then the
/// same plates; authored TextBkgnd stays native. Curved Text and
/// Shape Inside skip these siblings — those bakes put Highlight on
/// their own FillForegnd plates so Draw follows the arc / outline.
bool shapeNeedsLibvisioMixedHighlightBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.curvedText || shape.shapeInside) return false;
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  if (block.textDirection == 1) return false;
  if (block.backgroundColor != null) return false;
  if (uniformCharacterHighlight(shape) != null) return false;
  var sawHighlight = false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    if (run.charStyle.highlight != null) sawHighlight = true;
  }
  return sawHighlight;
}

typedef _HighlightSeg = ({
  String text,
  VsdxCharStyle style,
  VsdxParaStyle para,
  double width,
  double height,
  int? tabSetIx,
});

List<List<_HighlightSeg>> _mixedHighlightLines(VsdxShape shape) {
  final lines = <List<_HighlightSeg>>[<_HighlightSeg>[]];
  void addSeg(String text, VsdxTextRun run) {
    if (text.isEmpty) return;
    final width = nowrapTextAdvanceInches(text, run.charStyle);
    final height = math.max(
      run.charStyle.effectiveFontSizeInchesForText(text),
      0.04,
    );
    lines.last.add((
      text: text,
      style: run.charStyle,
      para: run.paraStyle,
      width: width,
      height: height,
      tabSetIx: null,
    ));
  }

  void addTab(VsdxTextRun run, int tabSetIx) {
    lines.last.add((
      text: '',
      style: run.charStyle,
      para: run.paraStyle,
      width: 0,
      height: 0.04,
      tabSetIx: tabSetIx,
    ));
  }

  for (final run in shape.richText.runs) {
    var tab = 0;
    final parts =
        run.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      var start = 0;
      for (var c = 0; c < part.length; c++) {
        if (part.codeUnitAt(c) != 0x09) continue;
        if (c > start) addSeg(part.substring(start, c), run);
        addTab(run, tab < run.tabIndices.length ? run.tabIndices[tab] : 0);
        tab++;
        start = c + 1;
      }
      if (start < part.length) addSeg(part.substring(start), run);
      if (i != parts.length - 1) lines.add(<_HighlightSeg>[]);
    }
  }
  return lines;
}

List<({_HighlightSeg seg, double x})> _placeHighlightLine(
  List<_HighlightSeg> line,
  VsdxShape source,
) {
  final hasTab = line.any((s) => s.tabSetIx != null);
  if (!hasTab) {
    var x = 0.0;
    final out = <({_HighlightSeg seg, double x})>[];
    for (final s in line) {
      out.add((seg: s, x: x));
      x += s.width;
    }
    return out;
  }
  final tabSets = source.richText.tabSets;
  final defaultStop = source.richText.textBlock.defaultTabStopInches;
  var x = 0.0;
  final out = <({_HighlightSeg seg, double x})>[];
  for (var i = 0; i < line.length; i++) {
    final s = line[i];
    final tabSetIx = s.tabSetIx;
    if (tabSetIx != null) {
      var following = 0.0;
      var decimalPrefix = 0.0;
      var sawDecimal = false;
      for (var j = i + 1; j < line.length; j++) {
        if (line[j].tabSetIx != null) break;
        following += line[j].width;
        if (sawDecimal) continue;
        final dot = line[j].text.indexOf('.');
        if (dot < 0) {
          decimalPrefix += line[j].width;
        } else {
          decimalPrefix += nowrapTextAdvanceInches(
            line[j].text.substring(0, dot),
            line[j].style,
          );
          sawDecimal = true;
        }
      }
      x = visioTabFieldStart(
        tabSets: tabSets,
        tabSetIx: tabSetIx,
        currentPosition: x,
        followingWidth: following,
        decimalPrefixWidth: decimalPrefix,
        defaultTabStop: defaultStop,
      );
      continue;
    }
    out.add((seg: s, x: x));
    x += s.width;
  }
  return out;
}

List<List<_HighlightSeg>> _wrapHighlightSegs(
  List<_HighlightSeg> segs,
  double lineMax,
) {
  if (segs.isEmpty) return [<_HighlightSeg>[]];
  final lines = <List<_HighlightSeg>>[];
  var cur = <_HighlightSeg>[];
  var curW = 0.0;

  void flush() {
    if (cur.isEmpty) return;
    lines.add(cur);
    cur = <_HighlightSeg>[];
    curW = 0.0;
  }

  void append(_HighlightSeg next) {
    cur.add(next);
    curW += next.width;
  }

  for (final s in segs) {
    if (s.text.isEmpty) {
      append(s);
      continue;
    }
    for (final unit in _libvisioWrapUnits(s.text)) {
      final uw = nowrapTextAdvanceInches(unit, s.style);
      final uh = math.max(
        s.style.effectiveFontSizeInchesForText(unit),
        0.04,
      );
      final isBlank = unit.trim().isEmpty;
      if (curW > 1e-9 && curW + uw > lineMax && !isBlank) {
        flush();
      }
      if (cur.isEmpty && isBlank) continue;
      if (uw > lineMax && unit.length > 1 && !isBlank) {
        for (final r in unit.runes) {
          final ch = String.fromCharCode(r);
          final cw = nowrapTextAdvanceInches(ch, s.style);
          final chH = math.max(
            s.style.effectiveFontSizeInchesForText(ch),
            0.04,
          );
          if (curW > 1e-9 && curW + cw > lineMax) flush();
          append((
            text: ch,
            style: s.style,
            para: s.para,
            width: cw,
            height: chH,
            tabSetIx: null,
          ));
        }
        continue;
      }
      append((
        text: unit,
        style: s.style,
        para: s.para,
        width: uw,
        height: uh,
        tabSetIx: null,
      ));
    }
  }
  flush();
  return lines.isEmpty ? [segs] : lines;
}

List<List<_HighlightSeg>> _wrapHighlightLines(
  List<List<_HighlightSeg>> lines,
  VsdxShape shape,
) {
  if (!shape.wordWrap) return lines;
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final contentW = math.max(
    0.04,
    tw - block.marginLeftInches - block.marginRightInches,
  );
  final out = <List<_HighlightSeg>>[];
  for (final line in lines) {
    if (line.any((s) => s.tabSetIx != null)) {
      out.add(line);
      continue;
    }
    out.addAll(_wrapHighlightSegs(line, contentW));
  }
  return out;
}

List<VsdxShape> _mixedHighlightPlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  final lines = _wrapHighlightLines(_mixedHighlightLines(source), source);
  if (lines.every((line) => line.isEmpty)) return const <VsdxShape>[];
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  final lineHeights = <double>[
    for (final line in lines)
      line.fold<double>(0.04, (h, s) => math.max(h, s.height)),
  ];
  final totalH = lineHeights.fold<double>(0, (a, b) => a + b);
  final firstH = lineHeights.first;
  var midY = switch (block.verticalAlign) {
    VsdxVertAlign.top => originY + th - block.marginTopInches - firstH / 2,
    VsdxVertAlign.bottom =>
      originY + block.marginBottomInches + totalH - firstH / 2,
    VsdxVertAlign.middle => originY + th / 2 + totalH / 2 - firstH / 2,
  };
  final contentW =
      math.max(0.0, tw - block.marginLeftInches - block.marginRightInches);
  final out = <VsdxShape>[];
  var plate = 0;
  for (var li = 0; li < lines.length; li++) {
    if (li > 0) {
      midY -= (lineHeights[li - 1] + lineHeights[li]) / 2;
    }
    final line = lines[li];
    final lineH = lineHeights[li];
    final placed = _placeHighlightLine(line, source);
    var totalW = 0.0;
    for (final p in placed) {
      final end = p.x + p.seg.width;
      if (end > totalW) totalW = end;
    }
    final align = line.isNotEmpty
        ? line.first.para.effectiveHorizontalAlign
        : VsdxHorzAlign.left;
    var origin = originX + block.marginLeftInches;
    switch (align) {
      case VsdxHorzAlign.center:
        origin += math.max(0.0, (contentW - totalW) / 2);
      case VsdxHorzAlign.right:
        origin += math.max(0.0, contentW - totalW);
      case VsdxHorzAlign.left:
      case VsdxHorzAlign.justify:
      case VsdxHorzAlign.full:
        break;
    }
    for (final p in placed) {
      final s = p.seg;
      final color = s.style.highlight;
      if (color != null && s.width > 1e-9 && s.text.trim().isNotEmpty) {
        final local = _textFlipAboutPin(
          source,
          _textRotateAboutPin(
            source,
            Offset2D(origin + p.x + s.width / 2, midY),
          ),
        );
        final page = _parentFromLocal(source, local);
        final id = plate < plateIds.length ? plateIds[plate] : nextId();
        final pw = math.max(s.width, lineH) * 1.2;
        final ph = lineH * 1.5;
        final style = s.style.copyWith(clearHighlight: true);
        out.add(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: page.x,
            pinY: page.y,
            width: pw,
            height: ph,
            name: '$kLibvisioHighlightShapeNamePrefix$plate.${source.id}',
            fill: VsdxFill(foreground: color, pattern: 1),
            line: const VsdxLine(pattern: 0),
          ).copyWith(
            locPinXInches: pw / 2,
            locPinYInches: ph / 2,
            angleRad: source.angleRad + block.angleRad,
            locked: true,
            layerMemberIds: source.layerMemberIds,
            text: s.text,
            richText: VsdxRichText(
              runs: <VsdxTextRun>[
                VsdxTextRun(
                  text: s.text,
                  charStyle: style,
                  paraStyle: const VsdxParaStyle(
                    horizontalAlign: VsdxHorzAlign.center,
                  ),
                ),
              ],
              textBlock: VsdxTextBlock(
                widthInches: pw,
                heightInches: ph,
                locPinXInches: pw / 2,
                locPinYInches: ph / 2,
                verticalAlign: VsdxVertAlign.middle,
                marginLeftInches: 0,
                marginRightInches: 0,
                marginTopInches: 0,
                marginBottomInches: 0,
              ),
            ),
          ),
        );
        plate++;
      }
    }
  }
  return out;
}

void _collectHighlightPlateIds(
  List<VsdxShape> shapes,
  Map<int, List<int>> into,
) {
  for (final shape in shapes) {
    final sourceId = libvisioHighlightSourceId(shape);
    if (sourceId != null) {
      (into[sourceId] ??= <int>[]).add(shape.id);
    }
    _collectHighlightPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioMixedHighlightBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioHighlightPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioMixedHighlightBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

VsdxShape _sourceForLibvisioMixedHighlightWrite(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return shape;
  return shape.copyWith(
    richText: shape.richText.copyWith(
      textBlock: shape.richText.textBlock.copyWith(hideText: true),
    ),
  );
}

List<VsdxShape> _bakeMixedHighlightTree(
  List<VsdxShape> shapes, {
  required Map<int, List<int>> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioHighlightPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeMixedHighlightTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioMixedHighlightBake(next) ||
        plateIds.containsKey(next.id)) {
      final plates = _mixedHighlightPlatesForLibvisioWrite(
        next,
        plateIds: plateIds[next.id] ?? const <int>[],
        nextId: nextId,
      );
      if (plates.isEmpty) {
        out.add(next);
        continue;
      }
      // Body fill first, then glyph plates so Draw does not cover the
      // markers. Hide the source label — Highlight is not a token.
      out.add(_sourceForLibvisioMixedHighlightWrite(next));
      out.addAll(plates);
      changed = true;
      continue;
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the per-run Highlight siblings Draw can fill.
VsdxDocument bakeMixedHighlightForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioMixedHighlightBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, List<int>>{};
    _collectHighlightPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeMixedHighlightTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages);
}

/// RIGHT-TO-LEFT MARK. Draw never reads Character `LangID`, so a save
/// prefixes this when canvas / SVG already treat a digit/punctuation run
/// as RTL from that cell.
const kLibvisioRtlMark = '\u200F';

bool _textHasStrongRightToLeft(String text) {
  for (final rune in text.runes) {
    if (isVisioRightToLeftRune(rune)) return true;
  }
  return false;
}

/// Prefix U+200F so Draw's Unicode bidi matches canvas LangID RTL.
String textWithLibvisioRtlMark(String text) {
  if (text.startsWith(kLibvisioRtlMark)) return text;
  return '$kLibvisioRtlMark$text';
}

bool _runNeedsLibvisioLangIdRtlBake(VsdxTextRun run) {
  final text = run.text;
  if (text.trim().isEmpty) return false;
  if (text.startsWith(kLibvisioRtlMark)) return false;
  // Tabs stay in the string; U+200F is a prefix so tabIndices still
  // name the same stops. Field spans shift past that prefix so `<fld>`
  // still covers the cached Value.
  if (_textHasStrongRightToLeft(text)) return false;
  return isVisioRightToLeftText(text, langId: run.charStyle.langId);
}

/// `true` when Character LangID must become a leading U+200F for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no
/// LangID and `readCharIX` never stores it, so Draw lays out digit-only
/// Arabic / Hebrew runs LTR. Canvas / SVG already use
/// [isVisioRightToLeftText]. Strong RTL letters do not need the mark.
bool shapeNeedsLibvisioLangIdRtlBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_runNeedsLibvisioLangIdRtlBake(run)) return true;
  }
  return false;
}

VsdxShape bakeLangIdRtlShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeLangIdRtlShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioLangIdRtlBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_runNeedsLibvisioLangIdRtlBake(run))
          run.copyWith(
            text: textWithLibvisioRtlMark(run.text),
            fieldSpans: _shiftFieldSpansAfterInserts(
              run.fieldSpans,
              const <int>[0],
              kLibvisioRtlMark.length,
            ),
          )
        else
          run,
    ];
    next = shape.copyWith(
      text: VsdxRichText(runs: runs, textBlock: shape.richText.textBlock)
          .plainText,
      richText: shape.richText.copyWith(runs: runs),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Prefix LangID-only RTL runs with U+200F so Draw matches canvas bidi.
VsdxDocument bakeLangIdRtlForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeLangIdRtlShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Script clusters canvas `_visioScriptChildren` would split a Character run
/// into. Combining marks and LRM/RLM stay on the preceding glyph.
List<({int start, String text})> _libvisioScriptFontChunks(String text) {
  final out = <({int start, String text})>[];
  final buf = StringBuffer();
  var kind = -1;
  var start = 0;
  var utf16 = 0;

  void flush() {
    if (buf.isEmpty) return;
    out.add((start: start, text: buf.toString()));
    buf.clear();
  }

  for (final rune in text.runes) {
    final units = rune > 0xFFFF ? 2 : 1;
    if (kind >= 0 &&
        (_isCombiningMarkRune(rune) || rune == 0x200E || rune == 0x200F)) {
      buf.writeCharCode(rune);
      utf16 += units;
      continue;
    }
    final next = isVisioComplexScriptRune(rune)
        ? 2
        : isVisioAsianScriptRune(rune)
            ? 1
            : 0;
    if (kind >= 0 && kind != next) {
      flush();
      start = utf16;
    }
    kind = next;
    buf.writeCharCode(rune);
    utf16 += units;
  }
  flush();
  return out;
}

bool _runNeedsLibvisioMixedScriptFontBake(VsdxTextRun run) {
  if (run.text.isEmpty) return false;
  final chunks = _libvisioScriptFontChunks(run.text);
  if (chunks.length < 2) return false;
  final style = run.charStyle;
  for (final chunk in chunks) {
    final face = fontFamilyForLibvisioWrite(style, chunk.text);
    final size = fontSizeForLibvisioWrite(style, chunk.text);
    if ((face ?? '') != (style.fontFamily ?? '')) return true;
    if ((size - style.fontSizeInches).abs() > 1e-12) return true;
  }
  return false;
}

/// `true` when a mixed-script run must become separate Character rows.
///
/// LibreOffice only calls `VisioDocument::parse`. `readCharIX` stores `Font`
/// / `Size` and skips `AsianFont` / `ComplexScriptFont` /
/// `ComplexScriptSize`. An Asian-only or complex-only run already rewrites
/// those into `Font` / `Size`. A mixed Latin+CJK or Latin+Arabic run would
/// keep the Latin face on every glyph, while canvas / SVG already switch
/// per script. A save splits the run so each script collects its face and
/// size. Combining marks stay on the preceding glyph. A second save does
/// not split again.
bool shapeNeedsLibvisioMixedScriptFontBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_runNeedsLibvisioMixedScriptFontBake(run)) return true;
  }
  return false;
}

List<VsdxTextRun> _libvisioMixedScriptFontRuns(List<VsdxTextRun> runs) {
  final next = <VsdxTextRun>[];
  for (final run in runs) {
    if (!_runNeedsLibvisioMixedScriptFontBake(run)) {
      next.add(run);
      continue;
    }
    final chunks = _libvisioScriptFontChunks(run.text);
    var tabOffset = 0;
    for (final chunk in chunks) {
      final tabs = '\t'.allMatches(chunk.text).length;
      next.add(
        VsdxTextRun(
          text: chunk.text,
          charStyle: run.charStyle.copyWith(
            fontFamily: fontFamilyForLibvisioWrite(run.charStyle, chunk.text),
            fontSizeInches: fontSizeForLibvisioWrite(run.charStyle, chunk.text),
          ),
          paraStyle: run.paraStyle,
          fieldSpans: _libvisioFieldSpansInRange(
            run.fieldSpans,
            chunk.start,
            chunk.text.length,
          ),
          tabIndices: run.tabIndices.skip(tabOffset).take(tabs).toList(),
        ),
      );
      tabOffset += tabs;
    }
  }
  return next;
}

VsdxShape bakeMixedScriptFontShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeMixedScriptFontShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioMixedScriptFontBake(shape)) {
    final runs = _libvisioMixedScriptFontRuns(shape.richText.runs);
    next = shape.copyWith(
      text: shape.text == null
          ? null
          : VsdxRichText(runs: runs, textBlock: shape.richText.textBlock)
              .plainText,
      richText: shape.richText.copyWith(runs: runs),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Split mixed-script runs so Draw collects Asian / complex Font and Size.
VsdxDocument bakeMixedScriptFontForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeMixedScriptFontShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

const _kLibvisioCurvedTextMaxGlyphs = 64;

/// `true` when `User.veCurvedText` must become per-glyph siblings for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so the arc never becomes ODF text-on-path. Pin / Angle / Font /
/// HideText *are* collected, so a save places one locked character shape
/// per glyph on the same quadratic arc canvas / SVG already paint, then
/// hides the source and drops the User row. Tab fields become spaces —
/// canvas / SVG already paint `\t` as a gap on the arc, not a stop.
/// Combining marks (Overline's U+0305) and bidi marks stay on the
/// preceding glyph so Draw does not park an orphan plate on the arc.
/// Character Highlight (`readCharIX` is an empty case) becomes
/// FillForegnd on each glyph plate so mixed markers follow the arc.
/// Glueable 1-D labels, vertical text and TxtAngle stay native. FlipX /
/// FlipY extra text mirrors about TxtPin are baked so Draw keeps the
/// upright arc.
bool shapeNeedsLibvisioCurvedTextBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (!shape.curvedText) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  if (shape.richText.textBlock.angleRad.abs() > 1e-12) return false;
  final plain = _curvedTextPlain(shape);
  if (plain.isEmpty) return false;
  var n = 0;
  for (final r in plain.runes) {
    if (r == 0x20 || _curvedTextClusterMark(r)) continue;
    n++;
    if (n > _kLibvisioCurvedTextMaxGlyphs) return false;
  }
  return n > 0;
}

String _libvisioInitialCaps(String text) {
  final buf = StringBuffer();
  var start = true;
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    if (ch == ' ' || ch == '\n' || ch == '\t') {
      buf.write(ch);
      start = true;
      continue;
    }
    buf.write(start ? ch.toUpperCase() : ch);
    start = false;
  }
  return buf.toString();
}

String _libvisioApplyTextCase(String text, VsdxTextCase textCase) =>
    switch (textCase) {
      VsdxTextCase.allCaps => text.toUpperCase(),
      VsdxTextCase.initialCaps => _libvisioInitialCaps(text),
      VsdxTextCase.normal => text,
    };

/// Per-glyph style on the arc. Combining marks keep the preceding
/// glyph's style when [_curvedTextPlatesForLibvisioWrite] clusters them.
List<({int rune, VsdxCharStyle style})> _curvedTextStyledRunes(
  VsdxShape shape,
) {
  final out = <({int rune, VsdxCharStyle style})>[];
  void addText(String raw, VsdxCharStyle style) {
    final text = _libvisioApplyTextCase(
      raw.replaceAll('\n', ' ').replaceAll('\r', ' ').replaceAll('\t', ' '),
      style.textCase,
    );
    final normalized = style.copyWith(textCase: VsdxTextCase.normal);
    for (final r in text.runes) {
      out.add((rune: r, style: normalized));
    }
  }

  if (shape.richText.runs.isNotEmpty) {
    for (final run in shape.richText.runs) {
      addText(run.text, run.charStyle);
    }
  } else {
    addText(shape.text ?? '', _curvedTextStyle(shape));
  }
  while (out.isNotEmpty && out.first.rune == 0x20) {
    out.removeAt(0);
  }
  while (out.isNotEmpty && out.last.rune == 0x20) {
    out.removeLast();
  }
  return out;
}

String _curvedTextPlain(VsdxShape shape) => String.fromCharCodes(
      _curvedTextStyledRunes(shape).map((g) => g.rune),
    );

VsdxCharStyle _curvedTextStyle(VsdxShape shape) {
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return style.copyWith(textCase: VsdxTextCase.normal);
}

Offset2D _quadBezPoint(Offset2D p0, Offset2D p1, Offset2D p2, double t) {
  final u = 1 - t;
  return Offset2D(
    u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
    u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
  );
}

Offset2D _quadBezTangent(Offset2D p0, Offset2D p1, Offset2D p2, double t) {
  return Offset2D(
    2 * (1 - t) * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
    2 * (1 - t) * (p1.y - p0.y) + 2 * t * (p2.y - p1.y),
  );
}

double _arcTForDistance(List<double> cum, double dist) {
  final n = cum.length - 1;
  if (n <= 0) return 0;
  if (dist <= 0) return 0;
  if (dist >= cum.last) return 1;
  var lo = 0;
  var hi = n;
  while (lo + 1 < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= dist) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final seg = cum[hi] - cum[lo];
  final local = seg <= 1e-12 ? 0.0 : (dist - cum[lo]) / seg;
  return (lo + local) / n;
}

List<VsdxShape> _curvedTextPlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  final glyphs = _curvedTextStyledRunes(source);
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final ml = block.marginLeftInches;
  final mr = block.marginRightInches;
  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  final midY = th * 0.58;
  final bulge = math.min(th * 0.32, th * 0.45);
  final p0 = Offset2D(ml, midY);
  final p1 = Offset2D(tw / 2, midY - bulge);
  final p2 = Offset2D(tw - mr, midY);
  const samples = 48;
  final cum = <double>[0.0];
  var prev = p0;
  for (var i = 1; i <= samples; i++) {
    final o = _quadBezPoint(p0, p1, p2, i / samples);
    final dx = o.x - prev.x;
    final dy = o.y - prev.y;
    cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
    prev = o;
  }
  final arcLen = cum.last;
  if (arcLen <= 1e-9) return const <VsdxShape>[];
  final widths = <double>[
    for (final g in glyphs)
      _curvedTextClusterMark(g.rune)
          ? 0.0
          : nowrapTextAdvanceInches(String.fromCharCode(g.rune), g.style),
  ];
  var totalW = 0.0;
  for (final w in widths) {
    totalW += w;
  }
  final pad = math.max(0.0, (arcLen - totalW) / 2);
  final out = <VsdxShape>[];
  var cursor = pad;
  var glyph = 0;
  var pendingMarks = '';
  for (var i = 0; i < glyphs.length; i++) {
    final w = widths[i];
    final ch = String.fromCharCode(glyphs[i].rune);
    if (_curvedTextClusterMark(glyphs[i].rune)) {
      if (out.isNotEmpty) {
        final last = out.removeLast();
        final next = '${last.text ?? ''}$ch';
        final run = last.richText.runs.single;
        out.add(
          last.copyWith(
            text: next,
            richText: last.richText.copyWith(
              runs: <VsdxTextRun>[run.copyWith(text: next)],
            ),
          ),
        );
      } else {
        pendingMarks += ch;
      }
      continue;
    }
    if (glyphs[i].rune != 0x20 && ch.trim().isNotEmpty) {
      final cluster = '$pendingMarks$ch';
      pendingMarks = '';
      final glyphStyle = glyphs[i].style;
      final highlight = glyphStyle.highlight;
      final plateStyle = glyphStyle.copyWith(clearHighlight: true);
      final centerDist = (cursor + w / 2).clamp(0.0, arcLen);
      final t = _arcTForDistance(cum, centerDist);
      final pos = _quadBezPoint(p0, p1, p2, t);
      final tan = _quadBezTangent(p0, p1, p2, t);
      final localAngle = -math.atan2(tan.y, tan.x);
      final local = _textFlipAboutPin(
        source,
        Offset2D(originX + pos.x, originY + th - pos.y),
      );
      final page = _parentFromLocal(source, local);
      final fs = math.max(glyphStyle.effectiveFontSizeInchesForText(ch), 0.04);
      // Wider / taller than the advance so Draw's wrap-at-svg:width and
      // baseline padding cannot clip a single rotated glyph.
      final gw = math.max(w, fs) * 1.2;
      final gh = fs * 1.6;
      final id = glyph < plateIds.length ? plateIds[glyph] : nextId();
      out.add(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: page.x,
          pinY: page.y,
          width: gw,
          height: gh,
          fill: highlight != null
              ? VsdxFill(foreground: highlight, pattern: 1)
              : const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
          name: '$kLibvisioCurvedTextShapeNamePrefix$glyph.${source.id}',
        ).copyWith(
          locPinXInches: gw / 2,
          locPinYInches: gh / 2,
          angleRad: source.angleRad + localAngle,
          locked: true,
          layerMemberIds: source.layerMemberIds,
          text: cluster,
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: cluster,
                charStyle: plateStyle,
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(
              widthInches: gw,
              heightInches: gh,
              locPinXInches: gw / 2,
              locPinYInches: gh / 2,
              verticalAlign: VsdxVertAlign.middle,
            ),
          ),
        ),
      );
      glyph++;
    }
    cursor += w;
  }
  return out;
}

VsdxShape _sourceForLibvisioCurvedTextWrite(VsdxShape shape) {
  return shape.withCurvedText(false).copyWith(
        richText: shape.richText.copyWith(
          textBlock: shape.richText.textBlock.copyWith(hideText: true),
        ),
      );
}

void _collectCurvedTextPlateIds(
  List<VsdxShape> shapes,
  Map<int, List<int>> into,
) {
  for (final shape in shapes) {
    final sourceId = libvisioCurvedTextSourceId(shape);
    if (sourceId != null) {
      (into[sourceId] ??= <int>[]).add(shape.id);
    }
    _collectCurvedTextPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioCurvedTextBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioCurvedTextPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioCurvedTextBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

VsdxShape? _findShapeById(List<VsdxShape> shapes, int id) {
  for (final shape in shapes) {
    if (shape.id == id) return shape;
    final nested = _findShapeById(shape.children, id);
    if (nested != null) return nested;
  }
  return null;
}

List<VsdxShape> _bakeCurvedTextTree(
  List<VsdxShape> shapes, {
  required Map<int, List<int>> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioCurvedTextPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeCurvedTextTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioCurvedTextBake(next)) {
      final plates = _curvedTextPlatesForLibvisioWrite(
        next,
        plateIds: plateIds[next.id] ?? const <int>[],
        nextId: nextId,
      );
      if (plates.isNotEmpty) {
        // Body first, then glyphs: later Draw z-order paints text on top,
        // and later Shadow/Sketch bakes keep that order when they rewrite
        // the source in place.
        out.add(_sourceForLibvisioCurvedTextWrite(next));
        out.addAll(plates);
        changed = true;
        continue;
      }
    } else {
      final existing = plateIds[next.id];
      if (existing != null) {
        out.add(next);
        for (final id in existing) {
          final kept = _findShapeById(shapes, id);
          if (kept != null) {
            out.add(kept);
          }
        }
        changed = true;
        continue;
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the per-glyph siblings Draw uses for Curved Text.
VsdxDocument bakeCurvedTextForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioCurvedTextBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, List<int>>{};
    _collectCurvedTextPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeCurvedTextTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages);
}

const _kLibvisioShapeInsideMaxLines = 24;

bool _shapeInsideDefaultTextBlock(VsdxShape shape) {
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final th = (block.heightInches ?? shape.height).abs();
  return (block.widthInches == null || (tw - shape.width).abs() < 1e-6) &&
      (block.heightInches == null || (th - shape.height).abs() < 1e-6) &&
      (block.pinXInches == null ||
          (block.pinXInches! - shape.width / 2).abs() < 1e-6) &&
      (block.pinYInches == null ||
          (block.pinYInches! - shape.height / 2).abs() < 1e-6);
}

/// `true` when `User.veShapeInside` must become per-line siblings for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so outline text-flow never becomes ODF. TxtWidth / HideText /
/// HorzAlign *are* collected, so a save places one locked line shape per
/// wrapped band canvas / SVG already paint, then hides the source and
/// drops the User row. Tab fields become spaces — canvas wrap units
/// already treat `\t` as a blank, and SVG skips outline flow when a
/// tab is present. Character Highlight (`readCharIX` is empty) becomes
/// FillForegnd on each band's plates so mixed markers follow the
/// outline. Glueable 1-D labels, vertical text, curved text
/// and TxtAngle stay native. FlipX / FlipY extra text mirrors about
/// TxtPin are baked so Draw keeps the upright bands. Field display
/// caches stay in the run text — plates copy those characters, then
/// HideText on the source so Draw does not keep a rectangular `<fld>`.
bool shapeNeedsLibvisioShapeInsideBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (!shape.shapeInside || !shape.supportsShapeInside) return false;
  if (!shape.wordWrap) return false;
  if (shape.curvedText) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  if (shape.richText.textBlock.angleRad.abs() > 1e-12) return false;
  if (!_shapeInsideDefaultTextBlock(shape)) return false;
  final plain = _shapeInsidePlain(shape);
  if (plain.trim().isEmpty) return false;
  for (final run in shape.richText.runs) {
    if (run.paraStyle.bullet != 0) return false;
    if (run.paraStyle.indentFirstInches.abs() > 1e-9) return false;
    if (run.paraStyle.indentLeftInches.abs() > 1e-9) return false;
    if (run.paraStyle.indentRightInches.abs() > 1e-9) return false;
  }
  return true;
}

String _shapeInsidePlain(VsdxShape shape) {
  final raw =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  final text =
      raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\t', ' ');
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return switch (style.textCase) {
    VsdxTextCase.allCaps => text.toUpperCase(),
    VsdxTextCase.initialCaps => _libvisioInitialCaps(text),
    VsdxTextCase.normal => text,
  };
}

VsdxCharStyle _shapeInsideStyle(VsdxShape shape) {
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return style.copyWith(textCase: VsdxTextCase.normal);
}

VsdxParaStyle _shapeInsidePara(VsdxShape shape) =>
    shape.richText.runs.isNotEmpty
        ? shape.richText.runs.first.paraStyle
        : const VsdxParaStyle();

double _shapeInsideLineHeight(VsdxShape shape) {
  final style = _shapeInsideStyle(shape);
  final para = _shapeInsidePara(shape);
  final plain = _shapeInsidePlain(shape);
  var fs = math.max(style.effectiveFontSizeInchesForText(plain), 0.04);
  if (para.lineSpacingAbsoluteInches > 1e-9) {
    return para.lineSpacingAbsoluteInches;
  }
  final mult = para.lineSpacingSolid ? 1.0 : para.lineSpacing;
  return fs *
      (mult <= 0
          ? 1.0
          : mult *
              (para.lineSpacingSolid
                  ? 1.0
                  : kLibreOfficeFontCellLineHeightFactor));
}

List<String> _libvisioWrapUnits(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  bool? inSpace;
  void flush() {
    if (buf.isEmpty) return;
    out.add(buf.toString());
    buf.clear();
  }

  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    final sp = ch == ' ' || ch == '\t';
    if (inSpace != null && inSpace != sp) flush();
    inSpace = sp;
    buf.write(ch);
  }
  flush();
  return out;
}

List<String> _wrapShapeInsideParagraph(
  String para,
  VsdxCharStyle style,
  double Function(int lineIndex) widthFor,
) {
  if (para.isEmpty) return <String>[''];
  final units = _libvisioWrapUnits(para);
  final lines = <String>[];
  var cur = StringBuffer();
  var curW = 0.0;
  var lineMax = widthFor(0);

  void flush() {
    lines.add(cur.toString());
    cur = StringBuffer();
    curW = 0.0;
    lineMax = widthFor(lines.length);
  }

  for (final unit in units) {
    final uw = nowrapTextAdvanceInches(unit, style);
    final isBlank = unit.trim().isEmpty;
    if (curW > 1e-9 && curW + uw > lineMax && !isBlank) {
      flush();
    }
    if (cur.isEmpty && isBlank) continue;
    if (uw > lineMax && unit.length > 1 && !isBlank) {
      for (final r in unit.runes) {
        final ch = String.fromCharCode(r);
        final cw = nowrapTextAdvanceInches(ch, style);
        if (curW > 1e-9 && curW + cw > lineMax) flush();
        cur.write(ch);
        curW += cw;
      }
      continue;
    }
    cur.write(unit);
    curW += uw;
  }
  if (cur.isNotEmpty || lines.isEmpty) flush();
  return lines;
}

({double left, double right}) _shapeInsideBandInches(
  VsdxShape shape, {
  required double y0,
  required double y1,
  required double tw,
  required double th,
  required double ml,
  required double mr,
  required double padding,
}) {
  final band = shape.shapeInsideBand(y0 / th, y1 / th);
  final left = math.max(ml, (band?.left ?? 0) * tw + padding);
  final right = math.min(tw - mr, (band?.right ?? 1) * tw - padding);
  return (left: left, right: math.max(left + 0.01, right));
}

typedef _InsideUnit = ({
  String text,
  VsdxCharStyle style,
  VsdxParaStyle para,
  double width,
});

bool _shapeInsideHasHighlight(VsdxShape shape) {
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    if (run.charStyle.highlight != null) return true;
  }
  return false;
}

bool _sameInsidePaintStyle(VsdxCharStyle a, VsdxCharStyle b) =>
    a.highlight?.value == b.highlight?.value &&
    a.color?.value == b.color?.value &&
    a.fontFamily == b.fontFamily &&
    a.fontSizeInches == b.fontSizeInches;

List<_InsideUnit> _mergeInsideUnits(List<_InsideUnit> units) {
  if (units.isEmpty) return units;
  final out = <_InsideUnit>[];
  for (final u in units) {
    if (out.isNotEmpty &&
        _sameInsidePaintStyle(out.last.style, u.style) &&
        out.last.para.effectiveHorizontalAlign ==
            u.para.effectiveHorizontalAlign) {
      final last = out.removeLast();
      out.add((
        text: last.text + u.text,
        style: last.style,
        para: last.para,
        width: last.width + u.width,
      ));
    } else {
      out.add(u);
    }
  }
  return out;
}

List<List<_InsideUnit>> _shapeInsideHighlightParagraphs(VsdxShape shape) {
  final paragraphs = <List<_InsideUnit>>[<_InsideUnit>[]];
  for (final run in shape.richText.runs) {
    final style = run.charStyle.copyWith(textCase: VsdxTextCase.normal);
    final cased = _libvisioApplyTextCase(run.text, run.charStyle.textCase)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\t', ' ');
    final parts = cased.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        for (final unit in _libvisioWrapUnits(parts[i])) {
          paragraphs.last.add((
            text: unit,
            style: style,
            para: run.paraStyle,
            width: nowrapTextAdvanceInches(unit, style),
          ));
        }
      }
      if (i != parts.length - 1) paragraphs.add(<_InsideUnit>[]);
    }
  }
  return paragraphs;
}

List<List<_InsideUnit>> _wrapShapeInsideStyledParagraph(
  List<_InsideUnit> units,
  double Function(int lineIndex) widthFor,
) {
  if (units.isEmpty) return <List<_InsideUnit>>[<_InsideUnit>[]];
  final lines = <List<_InsideUnit>>[];
  var cur = <_InsideUnit>[];
  var curW = 0.0;
  var lineMax = widthFor(0);

  void flush() {
    lines.add(cur);
    cur = <_InsideUnit>[];
    curW = 0.0;
    lineMax = widthFor(lines.length);
  }

  for (final unit in units) {
    final isBlank = unit.text.trim().isEmpty;
    if (curW > 1e-9 && curW + unit.width > lineMax && !isBlank) {
      flush();
    }
    if (cur.isEmpty && isBlank) continue;
    if (unit.width > lineMax && unit.text.length > 1 && !isBlank) {
      for (final r in unit.text.runes) {
        final ch = String.fromCharCode(r);
        final cw = nowrapTextAdvanceInches(ch, unit.style);
        if (curW > 1e-9 && curW + cw > lineMax) flush();
        cur.add((
          text: ch,
          style: unit.style,
          para: unit.para,
          width: cw,
        ));
        curW += cw;
      }
      continue;
    }
    cur.add(unit);
    curW += unit.width;
  }
  if (cur.isNotEmpty || lines.isEmpty) flush();
  return lines;
}

List<VsdxShape> _shapeInsideHighlightPlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final ml = block.marginLeftInches;
  final mr = block.marginRightInches;
  final mt = block.marginTopInches;
  final mb = block.marginBottomInches;
  final padding = source.shapeInsidePaddingPx / kLibvisioShapeInsidePxPerInch;
  final lineHeight = _shapeInsideLineHeight(source);
  if (tw <= 1e-9 || th <= 1e-9 || lineHeight <= 1e-9) {
    return const <VsdxShape>[];
  }
  final paragraphs = _shapeInsideHighlightParagraphs(source);
  var top = mt;
  var lines = <List<_InsideUnit>>[];
  for (var pass = 0; pass < 3; pass++) {
    lines = <List<_InsideUnit>>[];
    var index = 0;
    for (final paraUnits in paragraphs) {
      final wrapped = _wrapShapeInsideStyledParagraph(
        paraUnits,
        (i) {
          final y0 = top + (index + i) * lineHeight;
          return _shapeInsideBandInches(
                source,
                y0: y0,
                y1: y0 + lineHeight,
                tw: tw,
                th: th,
                ml: ml,
                mr: mr,
                padding: padding,
              ).right -
              _shapeInsideBandInches(
                source,
                y0: y0,
                y1: y0 + lineHeight,
                tw: tw,
                th: th,
                ml: ml,
                mr: mr,
                padding: padding,
              ).left;
        },
      );
      lines.addAll(wrapped);
      index += wrapped.length;
    }
    final total = lines.length * lineHeight;
    top = switch (block.verticalAlign) {
      VsdxVertAlign.top => mt,
      VsdxVertAlign.bottom => th - mb - total,
      VsdxVertAlign.middle => mt + (th - mt - mb - total) / 2,
    };
  }
  var visible = 0;
  for (final line in lines) {
    if (line.any((u) => u.text.trim().isNotEmpty)) visible++;
  }
  if (visible == 0 || visible > _kLibvisioShapeInsideMaxLines) {
    return const <VsdxShape>[];
  }

  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  final out = <VsdxShape>[];
  var glyph = 0;
  for (var i = 0; i < lines.length; i++) {
    final merged = _mergeInsideUnits(lines[i]);
    if (merged.every((u) => u.text.trim().isEmpty)) continue;
    final y0 = top + i * lineHeight;
    final band = _shapeInsideBandInches(
      source,
      y0: y0,
      y1: y0 + lineHeight,
      tw: tw,
      th: th,
      ml: ml,
      mr: mr,
      padding: padding,
    );
    final bw = band.right - band.left;
    var totalW = 0.0;
    for (final u in merged) {
      totalW += u.width;
    }
    final align = merged.isNotEmpty
        ? merged.first.para.effectiveHorizontalAlign
        : VsdxHorzAlign.left;
    var origin = band.left;
    switch (align) {
      case VsdxHorzAlign.center:
        origin += math.max(0.0, (bw - totalW) / 2);
      case VsdxHorzAlign.right:
        origin += math.max(0.0, bw - totalW);
      case VsdxHorzAlign.left:
      case VsdxHorzAlign.justify:
      case VsdxHorzAlign.full:
        break;
    }
    var x = origin;
    final midYDown = y0 + lineHeight / 2;
    for (final u in merged) {
      final text = u.text;
      if (text.trim().isNotEmpty) {
        final highlight = u.style.highlight;
        final plateStyle = u.style.copyWith(clearHighlight: true);
        final pw = math.max(u.width, lineHeight) * 1.2;
        final ph = lineHeight;
        final local = _textFlipAboutPin(
          source,
          Offset2D(originX + x + u.width / 2, originY + th - midYDown),
        );
        final page = _parentFromLocal(source, local);
        final id = glyph < plateIds.length ? plateIds[glyph] : nextId();
        out.add(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: page.x,
            pinY: page.y,
            width: pw,
            height: ph,
            fill: highlight != null
                ? VsdxFill(foreground: highlight, pattern: 1)
                : const VsdxFill(pattern: 0),
            line: const VsdxLine(pattern: 0),
            name: '$kLibvisioShapeInsideShapeNamePrefix$glyph.${source.id}',
          ).copyWith(
            locPinXInches: pw / 2,
            locPinYInches: ph / 2,
            angleRad: source.angleRad,
            locked: true,
            layerMemberIds: source.layerMemberIds,
            text: text,
            richText: VsdxRichText(
              runs: <VsdxTextRun>[
                VsdxTextRun(
                  text: text,
                  charStyle: plateStyle,
                  paraStyle: const VsdxParaStyle(
                    horizontalAlign: VsdxHorzAlign.center,
                  ),
                ),
              ],
              textBlock: VsdxTextBlock(
                widthInches: pw,
                heightInches: ph,
                locPinXInches: pw / 2,
                locPinYInches: ph / 2,
                verticalAlign: VsdxVertAlign.middle,
              ),
            ),
          ),
        );
        glyph++;
      }
      x += u.width;
    }
  }
  return out;
}

List<VsdxShape> _shapeInsidePlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  if (_shapeInsideHasHighlight(source)) {
    return _shapeInsideHighlightPlatesForLibvisioWrite(
      source,
      plateIds: plateIds,
      nextId: nextId,
    );
  }
  final style = _shapeInsideStyle(source);
  final para = _shapeInsidePara(source);
  final plain = _shapeInsidePlain(source);
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final ml = block.marginLeftInches;
  final mr = block.marginRightInches;
  final mt = block.marginTopInches;
  final mb = block.marginBottomInches;
  final padding = source.shapeInsidePaddingPx / kLibvisioShapeInsidePxPerInch;
  final lineHeight = _shapeInsideLineHeight(source);
  if (tw <= 1e-9 || th <= 1e-9 || lineHeight <= 1e-9) {
    return const <VsdxShape>[];
  }
  final paragraphs = plain.split('\n');
  var top = mt;
  var lines = <String>[];
  for (var pass = 0; pass < 3; pass++) {
    lines = <String>[];
    var index = 0;
    for (final paraText in paragraphs) {
      final wrapped = _wrapShapeInsideParagraph(
        paraText,
        style,
        (i) {
          final y0 = top + (index + i) * lineHeight;
          return _shapeInsideBandInches(
                source,
                y0: y0,
                y1: y0 + lineHeight,
                tw: tw,
                th: th,
                ml: ml,
                mr: mr,
                padding: padding,
              ).right -
              _shapeInsideBandInches(
                source,
                y0: y0,
                y1: y0 + lineHeight,
                tw: tw,
                th: th,
                ml: ml,
                mr: mr,
                padding: padding,
              ).left;
        },
      );
      lines.addAll(wrapped);
      index += wrapped.length;
    }
    final total = lines.length * lineHeight;
    top = switch (block.verticalAlign) {
      VsdxVertAlign.top => mt,
      VsdxVertAlign.bottom => th - mb - total,
      VsdxVertAlign.middle => mt + (th - mt - mb - total) / 2,
    };
  }
  var visible = 0;
  for (final line in lines) {
    if (line.trim().isNotEmpty) visible++;
  }
  if (visible == 0 || visible > _kLibvisioShapeInsideMaxLines) {
    return const <VsdxShape>[];
  }

  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  final out = <VsdxShape>[];
  var glyph = 0;
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].trim();
    if (text.isEmpty) continue;
    final y0 = top + i * lineHeight;
    final band = _shapeInsideBandInches(
      source,
      y0: y0,
      y1: y0 + lineHeight,
      tw: tw,
      th: th,
      ml: ml,
      mr: mr,
      padding: padding,
    );
    final bw = band.right - band.left;
    final midX = (band.left + band.right) / 2;
    final midYDown = y0 + lineHeight / 2;
    final local = _textFlipAboutPin(
      source,
      Offset2D(originX + midX, originY + th - midYDown),
    );
    final page = _parentFromLocal(source, local);
    final id = glyph < plateIds.length ? plateIds[glyph] : nextId();
    out.add(
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: page.x,
        pinY: page.y,
        width: bw,
        height: lineHeight,
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        name: '$kLibvisioShapeInsideShapeNamePrefix$glyph.${source.id}',
      ).copyWith(
        locPinXInches: bw / 2,
        locPinYInches: lineHeight / 2,
        angleRad: source.angleRad,
        locked: true,
        layerMemberIds: source.layerMemberIds,
        text: text,
        richText: VsdxRichText(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: style,
              paraStyle: VsdxParaStyle(
                horizontalAlign: para.effectiveHorizontalAlign,
              ),
            ),
          ],
          textBlock: VsdxTextBlock(
            widthInches: bw,
            heightInches: lineHeight,
            locPinXInches: bw / 2,
            locPinYInches: lineHeight / 2,
            verticalAlign: VsdxVertAlign.middle,
          ),
        ),
      ),
    );
    glyph++;
  }
  return out;
}

VsdxShape _sourceForLibvisioShapeInsideWrite(VsdxShape shape) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userShapeInside &&
          cell.name != VsdxShape.userShapeInsidePadding)
        cell,
  ];
  return shape.copyWith(
    userCells: others,
    richText: shape.richText.copyWith(
      textBlock: shape.richText.textBlock.copyWith(hideText: true),
    ),
  );
}

void _collectShapeInsidePlateIds(
  List<VsdxShape> shapes,
  Map<int, List<int>> into,
) {
  for (final shape in shapes) {
    final sourceId = libvisioShapeInsideSourceId(shape);
    if (sourceId != null) {
      (into[sourceId] ??= <int>[]).add(shape.id);
    }
    _collectShapeInsidePlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioShapeInsideBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioShapeInsidePlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioShapeInsideBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeShapeInsideTree(
  List<VsdxShape> shapes, {
  required Map<int, List<int>> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioShapeInsidePlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeShapeInsideTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioShapeInsideBake(next)) {
      final plates = _shapeInsidePlatesForLibvisioWrite(
        next,
        plateIds: plateIds[next.id] ?? const <int>[],
        nextId: nextId,
      );
      if (plates.isNotEmpty) {
        out.add(_sourceForLibvisioShapeInsideWrite(next));
        out.addAll(plates);
        changed = true;
        continue;
      }
    } else {
      final existing = plateIds[next.id];
      if (existing != null) {
        out.add(next);
        for (final id in existing) {
          final kept = _findShapeById(shapes, id);
          if (kept != null) {
            out.add(kept);
          }
        }
        changed = true;
        continue;
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the per-line siblings Draw uses for Shape Inside.
VsdxDocument bakeShapeInsideForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioShapeInsideBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, List<int>>{};
    _collectShapeInsidePlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeShapeInsideTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages);
}

/// `true` when `TextDirection=1` must become a `TxtAngle` Draw paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `TextDirection` *is* a
/// token (`readTextBlockIX` stores it) but `_flushText` never writes
/// `style:writing-mode` or extra rotation, so Draw lays the run out
/// horizontally. Canvas / SVG rotate −90° about the text-block centre
/// and swap width×height (margins remapped likewise). `TxtAngle` *is*
/// collected (`m_txtxform->angle` → `librevenge:rotate`), so a save
/// folds that rotation into TxtAngle, swaps TxtWidth/TxtHeight, remaps
/// LocPin so the box centre stays on TxtPin, writes TextDirection=0 so
/// canvas reopen does not rotate twice, and drops Txt* formulas that
/// would restore the unswapped box. Glueable labels with no TxtPin are
/// pinned to the route first, then that tight plate swaps the same way
/// so Draw's TextBkgnd stands at the elbow (`TxtAngle` stays 0 so
/// `librevenge:rotate` does not lay it back down, unless Rotate with
/// Edge later writes the route tangent). Curved text and
/// Shape Inside stay native — their layout is not a swapped rectangle.
bool shapeNeedsLibvisioTextDirectionBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.curvedText || shape.shapeInside) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection != 1) return false;
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  if (!hasText) return false;
  if (shape.isGlueableConnector) return true;
  if (shape.is1D) {
    final block = shape.richText.textBlock;
    return block.pinXInches != null || block.pinYInches != null;
  }
  return true;
}

/// Fold `TextDirection=1` into `TxtAngle` / swapped TxtWidth×TxtHeight.
///
/// [addAngle] is false for a loose connector plate: Draw's
/// `librevenge:rotate` would lay the already-swapped box back down.
VsdxShape _sourceForLibvisioTextDirectionWrite(
  VsdxShape shape, {
  bool addAngle = true,
}) {
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final th = (block.heightInches ?? shape.height).abs();
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  // Extra −90° is about TxtPin in Draw. Canvas TextDirection rotates
  // about the block centre, so LocPin moves to keep that centre fixed:
  // L' = (th − Ly, Lx). Draw's TextBkgnd follows this swapped box.
  final nextBlock = VsdxTextBlock(
    pinXInches: block.pinXInches ?? shape.width / 2,
    pinYInches: block.pinYInches ?? shape.height / 2,
    locPinXInches: th - locY,
    locPinYInches: locX,
    widthInches: th,
    heightInches: tw,
    angleRad: addAngle ? block.angleRad - math.pi / 2 : block.angleRad,
    verticalAlign: block.verticalAlign,
    marginLeftInches: block.marginTopInches,
    marginRightInches: block.marginBottomInches,
    marginTopInches: block.marginRightInches,
    marginBottomInches: block.marginLeftInches,
    hideText: block.hideText,
    backgroundColor: block.backgroundColor,
    backgroundTransparency: block.backgroundTransparency,
    textDirection: 0,
    defaultTabStopInches: block.defaultTabStopInches,
  );
  var formulas = shape.formulas;
  const keys = <String>[
    'TxtWidth',
    'TxtHeight',
    'TxtLocPinX',
    'TxtLocPinY',
    'TxtPinX',
    'TxtPinY',
    'TxtAngle',
    'TextDirection',
  ];
  if (keys.any(formulas.containsKey)) {
    formulas = Map<String, String>.of(shape.formulas);
    for (final key in keys) {
      formulas.remove(key);
    }
  }
  // Keep `veAutoRotateLabel` so the later tangent bake can write TxtAngle
  // onto this swapped plate. Dropping it here left Draw with a vertical
  // bar and no route heading.
  return shape.copyWith(
    richText: shape.richText.copyWith(textBlock: nextBlock),
    formulas: formulas,
  );
}

VsdxShape bakeTextDirectionShapeForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeTextDirectionShapeForLibvisioWrite(child, page),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioTextDirectionBake(shape)) {
    final loose = shape.isGlueableConnector && _missingEdgeLabelPin(shape);
    final framed = loose ? _applyLooseEdgeLabelFrame(shape, page) : shape;
    next = _sourceForLibvisioTextDirectionWrite(
      framed,
      addAngle: !loose,
    );
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Write `TxtAngle` Draw collects for vertical text, then drop TextDirection.
VsdxDocument bakeTextDirectionForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeTextDirectionShapeForLibvisioWrite(shape, page),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when `User.veAutoRotateLabel` must become a `TxtAngle` Draw paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `labelAutoRotate` never becomes ODF rotation. `TxtAngle` *is*
/// collected (`m_txtxform->angle` → `transformAngle`), so a save writes the
/// same upright route tangent canvas / SVG already paint and drops the
/// User row. Isolated vertical text still skips here; `TextDirection`
/// folds first and leaves this User row so the tangent lands on the
/// swapped plate. Vertices stay native.
bool shapeNeedsLibvisioAutoRotateLabelBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.isGlueableConnector) return false;
  if (!shape.autoRotateLabel) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  return !shape.richText.isEmpty ||
      (shape.text != null && shape.text!.isNotEmpty);
}

Offset2D _libvisioRouteMidpoint(List<Offset2D> route) {
  if (route.isEmpty) return const Offset2D(0, 0);
  if (route.length == 1) return route.first;
  var total = 0.0;
  for (var i = 1; i < route.length; i++) {
    final dx = route[i].x - route[i - 1].x;
    final dy = route[i].y - route[i - 1].y;
    total += math.sqrt(dx * dx + dy * dy);
  }
  if (total <= 1e-18) return route.first;
  var remaining = total / 2;
  for (var i = 1; i < route.length; i++) {
    final a = route[i - 1];
    final b = route[i];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length >= remaining) {
      final t = length <= 1e-18 ? 0.0 : remaining / length;
      return Offset2D(a.x + dx * t, a.y + dy * t);
    }
    remaining -= length;
  }
  return route.last;
}

/// Canvas / SVG treat a glueable label as loose whenever `TxtPin` is
/// missing — authored `TxtWidth` is ignored and glyphs centre on the
/// route. Draw is different: any TxtWidth cell constructs `m_txtxform`
/// whose unset pin stays `XForm()`'s 0,0.
bool _missingEdgeLabelPin(VsdxShape shape) {
  final block = shape.richText.textBlock;
  return block.pinXInches == null && block.pinYInches == null;
}

bool _hasLooseEdgeLabelText(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  final plain =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  return plain.trim().isNotEmpty;
}

/// Pin a tight text box on the drawn-route midpoint canvas / SVG already use.
///
/// LibreOffice's collector falls back to the 1-D XForm (`m_xform.width/2`)
/// when `m_txtxform` is missing, which is the Begin–End box — not the
/// polyline. A lone TxtWidth still builds `m_txtxform` with pin 0,0.
/// TxtPin / TxtWidth *are* collected. An authored wide TxtWidth is
/// rewritten tight so left-align cannot sit a box-width away from the
/// pin the way canvas glyph-centring does.
VsdxShape _applyLooseEdgeLabelFrame(VsdxShape shape, VsdxPage page) {
  if (!_missingEdgeLabelPin(shape)) return shape;
  final previous = shape.richText.textBlock;
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  final plain =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  final lines =
      plain.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  var fs = math.max(style.effectiveFontSizeInchesForText(plain), 0.04);
  if (style.position != VsdxTextPosition.normal) fs *= 0.7;
  final lineHeight = fs * kLibreOfficeFontCellLineHeightFactor;
  final tw = math.max(
    nowrapLabelAdvanceInches(shape) +
        previous.marginLeftInches +
        previous.marginRightInches +
        0.06,
    0.2,
  );
  final th = math.max(
    lines.length * lineHeight +
        previous.marginTopInches +
        previous.marginBottomInches,
    0.2,
  );
  final route = page.drawnConnectorPagePolyline(shape);
  final mid = route.length >= 2
      ? _libvisioRouteMidpoint(route)
      : VsdxPage.connectorMidpoint(shape);
  final local = page.pageToLocalDeep(shape.id, mid);
  return shape.copyWith(
    richText: shape.richText.copyWith(
      textBlock: VsdxTextBlock(
        pinXInches: local.x,
        pinYInches: local.y,
        locPinXInches: tw / 2,
        locPinYInches: th / 2,
        widthInches: tw,
        heightInches: th,
        angleRad: previous.angleRad,
        verticalAlign: previous.verticalAlign,
        marginLeftInches: previous.marginLeftInches,
        marginRightInches: previous.marginRightInches,
        marginTopInches: previous.marginTopInches,
        marginBottomInches: previous.marginBottomInches,
        hideText: previous.hideText,
        backgroundColor: previous.backgroundColor,
        backgroundTransparency: previous.backgroundTransparency,
        textDirection: previous.textDirection,
        defaultTabStopInches: previous.defaultTabStopInches,
      ),
    ),
  );
}

VsdxShape _sourceForLibvisioAutoRotateLabelWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userAutoRotateLabel) cell,
  ];
  final framed = _applyLooseEdgeLabelFrame(shape, page);
  final previous = framed.richText.textBlock;
  final angle = page.effectiveConnectorLabelAngle(shape);
  // `copyWith(angleRad: 0)` cannot clear a previous TxtAngle because `??`
  // treats 0 as absent. Reconstruct so a horizontal route still writes 0.
  final block = VsdxTextBlock(
    pinXInches: previous.pinXInches,
    pinYInches: previous.pinYInches,
    locPinXInches: previous.locPinXInches,
    locPinYInches: previous.locPinYInches,
    widthInches: previous.widthInches,
    heightInches: previous.heightInches,
    angleRad: angle,
    verticalAlign: previous.verticalAlign,
    marginLeftInches: previous.marginLeftInches,
    marginRightInches: previous.marginRightInches,
    marginTopInches: previous.marginTopInches,
    marginBottomInches: previous.marginBottomInches,
    hideText: previous.hideText,
    backgroundColor: previous.backgroundColor,
    backgroundTransparency: previous.backgroundTransparency,
    textDirection: previous.textDirection,
    defaultTabStopInches: previous.defaultTabStopInches,
  );
  return framed.copyWith(
    userCells: others,
    richText: framed.richText.copyWith(textBlock: block),
  );
}

VsdxShape bakeAutoRotateLabelShapeForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeAutoRotateLabelShapeForLibvisioWrite(child, page),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shapeNeedsLibvisioAutoRotateLabelBake(shape)
      ? _sourceForLibvisioAutoRotateLabelWrite(shape, page)
      : shape;
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Write `TxtAngle` Draw collects for Rotate with Edge, then drop the User row.
VsdxDocument bakeAutoRotateLabelForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeAutoRotateLabelShapeForLibvisioWrite(shape, page),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when a glueable connector label with no `TxtPin` must become a
/// tight `TxtPin` / `TxtWidth` box Draw will collect.
///
/// LibreOffice only calls `VisioDocument::parse`. Missing `m_txtxform`
/// falls back to the 1-D XForm centre (Begin–End box). A TxtWidth
/// without TxtPin still constructs `m_txtxform` (`XForm` pin defaults
/// to 0). Canvas / SVG pin a tight plate on the drawn-route midpoint
/// whenever TxtPin is missing. Rotate-with-Edge already writes that
/// frame; this covers labels that are not auto-rotated.
bool shapeNeedsLibvisioLooseEdgeLabelBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.isGlueableConnector) return false;
  if (!_missingEdgeLabelPin(shape)) return false;
  return _hasLooseEdgeLabelText(shape);
}

VsdxShape bakeLooseEdgeLabelShapeForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeLooseEdgeLabelShapeForLibvisioWrite(child, page),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shapeNeedsLibvisioLooseEdgeLabelBake(shape)
      ? _applyLooseEdgeLabelFrame(shape, page)
      : shape;
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Write TxtPin on the route midpoint so Draw matches canvas edge labels.
VsdxDocument bakeLooseEdgeLabelForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeLooseEdgeLabelShapeForLibvisioWrite(shape, page),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when `User.veOpacity` must fold into cells Draw actually paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veOpacity` never becomes ODF `draw:opacity`. FillForegndTrans
/// *is* collected (`VSDContentCollector` maps it to `draw:opacity`), and
/// unfilled LineColorTrans already bakes a FillForegndTrans ribbon, so a
/// save multiplies the extra transparency into Fill / Line / Glow /
/// Reflection / Shadow / image / text, then drops the User row.
bool shapeNeedsLibvisioOpacityBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  return shape.shapeOpacity < 1 - 1e-9;
}

VsdxGradient? _gradientWithExtraTransparency(
  VsdxGradient? gradient,
  double extra,
) {
  if (gradient == null || extra <= 1e-9) return gradient;
  return VsdxGradient(
    stops: <VsdxGradientStop>[
      for (final stop in gradient.stops)
        VsdxGradientStop(
          position: stop.position,
          color: stop.color,
          themeColorIndex: stop.themeColorIndex,
          transparency: _combinedTransparency(stop.transparency, extra),
        ),
    ],
    type: gradient.type,
    angleRad: gradient.angleRad,
    dir: gradient.dir,
  );
}

VsdxFill _fillWithExtraTransparency(VsdxFill fill, double extra) {
  return fill.copyWith(
    foregroundTransparency:
        _combinedTransparency(fill.foregroundTransparency, extra),
    backgroundTransparency:
        _combinedTransparency(fill.backgroundTransparency, extra),
    gradient: _gradientWithExtraTransparency(fill.gradient, extra),
  );
}

VsdxLine _lineWithExtraTransparency(VsdxLine line, double extra) {
  var next = line.copyWith(
    transparency: _combinedTransparency(line.transparency, extra),
  );
  final gradient = _gradientWithExtraTransparency(line.gradient, extra);
  if (!identical(gradient, line.gradient)) {
    next = next.copyWith(gradient: gradient);
  }
  return next;
}

VsdxRichText _richTextWithExtraTransparency(VsdxRichText rich, double extra) {
  return rich.copyWith(
    runs: <VsdxTextRun>[
      for (final run in rich.runs)
        run.copyWith(
          charStyle: run.charStyle.copyWith(
            transparency: _combinedTransparency(
              run.charStyle.transparency,
              extra,
            ),
          ),
        ),
    ],
    textBlock: rich.textBlock.copyWith(
      backgroundTransparency: _combinedTransparency(
        rich.textBlock.backgroundTransparency,
        extra,
      ),
    ),
  );
}

VsdxShape _applyOpacityForLibvisioWrite(VsdxShape shape, double extra) {
  var next = shape.withShapeOpacity(1);
  if (extra <= 1e-9) return next;
  if (next.fill.hasFill) {
    next = next.copyWith(fill: _fillWithExtraTransparency(next.fill, extra));
  }
  if (next.line.hasLine) {
    next = next.copyWith(line: _lineWithExtraTransparency(next.line, extra));
  }
  if (next.glow.enabled) {
    next = next.copyWith(
      glow: next.glow.copyWith(
        transparency: _combinedTransparency(next.glow.transparency, extra),
      ),
    );
  }
  if (next.reflection.enabled) {
    next = next.copyWith(
      reflection: next.reflection.copyWith(
        transparency:
            _combinedTransparency(next.reflection.transparency, extra),
      ),
    );
  }
  if (next.shadow.enabled) {
    next = next.copyWith(
      shadow: next.shadow.copyWith(
        transparency: _combinedTransparency(next.shadow.transparency, extra),
      ),
    );
  }
  if (next.hasImage) {
    next = next.copyWith(
      imageTransparency: _combinedTransparency(next.imageTransparency, extra),
    );
  }
  if (next.richText.runs.isNotEmpty ||
      next.richText.textBlock.backgroundColor != null) {
    next = next.copyWith(
      richText: _richTextWithExtraTransparency(next.richText, extra),
    );
  }
  return next;
}

VsdxShape bakeShapeOpacityShapeForLibvisioWrite(
  VsdxShape shape, {
  double inheritedExtra = 0,
}) {
  final extra = _combinedTransparency(1 - shape.shapeOpacity, inheritedExtra);
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeShapeOpacityShapeForLibvisioWrite(child, inheritedExtra: extra),
  ];
  var next = extra > 1e-9 || shapeNeedsLibvisioOpacityBake(shape)
      ? _applyOpacityForLibvisioWrite(shape, extra)
      : shape;
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Fold `User.veOpacity` into FillForegndTrans / LineColorTrans cells Draw
/// collects, including inherited fade on grouped children.
VsdxDocument bakeShapeOpacityForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeShapeOpacityShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// SoftEdgesSize Draw will collect for this picture (0 = do not bake).
///
/// Canvas / SVG feather the visible Img* window, clipped to the Foreign
/// frame. `tokens.txt` has no SoftEdgesSize, so a 2-D bitmap bakes that
/// halo into PNG alpha. Cropped frames composite into the box first;
/// uncropped frames feather the bitmap in place.
double imageSoftEdgesInchesForLibvisioWrite(VsdxShape shape) {
  if (!shape.hasImage || shape.is1D) return 0;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return 0;
  return shape.line.softEdgesInches;
}

/// `true` when Img* crop must composite into the Foreign frame for Draw.
///
/// libvisio collects ImgOffset / ImgWidth / ImgHeight, but it emits
/// `svg:width` from ImgWidth. Draw paints that unclipped bitmap; canvas /
/// SVG clip to the box. A save writes a frame-sized PNG. 1-D pictures stay
/// native (no Foreign box to clip). A second save does not restack: Img*
/// already fill the frame.
bool shapeNeedsLibvisioImageCropBake(VsdxShape shape) {
  if (!shape.hasImage || shape.is1D) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  return visioPictureFrameIsCropped(
    frameWidthInches: shape.width,
    frameHeightInches: shape.height,
    imgOffsetXInches: shape.imgOffsetXInches,
    imgOffsetYInches: shape.imgOffsetYInches,
    imgWidthInches: shape.imgWidthInches,
    imgHeightInches: shape.imgHeightInches,
  );
}

/// `true` when SoftEdges must composite Img* crop into the Foreign frame.
bool shapeNeedsLibvisioCroppedSoftEdgesBake(VsdxShape shape) {
  if (imageSoftEdgesInchesForLibvisioWrite(shape) <= 1e-6) return false;
  return visioPictureFrameIsCropped(
    frameWidthInches: shape.width,
    frameHeightInches: shape.height,
    imgOffsetXInches: shape.imgOffsetXInches,
    imgOffsetYInches: shape.imgOffsetYInches,
    imgWidthInches: shape.imgWidthInches,
    imgHeightInches: shape.imgHeightInches,
  );
}

/// `true` when Foreign EnhMetaFile / MetaFile must become a Bitmap PNG for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `ForeignType=EnhMetaFile`
/// / `MetaFile` still becomes `image/emf` / `image/wmf`, and Draw fills
/// the default Blue 2 graphic style instead of replaying those records,
/// while canvas / SVG already extract a wrapped DIB or replay the vector
/// display list, including ExtTextOut glyphs, GDI hatch / pattern
/// brushes and clips. A save writes an opaque PNG
/// `ForeignType=Bitmap`. A second save does not stack another PNG.
bool shapeNeedsLibvisioMetafileBitmapBake(VsdxShape shape) {
  if (!shape.hasImage) return false;
  final type = shape.foreignType ??
      VsdxImage.foreignTypeFor(
        mimeType: '',
        partName: shape.imagePartName ?? '',
      );
  return type == 'EnhMetaFile' || type == 'MetaFile';
}

/// Extract a wrapped EMF/WMF DIB, or replay a vector metafile, as opaque PNG.
VsdxDocument bakeMetafileBitmapsForLibvisioWrite(VsdxDocument document) {
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  final cache = <String, String>{};
  var changed = false;

  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_emf_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_emf_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    if (shapeNeedsLibvisioMetafileBitmapBake(shape)) {
      final source =
          _imageForLibvisioWrite(document.images, shape.imagePartName);
      if (source != null) {
        var bakedPart = cache[source.partName];
        if (bakedPart == null) {
          final wrapped = source.rasterForRendering();
          final bytes = wrapped != null && wrapped.bytes.isNotEmpty
              ? wrapped.bytes
              : rasterizeVectorMetafileToPng(
                  source.bytes,
                  mimeType: source.mimeType,
                  partName: source.partName,
                );
          if (bytes != null && bytes.isNotEmpty) {
            bakedPart = allocatePart(shape.id);
            cache[source.partName] = bakedPart;
            registry = registry.withImage(
              VsdxImage(
                partName: bakedPart,
                bytes: bytes,
                mimeType: 'image/png',
              ),
            );
          }
        }
        if (bakedPart != null) {
          next = shape.copyWith(
            imagePartName: bakedPart,
            foreignType: VsdxImage.foreignTypeFor(
              mimeType: 'image/png',
              partName: bakedPart,
            ),
            foreignCompressionType: VsdxImage.compressionTypeFor(
              mimeType: 'image/png',
              partName: bakedPart,
            ),
          );
          changed = true;
        }
      }
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) {
      next = next.copyWith(children: children);
      changed = true;
    }
    return next;
  }

  if (document.pages.isEmpty && document.images.length == 0) {
    return document;
  }
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) rewrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!changed && !pagesChanged) return document;
  return document.copyWith(
    pages: pagesChanged ? pages : document.pages,
    images: registry,
  );
}

/// CompressionType libvisio will see for this Foreign Bitmap.
///
/// Matches [VsdxWriter]: an explicit `None` is stripped, and a missing
/// cell is inferred from the part extension only. Format 255 then becomes
/// `image/bmp`.
String? _libvisioWrittenBitmapCompression(VsdxShape shape) {
  final explicit = shape.foreignCompressionType;
  if (explicit != null && explicit.toLowerCase() == 'none') return null;
  return explicit ??
      VsdxImage.compressionTypeFor(
        mimeType: '',
        partName: shape.imagePartName ?? '',
      );
}

/// `true` when a Bitmap payload would be labelled `image/bmp` but is not a BMP.
///
/// `readForeignData` maps a missing CompressionType to format 255 →
/// `image/bmp`. Draw paints a `BM` file on that path; WebP / ICO /
/// headerless DIB / a PNG sitting on `.bin` disappear. Canvas / SVG
/// already decode those rasters. [image] is the Foreign media part.
bool shapeNeedsLibvisioUnsupportedBitmapBake(
  VsdxShape shape, [
  VsdxImage? image,
]) {
  if (!shape.hasImage) return false;
  final type = shape.foreignType ??
      image?.foreignType ??
      VsdxImage.foreignTypeFor(
        mimeType: '',
        partName: shape.imagePartName ?? '',
      );
  if (type != 'Bitmap') return false;
  if (_libvisioWrittenBitmapCompression(shape) != null) return false;
  if (image != null && image.looksLikeBmpFile) return false;
  if (image != null) return image.pngBytesForLibvisioWrite() != null;
  final part = (shape.imagePartName ?? '').toLowerCase();
  return part.endsWith('.webp') ||
      part.endsWith('.ico') ||
      part.endsWith('.dib');
}

/// Re-encode Bitmap payloads libvisio would mislabel as BMP into PNG.
VsdxDocument bakeUnsupportedBitmapsForLibvisioWrite(VsdxDocument document) {
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  final cache = <String, String>{};
  var changed = false;

  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_bmp_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_bmp_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    final source = _imageForLibvisioWrite(document.images, shape.imagePartName);
    if (shapeNeedsLibvisioUnsupportedBitmapBake(shape, source) &&
        source != null) {
      var bakedPart = cache[source.partName];
      if (bakedPart == null) {
        final bytes = source.pngBytesForLibvisioWrite();
        if (bytes != null && bytes.isNotEmpty) {
          bakedPart = allocatePart(shape.id);
          cache[source.partName] = bakedPart;
          registry = registry.withImage(
            VsdxImage(
              partName: bakedPart,
              bytes: bytes,
              mimeType: 'image/png',
            ),
          );
        }
      }
      if (bakedPart != null) {
        next = shape.copyWith(
          imagePartName: bakedPart,
          foreignType: VsdxImage.foreignTypeFor(
            mimeType: 'image/png',
            partName: bakedPart,
          ),
          foreignCompressionType: VsdxImage.compressionTypeFor(
            mimeType: 'image/png',
            partName: bakedPart,
          ),
        );
        changed = true;
      }
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) {
      next = next.copyWith(children: children);
      changed = true;
    }
    return next;
  }

  if (document.pages.isEmpty && document.images.length == 0) {
    return document;
  }
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) rewrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!changed && !pagesChanged) return document;
  return document.copyWith(
    pages: pagesChanged ? pages : document.pages,
    images: registry,
  );
}

({Uint8List bytes, String mime, String ext})? _olePreviewForLibvisioWrite(
  VsdxImage source,
) {
  final preview = extractOlePresentationMetafile(source.bytes);
  if (preview == null || preview.isEmpty) return null;
  if (looksLikeWmf(preview)) {
    return (bytes: preview, mime: 'image/x-wmf', ext: 'wmf');
  }
  if (looksLikeEmf(preview)) {
    return (bytes: preview, mime: 'image/x-emf', ext: 'emf');
  }
  return null;
}

/// `true` when Foreign Object must unwrap its OlePres preview for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. libvisio emits
/// `object/ole` for `ForeignType=Object`, and Draw paints the default
/// Blue 2 graphic style instead of the `\x02OlePres000` WMF/EMF canvas /
/// SVG already replay. A save writes that preview as `MetaFile` /
/// `EnhMetaFile`. Objects without a presentation stay native. A second
/// save does not unwrap again.
bool shapeNeedsLibvisioOlePreviewBake(VsdxShape shape) {
  if (!shape.hasImage) return false;
  final type = shape.foreignType ??
      VsdxImage.foreignTypeFor(
        mimeType: '',
        partName: shape.imagePartName ?? '',
      );
  if (type == 'Object') return true;
  return false;
}

/// Unwrap OLE OlePres WMF/EMF so Draw paints the preview ForeignData.
VsdxDocument bakeOlePreviewsForLibvisioWrite(VsdxDocument document) {
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  final cache = <String, String>{};
  var changed = false;

  String allocatePart(int shapeId, String ext) {
    var name = '/visio/media/image_lo_ole_$shapeId.$ext';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_ole_${shapeId}_$n.$ext';
    }
    used.add(name);
    return name;
  }

  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    if (shapeNeedsLibvisioOlePreviewBake(shape)) {
      final source =
          _imageForLibvisioWrite(document.images, shape.imagePartName);
      if (source != null) {
        var bakedPart = cache[source.partName];
        if (bakedPart == null) {
          final preview = _olePreviewForLibvisioWrite(source);
          if (preview != null) {
            bakedPart = allocatePart(shape.id, preview.ext);
            cache[source.partName] = bakedPart;
            registry = registry.withImage(
              VsdxImage(
                partName: bakedPart,
                bytes: preview.bytes,
                mimeType: preview.mime,
              ),
            );
          }
        }
        if (bakedPart != null) {
          final bakedImage = registry.findByPart(bakedPart)!;
          next = shape.copyWith(
            imagePartName: bakedPart,
            foreignType: VsdxImage.foreignTypeFor(
              mimeType: bakedImage.mimeType,
              partName: bakedPart,
            ),
            foreignCompressionType: VsdxImage.compressionTypeFor(
              mimeType: bakedImage.mimeType,
              partName: bakedPart,
            ),
          );
          changed = true;
        }
      }
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) {
      next = next.copyWith(children: children);
      changed = true;
    }
    return next;
  }

  if (document.pages.isEmpty && document.images.length == 0) {
    return document;
  }
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) rewrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!changed && !pagesChanged) return document;
  return document.copyWith(
    pages: pagesChanged ? pages : document.pages,
    images: registry,
  );
}

/// Bake Image Properties into PNG pixels and reset the cells Draw ignores.
VsdxDocument bakeImageAdjustmentsForLibvisioWrite(VsdxDocument document) {
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  final cache = <String, String>{};
  var changed = false;

  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_tone_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_tone_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    final soft = imageSoftEdgesInchesForLibvisioWrite(shape);
    final cropped = shapeNeedsLibvisioImageCropBake(shape);
    if (shape.hasImage &&
        (visioImageAdjustmentsNeedBake(
              transparency: shape.imageTransparency,
              blur: shape.imageBlur,
              brightness: shape.imageBrightness,
              contrast: shape.imageContrast,
              softEdgesInches: soft,
            ) ||
            cropped)) {
      final part = shape.imagePartName;
      final source = part == null
          ? null
          : (document.images.findByPart(part) ??
              document.images.findByPart(
                part.startsWith('/') ? part.substring(1) : '/$part',
              ));
      if (source != null) {
        final key = '$part|${shape.imageTransparency}|${shape.imageBlur}|'
            '${shape.imageBrightness}|${shape.imageContrast}|$soft|'
            '${shape.effectiveImgWidth}|${shape.effectiveImgHeight}|'
            '${shape.imgOffsetXInches}|${shape.imgOffsetYInches}|'
            '${shape.width}|${shape.height}|$cropped';
        var bakedPart = cache[key];
        if (bakedPart == null) {
          final png = bakeVisioImageAdjustmentsPng(
            image: source,
            transparency: shape.imageTransparency,
            blur: shape.imageBlur,
            brightness: shape.imageBrightness,
            contrast: shape.imageContrast,
            displayWidthInches:
                cropped ? shape.width.abs() : shape.effectiveImgWidth,
            softEdgesInches: soft,
            frameWidthInches: cropped ? shape.width : 0,
            frameHeightInches: cropped ? shape.height : 0,
            imgOffsetXInches: shape.imgOffsetXInches,
            imgOffsetYInches: shape.imgOffsetYInches,
            imgWidthInches: shape.imgWidthInches,
            imgHeightInches: shape.imgHeightInches,
          );
          if (png != null) {
            bakedPart = allocatePart(shape.id);
            cache[key] = bakedPart;
            registry = registry.withImage(
              VsdxImage(
                partName: bakedPart,
                bytes: png,
                mimeType: 'image/png',
              ),
            );
          }
        }
        if (bakedPart != null) {
          next = shape.copyWith(
            imagePartName: bakedPart,
            foreignType: VsdxImage.foreignTypeFor(
              mimeType: 'image/png',
              partName: bakedPart,
            ),
            foreignCompressionType: VsdxImage.compressionTypeFor(
              mimeType: 'image/png',
              partName: bakedPart,
            ),
            imageTransparency: 0,
            imageBlur: 0,
            imageBrightness: 0.5,
            imageContrast: 0.5,
            line: soft > 1e-6
                ? shape.line.copyWith(softEdgesInches: 0)
                : shape.line,
            imgOffsetXInches: cropped ? 0 : shape.imgOffsetXInches,
            imgOffsetYInches: cropped ? 0 : shape.imgOffsetYInches,
            imgWidthInches: cropped ? shape.width : shape.imgWidthInches,
            imgHeightInches: cropped ? shape.height : shape.imgHeightInches,
          );
          changed = true;
        }
      }
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) {
      next = next.copyWith(children: children);
      changed = true;
    }
    return next;
  }

  if (document.pages.isEmpty && document.images.length == 0) {
    return document;
  }
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) rewrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!changed && !pagesChanged) return document;
  return document.copyWith(
    pages: pagesChanged ? pages : document.pages,
    images: registry,
  );
}

/// `true` when geometry `SoftEdgesSize` must become a feathered PNG for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no
/// SoftEdgesSize, so Draw paints a hard fill or a hard stroke. Picture
/// SoftEdges already feathers PNG alpha; a filled 2-D vector bakes the
/// same SourceAlpha treatment into a locked Foreign sibling, then the
/// source fill is dropped so the plate is the body. An unfilled 2-D
/// stroke bakes the stroke ring the same way and drops the source line.
/// A filled 2-D shape that also paints a solid or dashed stroke bakes both into
/// one padded plate and drops fill and line, so Draw does not keep a
/// hard outline. Gradient / hatch fills with a stroke join that plate.
/// CompoundType 1–4 rails join that plate too. LineGradient strokes
/// with resolved-RGB or theme-only stops join that plate so Draw does
/// not keep a hard opaque outline. Rounding fillets join that plate so
/// Draw does not keep square corners after the fill is dropped.
/// Theme-only FillForegnd / LineColor / gradient stops (canvas
/// `_colourOrTheme` / `_fillColour`) resolve through the document theme,
/// then Office, into that PNG so Draw keeps the feather. A FillGradient
/// whose opaque stops use more than two unique colours uses that same
/// plate at sigma 0: FillPattern 25–40 only interpolates two colours.
/// Multiple NoFill=0 Geometry sections punch even-odd holes in that
/// plate — libvisio emits `svg:fill-rule=evenodd`, so a two-ring frame
/// must not bake as a solid Width×Height rectangle. Leftover source
/// Geometry is marked NoFill so CompoundType 2–4 cannot refill the
/// body with LineColor over that plate.
/// A LineGradient whose opaque stops use more than two unique colours
/// bakes the stroke ring the same way (1-D as a 2-D ribbon plate) so
/// Draw does not drop the middle colour onto a two-stop FillPattern ribbon.
/// InfiniteLine washes clip to the shape box so that plate keeps every stop.
/// Open-path arrows on those washes rasterize into the same plate.
/// Pictures and unrecognised geometry stay native. Closed 2-D
/// arrow cells do not block the bake — libvisio suppresses markers on
/// Z-closed subpaths, same as canvas.
/// Sketch jiggle siblings copy the live LineGradient; those plates are
/// otherwise skipped as bake plates, so an unrepresentable wash would
/// collapse to FillPattern 25–40. They take the same stroke PNG.
/// SoftEdgesSize is not a token either — leftover Geometry is already
/// NoLine — so a Sketch stroke with a live size takes that PNG too
/// (1-D Sketch copies stay Height=0 and still skip, matching canvas).
bool shapeNeedsLibvisioGeometrySoftEdgesBake(VsdxShape shape) =>
    _shapeNeedsLibvisioFillSoftEdgesBake(shape) ||
    _shapeNeedsLibvisioStrokeSoftEdgesBake(shape);

bool _softEdgesGeometryOk(VsdxShape shape, {bool allow1d = false}) {
  if (isLibvisioSketchPlate(shape)) {
    if (!_lineHasLibvisioUnrepresentableGradient(shape.line) &&
        shape.line.softEdgesInches <= 1e-6) {
      return false;
    }
  } else if (_isLibvisioBakePlate(shape)) {
    return false;
  } else {
    if (shape.hasImage) return false;
    if (shape.children.isNotEmpty) return false;
    if (shape.sketchEffect) return false;
  }
  if (shape.hasImage) return false;
  if (shape.children.isNotEmpty) return false;
  if (shape.is1D) {
    if (!allow1d) return false;
    return shape.width.abs() > 1e-9 || shape.height.abs() > 1e-9;
  }
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) {
    // Sketch copies of 1-D connectors keep Height=0 and is1D=false.
    if (isLibvisioSketchPlate(shape) && allow1d) {
      return shape.width.abs() > 1e-9 || shape.height.abs() > 1e-9;
    }
    return false;
  }
  return true;
}

/// Classic FillPattern 25–40 copies Fill*Trans onto the synthesised
/// stops. A modern FillGradient keeps the cell, so the sampler must
/// still multiply it.
double _fillGradientCellTransparency(VsdxFill fill) =>
    fill.hasGradient ? fill.foregroundTransparency : 0;

/// Classic FillPattern 25–40 only store FillForegnd / FillBkgnd. Opaque
/// gradient stops with more than two unique colours cannot survive that
/// collapse, so the SoftEdges PNG is used even at sigma 0. Per-stop
/// alpha is the same missing paint: those two Trans cells become
/// `librevenge:*-opacity`, which Draw does not honour — including a
/// fully transparent stop, which 25–40 would replace with the next
/// opaque colour at the box edge.
bool _gradientHasLibvisioUnrepresentableStops(VsdxGradient? gradient) {
  if (gradient == null || gradient.stops.length < 2) return false;
  final keys = <int>{};
  for (final stop in gradient.stops) {
    if (stop.transparency > 1 - 1e-9) continue;
    final color = stop.color;
    final int key;
    if (color != null) {
      key = color.value & 0x00FFFFFF;
    } else {
      final slot = stop.themeColorIndex;
      if (slot == null) return false;
      key = 0x1000000 | (slot & 0xFFFFFF);
    }
    keys.add(key);
  }
  if (keys.length > 2) return true;
  for (final stop in gradient.stops) {
    if (stop.transparency > 1e-9) return true;
  }
  return false;
}

bool _fillHasLibvisioUnrepresentableGradient(VsdxFill fill) {
  final gradient = fill.paintGradient;
  if (_gradientHasLibvisioUnrepresentableStops(gradient)) return true;
  if (gradient == null || gradient.stops.length < 2) return false;
  // FillPattern 25–40 drop `draw:opacity`; Draw ignores the replacement
  // `librevenge:start-opacity` / `end-opacity` from Fill*Trans.
  return fill.foregroundTransparency > 1e-9 ||
      fill.backgroundTransparency > 1e-9;
}

bool _lineHasLibvisioUnrepresentableGradient(VsdxLine line) {
  if (_gradientHasLibvisioUnrepresentableStops(line.gradient)) return true;
  if (line.gradient == null || line.gradient!.stops.length < 2) return false;
  return line.transparency > 1e-9;
}

bool _shapeNeedsLibvisioFillSoftEdgesBake(VsdxShape shape) {
  if (!_softEdgesGeometryOk(shape)) return false;
  if (shape.line.softEdgesInches <= 1e-6 &&
      !_fillHasLibvisioUnrepresentableGradient(shape.fill)) {
    return false;
  }
  if (!shape.fill.hasFill) return false;
  final paintGradient = shape.fill.paintGradient;
  if (paintGradient != null) {
    if (_gradientBakeStops(
      paintGradient,
      _fillGradientCellTransparency(shape.fill),
    ).isEmpty) {
      return false;
    }
  } else if (libvisioHatchSpec(shape.fill.pattern) != null) {
    // Theme-only FillForegnd used to skip so THEMEVAL hatch cells
    // survived, but Draw then painted a hard hatch (SoftEdgesSize is
    // not a token). RGB hatch already bakes to PNG; freeze theme FG
    // the same way theme FillBkgnd already freezes into that sampler.
    if (shape.fill.foreground == null &&
        shape.fill.themeForegroundIndex == null) {
      return false;
    }
  } else {
    if (shape.fill.pattern != 1) return false;
    if (shape.fill.foreground == null &&
        shape.fill.themeForegroundIndex == null) {
      return false;
    }
  }
  return _softEdgesSilhouetteKind(shape) != null;
}

bool _shapeHasSoftEdgesDashes(VsdxShape shape) {
  final dashes = effectiveDashPatternForLine(shape.line);
  return dashes != null && dashes.isNotEmpty;
}

bool _shapeHasBakeableSoftEdgesStroke(VsdxShape shape) {
  if (!shape.line.hasLine) return false;
  final dashed = _shapeHasSoftEdgesDashes(shape);
  if (shape.line.pattern != 1 && !dashed) return false;
  if (shape.line.hasGradient && _softEdgesLineColorAt(shape) == null) {
    return false;
  }
  if (_openArrowheadsBlockStrokeBake(shape) &&
      !_lineHasLibvisioUnrepresentableGradient(shape.line)) {
    return false;
  }
  if (shape.line.compoundType != 0) {
    return _softEdgesCompoundRibbonPolygons(shape).isNotEmpty;
  }
  if (dashed) {
    return _softEdgesDashRibbonPolygons(shape).isNotEmpty;
  }
  if (_softEdgesStrokeSilhouetteKind(shape) != null) return true;
  if (_lineHasLibvisioUnrepresentableGradient(shape.line) ||
      isLibvisioSketchPlate(shape)) {
    return _solidStrokeRibbonPolygons(shape).isNotEmpty;
  }
  return false;
}

bool _shapeNeedsLibvisioStrokeSoftEdgesBake(VsdxShape shape) {
  final unrepresentable = _lineHasLibvisioUnrepresentableGradient(shape.line);
  if (!_softEdgesGeometryOk(shape, allow1d: unrepresentable)) return false;
  if (_shapeNeedsLibvisioFillSoftEdgesBake(shape)) return false;
  if (shape.line.softEdgesInches <= 1e-6 && !unrepresentable) return false;
  return _shapeHasBakeableSoftEdgesStroke(shape);
}

bool _shapeNeedsLibvisioFillStrokeSoftEdgesBake(VsdxShape shape) =>
    _shapeNeedsLibvisioFillSoftEdgesBake(shape) &&
    _shapeHasBakeableSoftEdgesStroke(shape) &&
    (shape.line.softEdgesInches > 1e-6 ||
        _lineHasLibvisioUnrepresentableGradient(shape.line));

List<VsdxGeometry> _softEdgesFillGeometries(VsdxShape shape) {
  return <VsdxGeometry>[
    for (final candidate in shape.geometries)
      if (!candidate.noShow && !candidate.noFill) candidate,
  ];
}

/// Every fillable Geometry as a closed ring. libvisio concatenates those
/// into one even-odd path (`svg:fill-rule=evenodd`); a PNG plate must
/// punch the same holes instead of filling only the first section.
List<List<Offset2D>>? _softEdgesFillPolygonsInches(VsdxShape shape) {
  final out = <List<Offset2D>>[];
  for (final geom in _softEdgesFillGeometries(shape)) {
    final inches = _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    out.add(inches);
  }
  return out.isEmpty ? null : out;
}

List<List<({double x, double y})>> _softEdgesRingsToPx(
  List<List<Offset2D>> rings, {
  required double w,
  required double h,
  required int widthPx,
  required int heightPx,
}) {
  return <List<({double x, double y})>>[
    for (final ring in rings)
      <({double x, double y})>[
        for (final p in ring)
          (
            x: p.x / w * (widthPx - 1),
            y: (1 - p.y / h) * (heightPx - 1),
          ),
      ],
  ];
}

SoftEdgesSilhouetteKind? _softEdgesSilhouetteKind(VsdxShape shape) {
  final geoms = _softEdgesFillGeometries(shape);
  if (geoms.isEmpty) return null;
  if (geoms.length == 1 &&
      geoms.first.commands.length == 1 &&
      geoms.first.commands.first is EllipseCmd) {
    return SoftEdgesSilhouetteKind.ellipse;
  }
  final rings = _softEdgesFillPolygonsInches(shape);
  if (rings == null || rings.isEmpty) return null;
  // A second fillable section is a hole (or island). The outer ring is
  // often the Width×Height box — that must not collapse to a rectangle.
  if (geoms.length > 1) return SoftEdgesSilhouetteKind.polygon;
  final points = rings.first;
  if (shape.line.roundingInches > 1e-12) {
    return SoftEdgesSilhouetteKind.polygon;
  }
  if (_softEdgesIsShapeBox(points, shape.width, shape.height)) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  return SoftEdgesSilhouetteKind.polygon;
}

SoftEdgesSilhouetteKind? _softEdgesStrokeSilhouetteKind(VsdxShape shape) {
  VsdxGeometry? geom;
  for (final candidate in shape.geometries) {
    if (candidate.noShow || candidate.noLine) continue;
    geom = candidate;
    break;
  }
  if (geom == null) return null;
  if (geom.commands.length == 1 && geom.commands.first is EllipseCmd) {
    return SoftEdgesSilhouetteKind.ellipse;
  }
  final points = _softEdgesPolygonInches(shape, geom);
  if (points == null || points.length < 3) return null;
  if (shape.line.roundingInches > 1e-12) {
    return SoftEdgesSilhouetteKind.polygon;
  }
  if (_softEdgesIsShapeBox(points, shape.width, shape.height)) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  return SoftEdgesSilhouetteKind.polygon;
}

VsdxGeometry? _softEdgesStrokeGeometry(VsdxShape shape) {
  for (final candidate in shape.geometries) {
    if (candidate.noShow || candidate.noLine) continue;
    return candidate;
  }
  return null;
}

VsdxGeometry? _anyVisibleGeometry(VsdxShape shape) {
  for (final candidate in shape.geometries) {
    if (candidate.noShow) continue;
    return candidate;
  }
  return null;
}

/// Image-frame silhouette canvas uses for Foreign pictures (NoFill/NoLine).
SoftEdgesSilhouetteKind? _foreignFrameSilhouetteKind(VsdxShape shape) {
  if (!shape.hasImage || shape.is1D) return null;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return null;
  final geom = _anyVisibleGeometry(shape);
  if (geom == null) return SoftEdgesSilhouetteKind.rectangle;
  if (geom.commands.length == 1 && geom.commands.first is EllipseCmd) {
    return SoftEdgesSilhouetteKind.ellipse;
  }
  final points = _softEdgesPolygonInches(shape, geom);
  if (points == null || points.length < 3) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  if (shape.line.roundingInches > 1e-12) {
    return SoftEdgesSilhouetteKind.polygon;
  }
  if (_softEdgesIsShapeBox(points, shape.width, shape.height)) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  return SoftEdgesSilhouetteKind.polygon;
}

bool _geometryHasNonLinearSoftEdgesCommands(VsdxGeometry geom) {
  for (final cmd in geom.commands) {
    switch (cmd) {
      case MoveTo() || LineTo() || RelMoveTo() || RelLineTo():
        break;
      default:
        return true;
    }
  }
  return false;
}

List<Offset2D>? _sampledSoftEdgesPolygonInches(
  VsdxShape shape,
  VsdxGeometry geom,
) {
  final w = shape.width.abs();
  final h = shape.height.abs();
  var sampled = ShapePerimeter.sampledGeometryVertices(
    geom,
    width: w,
    height: h,
  );
  if (sampled == null || sampled.isEmpty) return sampled;
  if (_geometryHasInfiniteLine(geom) && sampled.length >= 2) {
    sampled = clipInfiniteLineToPage(
          sampled.first,
          sampled.last,
          pageWidth: math.max(w, 1e-6),
          pageHeight: math.max(h, 1e-6),
        ) ??
        sampled;
  }
  if (sampled.length >= 2) {
    final a = sampled.first;
    final b = sampled.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      sampled = sampled.sublist(0, sampled.length - 1);
    }
  }
  return sampled;
}

List<Offset2D>? _softEdgesPolygonInches(VsdxShape shape, VsdxGeometry geom) {
  if (_geometryHasNonLinearSoftEdgesCommands(geom)) {
    return _sampledSoftEdgesPolygonInches(shape, geom);
  }
  final w = shape.width.abs();
  final h = shape.height.abs();
  final points = <Offset2D>[];
  for (final cmd in geom.commands) {
    switch (cmd) {
      case MoveTo(:final x, :final y):
        if (points.isNotEmpty) return null;
        points.add(Offset2D(x, y));
      case LineTo(:final x, :final y):
        points.add(Offset2D(x, y));
      case RelMoveTo(:final fx, :final fy):
        if (points.isNotEmpty) return null;
        points.add(Offset2D(fx * w, fy * h));
      case RelLineTo(:final fx, :final fy):
        points.add(Offset2D(fx * w, fy * h));
      default:
        return _sampledSoftEdgesPolygonInches(shape, geom);
    }
  }
  if (points.length >= 2) {
    final a = points.first;
    final b = points.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      points.removeLast();
    }
  }
  if (points.length < 3) return points;
  final radius = shape.line.roundingInches;
  if (radius <= 1e-12) return points;
  return filletPolyline(
    points,
    radius,
    closed: polylineLooksClosed(points, noFill: geom.noFill),
  );
}

/// True when [points] are the four corners of the Width×Height box.
///
/// A bbox match is not enough: a pie chord, a diamond, or a rounded-rect
/// octagon can span 0..W × 0..H and would otherwise bake as a rectangle.
bool _softEdgesIsShapeBox(List<Offset2D> points, double w, double h) {
  if (points.length < 4) return false;
  const eps = 1e-6;
  bool near(double a, double b) => (a - b).abs() <= eps;
  final boxW = w.abs();
  final boxH = h.abs();
  final seen = <int>{};
  for (final p in points) {
    final onLeft = near(p.x, 0);
    final onRight = near(p.x, boxW);
    final onBottom = near(p.y, 0);
    final onTop = near(p.y, boxH);
    if (!onLeft && !onRight && !onBottom && !onTop) return false;
    if ((onLeft || onRight) && (onBottom || onTop)) {
      var id = 0;
      if (onRight) id |= 1;
      if (onTop) id |= 2;
      seen.add(id);
    }
  }
  return seen.length == 4;
}

Uint8List? _softEdgesPngForLibvisioWrite(VsdxShape shape, VsdxTheme theme) {
  final kind = _softEdgesSilhouetteKind(shape);
  if (kind == null) return null;
  final paintGradient = shape.fill.paintGradient;
  final colorAt = _softEdgesFillColorAt(shape, theme);
  if (paintGradient != null && colorAt == null) return null;
  final color = _fillRgbForLibvisioWrite(
    shape.fill,
    theme,
    fillMatrix: shape.quickStyleFillMatrix,
  );
  final trans = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var widthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var heightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(widthPx, heightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    widthPx = math.max(8, (widthPx * scale).round());
    heightPx = math.max(8, (heightPx * scale).round());
  }
  final polygon = <({double x, double y})>[];
  var evenOddPolygons = const <List<({double x, double y})>>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    final rings = _softEdgesFillPolygonsInches(shape);
    if (rings == null) return null;
    evenOddPolygons = _softEdgesRingsToPx(
      rings,
      w: w,
      h: h,
      widthPx: widthPx,
      heightPx: heightPx,
    );
    polygon.addAll(evenOddPolygons.first);
  }
  return bakeSilhouetteSoftEdgesPng(
    widthPx: widthPx,
    heightPx: heightPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: colorAt != null ? 255 : alpha,
    softSigmaPx: shape.line.softEdgesInches / w * widthPx,
    kind: kind,
    polygon: polygon,
    evenOddPolygons: evenOddPolygons,
    roundingPx: 0,
    colorAt: colorAt == null
        ? null
        : (xPx, yPx) => colorAt(xPx, yPx, widthPx, heightPx),
  );
}

({int r, int g, int b, int a}) Function(
        double xPx, double yPx, int widthPx, int heightPx)?
    _softEdgesFillColorAt(VsdxShape shape, VsdxTheme theme) {
  final w = shape.width.abs();
  final h = shape.height.abs();
  final paintGradient = shape.fill.paintGradient;
  if (paintGradient != null) {
    return _softEdgesGradientSampler(
      paintGradient,
      _fillGradientCellTransparency(shape.fill),
      w,
      h,
      theme,
    );
  }
  final hatch = libvisioHatchSpec(shape.fill.pattern);
  if (hatch == null) return null;
  final fg = _fillCellRgba(
    _fillRgbForLibvisioWrite(
      shape.fill,
      theme,
      fillMatrix: shape.quickStyleFillMatrix,
    ),
    shape.fill.foregroundTransparency,
  );
  final bgColor = _fillBackgroundRgbForLibvisioWrite(shape.fill, theme);
  final bg = bgColor == null
      ? (r: 0, g: 0, b: 0, a: 0)
      : _fillCellRgba(bgColor, shape.fill.backgroundTransparency);
  return (xPx, yPx, widthPx, heightPx) {
    final ix = widthPx <= 1 ? 0.0 : xPx / (widthPx - 1) * w;
    final iy = heightPx <= 1 ? h : (1 - yPx / (heightPx - 1)) * h;
    return sampleVisioHatchRgba(
      spec: hatch,
      x: ix,
      y: iy,
      foreground: fg,
      background: bg,
    );
  };
}

({int r, int g, int b, int a}) Function(
    double xPx, double yPx, int widthPx, int heightPx)? _softEdgesLineColorAt(
  VsdxShape shape, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final gradient = shape.line.gradient;
  if (gradient == null || gradient.stops.isEmpty) return null;
  return _softEdgesGradientSampler(
    gradient,
    shape.line.transparency,
    shape.width.abs(),
    shape.height.abs(),
    theme,
  );
}

({int r, int g, int b, int a}) Function(
        double xPx, double yPx, int widthPx, int heightPx)?
    _softEdgesGradientSampler(
  VsdxGradient gradient,
  double transparency,
  double w,
  double h, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final stops = _gradientBakeStops(gradient, transparency, theme);
  if (stops.isEmpty) return null;
  final linear = gradient.type == VsdxGradientType.linear;
  final angle = gradient.angleRad;
  final dir = gradient.dir;
  return (xPx, yPx, widthPx, heightPx) {
    final ix = widthPx <= 1 ? 0.0 : xPx / (widthPx - 1) * w;
    final iy = heightPx <= 1 ? h : (1 - yPx / (heightPx - 1)) * h;
    return sampleVisioGradientRgba(
      x: ix,
      y: iy,
      minX: 0,
      minY: 0,
      width: w,
      height: h,
      linear: linear,
      angleRad: angle,
      dir: dir,
      stops: stops,
    );
  };
}

List<({double position, int r, int g, int b, int a})> _gradientBakeStops(
  VsdxGradient gradient,
  double fillTransparency, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final fillAlpha = 1 - fillTransparency.clamp(0.0, 1.0);
  final out = <({double position, int r, int g, int b, int a})>[];
  for (final stop in gradient.stops) {
    final color = _gradientStopRgbForLibvisioWrite(stop, theme);
    if (color == null) return const [];
    final a =
        (color.alpha * (1 - stop.transparency.clamp(0.0, 1.0)) * fillAlpha)
            .round()
            .clamp(0, 255);
    out.add((
      position: stop.position,
      r: color.red,
      g: color.green,
      b: color.blue,
      a: a,
    ));
  }
  if (out.isEmpty || out.every((stop) => stop.a <= 0)) {
    return const [];
  }
  return out;
}

({int r, int g, int b, int a}) _fillCellRgba(
  VsdxColor? color,
  double transparency,
) {
  final c = color ?? const VsdxColor(0x00000000);
  final a =
      (c.alpha * (1 - transparency.clamp(0.0, 1.0))).round().clamp(0, 255);
  return (r: c.red, g: c.green, b: c.blue, a: a);
}

List<Offset2D> _filletSoftEdgesStrokePoints(
  List<Offset2D> points,
  VsdxShape shape, {
  required bool closed,
}) {
  final radius = shape.line.roundingInches;
  if (radius <= 1e-12 || points.length < 3) return points;
  return filletPolyline(points, radius, closed: closed);
}

List<List<Offset2D>> _softEdgesDashRibbonPolygons(VsdxShape shape) {
  final inches = effectiveDashPatternForLine(shape.line);
  if (inches == null || inches.isEmpty) {
    return const <List<Offset2D>>[];
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final half = weight / 2;
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final body = _filletSoftEdgesStrokePoints(points, shape, closed: closed);
    for (final segment in _dashPolyline(body, inches, closed: closed)) {
      if (segment.length < 2) continue;
      final left = offsetPolyline(segment, half, closed: false);
      final right = offsetPolyline(segment, -half, closed: false);
      if (left.length < 2 || right.length < 2) continue;
      out.add(<Offset2D>[...left, ...right.reversed]);
    }
  }
  return out;
}

List<List<Offset2D>> _softEdgesCompoundRibbonPolygons(VsdxShape shape) {
  if (shape.line.compoundType <= 0) {
    return const <List<Offset2D>>[];
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final rails = compoundRails(shape.line.compoundType, weight);
  if (rails.isEmpty) return const <List<Offset2D>>[];
  final dashes = effectiveDashPatternForLine(shape.line);
  final dashed = dashes != null && dashes.isNotEmpty;
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final body = _filletSoftEdgesStrokePoints(points, shape, closed: closed);
    final polylines = dashes != null && dashes.isNotEmpty
        ? _dashPolyline(body, dashes, closed: closed)
        : <List<Offset2D>>[body];
    for (final poly in polylines) {
      if (poly.length < 2) continue;
      // Closed rails become an open loop (repeat the start) so the ribbon
      // is one `[...left, ...right.reversed]` strip `_paintFilledPolygons`
      // can fill. `closed: true` offsets would need even-odd hole pairs.
      final loop = dashed || !closed ? poly : <Offset2D>[...poly, poly.first];
      for (final rail in rails) {
        final centre = offsetPolyline(loop, rail.offset, closed: false);
        if (centre.length < 2) continue;
        final half = rail.width / 2;
        if (half <= 1e-9) continue;
        final left = offsetPolyline(centre, half, closed: false);
        final right = offsetPolyline(centre, -half, closed: false);
        if (left.length < 2 || right.length < 2) continue;
        out.add(<Offset2D>[...left, ...right.reversed]);
      }
    }
  }
  return out;
}

double _softEdgesStrokeExtentInches(VsdxShape shape) {
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  var extent = weight / 2;
  if (shape.line.compoundType <= 0) return extent;
  for (final rail in compoundRails(shape.line.compoundType, weight)) {
    extent = math.max(extent, rail.offset.abs() + rail.width / 2);
  }
  return extent;
}

List<List<Offset2D>> _softEdgesStrokeRibbonPolygons(VsdxShape shape) {
  if (shape.line.compoundType > 0) {
    return _softEdgesCompoundRibbonPolygons(shape);
  }
  return _softEdgesDashRibbonPolygons(shape);
}

({double width, double height, double locPinX, double locPinY})
    _strokeRibbonPlateLocalBox(VsdxShape shape, double padInches) {
  final pad = padInches < 0 ? 0.0 : padInches;
  final aabb = _polygonsAabb(_lineGradientStrokePolygons(shape));
  if (aabb == null) {
    final extent = _softEdgesStrokeExtentInches(shape);
    return (
      width: math.max(shape.width.abs(), 1e-6) + 2 * pad,
      height: math.max(shape.height.abs(), 2 * extent) + 2 * pad,
      locPinX: shape.effectiveLocPinX + pad,
      locPinY: shape.effectiveLocPinY + pad,
    );
  }
  return (
    width: math.max(aabb.maxX - aabb.minX, 1e-6) + 2 * pad,
    height: math.max(aabb.maxY - aabb.minY, 1e-6) + 2 * pad,
    locPinX: shape.effectiveLocPinX - (aabb.minX - pad),
    locPinY: shape.effectiveLocPinY - (aabb.minY - pad),
  );
}

/// Rasterize a LineGradient ribbon Draw cannot hold in FillPattern 25–40.
/// Sketch jiggle plates reuse this path (AABB + stroke rings) so a live
/// SoftEdgesSize can feather that same PNG — leftover Geometry is NoLine.
({Uint8List png, double padInches})? _lineGradientRibbonPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final ribbons = _lineGradientStrokePolygons(shape);
  final aabb = _polygonsAabb(ribbons);
  if (aabb == null) return null;
  final gradient = shape.line.gradient;
  final stops = gradient == null
      ? const <({double position, int r, int g, int b, int a})>[]
      : _gradientBakeStops(gradient, shape.line.transparency, theme);
  if (shape.line.hasGradient && stops.isEmpty) return null;
  final color = _lineRgbForLibvisioWrite(shape.line, theme);
  final trans = shape.line.transparency.clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final originX = aabb.minX;
  final originY = aabb.minY;
  final aabbW = math.max(aabb.maxX - aabb.minX, 1e-6);
  final aabbH = math.max(aabb.maxY - aabb.minY, 1e-6);
  const minPx = 16;
  var innerWidthPx =
      math.max(minPx, (aabbW * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx =
      math.max(minPx, (aabbH * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(minPx, (innerWidthPx * scale).round());
    innerHeightPx = math.max(minPx, (innerHeightPx * scale).round());
  }
  final soft = math.max(shape.line.softEdgesInches, 0.0);
  final padInches =
      2 / kLibvisioSoftEdgesPxPerInch + (soft > 1e-6 ? soft * 3 : 0.0);
  final padPx = math.max(1, (padInches / aabbW * innerWidthPx).ceil());
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final strokeWidthPx = math.max(weight / aabbW * innerWidthPx, 1.0);
  final sigmaPx = soft > 1e-6 ? soft / aabbW * innerWidthPx : 0.0;
  final boxW = math.max(shape.width.abs(), aabbW);
  final boxH = math.max(shape.height.abs(), aabbH);
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      strokeColorAt;
  if (stops.isNotEmpty && gradient != null) {
    final linear = gradient.type == VsdxGradientType.linear;
    strokeColorAt = (innerX, innerY) {
      final ix = innerWidthPx <= 1
          ? originX
          : originX + innerX / (innerWidthPx - 1) * aabbW;
      final iy = innerHeightPx <= 1
          ? originY
          : originY + (1 - innerY / (innerHeightPx - 1)) * aabbH;
      return sampleVisioGradientRgba(
        x: ix,
        y: iy,
        minX: 0,
        minY: 0,
        width: boxW,
        height: boxH,
        linear: linear,
        angleRad: gradient.angleRad,
        dir: gradient.dir,
        stops: stops,
      );
    };
  }
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + (p.x - originX) / aabbW * (innerWidthPx - 1),
        y: padPx + (1 - (p.y - originY) / aabbH) * (innerHeightPx - 1),
      );
  final ribbonPx = <List<({double x, double y})>>[
    for (final ribbon in ribbons)
      if (ribbon.length >= 3)
        <({double x, double y})>[for (final p in ribbon) toPx(p)],
  ];
  if (ribbonPx.isEmpty) return null;
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    ribbons: ribbonPx,
    strokeColorAt: strokeColorAt,
  );
  if (png == null) return null;
  return (png: png, padInches: padInches);
}

({Uint8List png, double padInches})? _softEdgesStrokePngForLibvisioWrite(
  VsdxShape shape, {
  required VsdxTheme theme,
  int? holeRed,
  int? holeGreen,
  int? holeBlue,
  int? holeAlpha,
  bool holeFromFill = false,
}) {
  final ribbons0 = _softEdgesStrokeRibbonPolygons(shape);
  final fillRings = _softEdgesFillPolygonsInches(shape);
  final evenOddFill = fillRings != null && fillRings.length > 1;
  // libvisio concatenates every NoFill=0 Geometry with even-odd. A
  // Width×Height outer box would otherwise bake as a solid rectangle and
  // fill the hole; stroke both rings as ribbons instead.
  final ribbons = ribbons0.isNotEmpty
      ? ribbons0
      : (evenOddFill ? _solidStrokeRibbonPolygons(shape) : ribbons0);
  final kind = evenOddFill
      ? SoftEdgesSilhouetteKind.polygon
      : _softEdgesStrokeSilhouetteKind(shape);
  if (kind == null && ribbons.isEmpty) return null;
  final color = _lineRgbForLibvisioWrite(shape.line, theme);
  final trans = shape.line.transparency.clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final soft = shape.line.softEdgesInches;
  final padInches = _softEdgesStrokeExtentInches(shape) + soft * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final sigmaPx = soft / w * innerWidthPx;
  final strokeWidthPx = weight / w * innerWidthPx;
  final fillColorAt = holeFromFill ? _softEdgesFillColorAt(shape, theme) : null;
  if (holeFromFill && fillColorAt == null) return null;
  final holeColorAt = fillColorAt == null
      ? null
      : (double innerX, double innerY) =>
          fillColorAt(innerX, innerY, innerWidthPx, innerHeightPx);
  final lineColorAt = _softEdgesLineColorAt(shape, theme);
  final strokeColorAt = lineColorAt == null
      ? null
      : (double innerX, double innerY) =>
          lineColorAt(innerX, innerY, innerWidthPx, innerHeightPx);
  var outer = const <({double x, double y})>[];
  var inner = const <({double x, double y})>[];
  var ribbonPx = const <List<({double x, double y})>>[];
  var holePolygons = const <List<({double x, double y})>>[];
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + p.x / w * (innerWidthPx - 1),
        y: padPx + (1 - p.y / h) * (innerHeightPx - 1),
      );
  final needsHole = (holeAlpha != null && holeAlpha > 0) || holeColorAt != null;
  if (needsHole && fillRings != null && fillRings.isNotEmpty) {
    holePolygons = <List<({double x, double y})>>[
      for (final ring in fillRings)
        if (ring.length >= 3)
          <({double x, double y})>[for (final p in ring) toPx(p)],
    ];
    if (holePolygons.isNotEmpty) inner = holePolygons.first;
  }
  if (ribbons.isNotEmpty) {
    ribbonPx = <List<({double x, double y})>>[
      for (final ribbon in ribbons)
        if (ribbon.length >= 3)
          <({double x, double y})>[
            for (final p in ribbon) toPx(p),
          ],
    ];
    if (ribbonPx.isEmpty) return null;
  } else if (kind == SoftEdgesSilhouetteKind.polygon) {
    final geom = _softEdgesStrokeGeometry(shape);
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    final half = weight / 2;
    final left = offsetPolyline(inches, half, closed: true);
    final right = offsetPolyline(inches, -half, closed: true);
    if (left.length < 3 || right.length < 3) return null;
    outer = <({double x, double y})>[for (final p in left) toPx(p)];
    inner = <({double x, double y})>[for (final p in right) toPx(p)];
  }
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    kind: kind ?? SoftEdgesSilhouetteKind.rectangle,
    outer: outer,
    inner: inner,
    ribbons: ribbonPx,
    holePolygons: holePolygons,
    holeRed: holeRed,
    holeGreen: holeGreen,
    holeBlue: holeBlue,
    holeAlpha: holeAlpha,
    holeColorAt: holeColorAt,
    strokeColorAt: strokeColorAt,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

({Uint8List png, double padInches})? _softEdgesFillStrokePngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  if (shape.fill.paintGradient != null ||
      libvisioHatchSpec(shape.fill.pattern) != null) {
    return _softEdgesStrokePngForLibvisioWrite(
      shape,
      theme: theme,
      holeFromFill: true,
    );
  }
  final fillColor = _fillRgbForLibvisioWrite(
    shape.fill,
    theme,
    fillMatrix: shape.quickStyleFillMatrix,
  );
  final fillTrans = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final fillAlpha = (fillColor.alpha * (1 - fillTrans)).round().clamp(0, 255);
  return _softEdgesStrokePngForLibvisioWrite(
    shape,
    theme: theme,
    holeRed: fillColor.red,
    holeGreen: fillColor.green,
    holeBlue: fillColor.blue,
    holeAlpha: fillAlpha,
  );
}

({Uint8List png, double padInches})? _softEdgesBakePayload(
  VsdxShape shape,
  VsdxTheme theme,
) {
  if (_shapeNeedsLibvisioFillStrokeSoftEdgesBake(shape)) {
    return _softEdgesFillStrokePngForLibvisioWrite(shape, theme);
  }
  if (_shapeNeedsLibvisioFillSoftEdgesBake(shape)) {
    final png = _softEdgesPngForLibvisioWrite(shape, theme);
    if (png == null) return null;
    return (png: png, padInches: 0);
  }
  if (shape.is1D ||
      isLibvisioSketchPlate(shape) ||
      _openArrowheadsBlockStrokeBake(shape) ||
      _softEdgesStrokeSilhouetteKind(shape) == null) {
    return _lineGradientRibbonPngForLibvisioWrite(shape, theme);
  }
  return _softEdgesStrokePngForLibvisioWrite(shape, theme: theme);
}

VsdxShape _sourceForLibvisioGeometrySoftEdgesWrite(VsdxShape shape) {
  var fill = shape.fill;
  var line = shape.line.copyWith(softEdgesInches: 0);
  var geometries = shape.geometries;
  if (_shapeNeedsLibvisioFillSoftEdgesBake(shape)) {
    fill = const VsdxFill(pattern: 0);
    // CompoundType 2–4 ribbons would otherwise keep these NoFill=0
    // sections and paint LineColor over the PNG plate.
    geometries = <VsdxGeometry>[
      for (final geometry in geometries)
        geometry.noFill ? geometry : geometry.copyWith(noFill: true),
    ];
  }
  if (_shapeNeedsLibvisioFillStrokeSoftEdgesBake(shape) ||
      _shapeNeedsLibvisioStrokeSoftEdgesBake(shape)) {
    line = line.copyWith(pattern: 0, compoundType: 0, gradient: null);
    if (_openArrowheadsBlockStrokeBake(shape)) {
      line = line.copyWith(beginArrow: 0, endArrow: 0);
    }
  }
  return shape.copyWith(fill: fill, line: line, geometries: geometries);
}

VsdxShape _softEdgesPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  double padInches = 0,
  bool useStrokeRibbonAabb = false,
}) {
  final pad = padInches < 0 ? 0.0 : padInches;
  final box = useStrokeRibbonAabb
      ? _strokeRibbonPlateLocalBox(source, pad)
      : (
          width: source.width.abs() + pad * 2,
          height: source.height.abs() + pad * 2,
          locPinX: pad > 1e-12
              ? source.effectiveLocPinX + pad
              : source.locPinXInches,
          locPinY: pad > 1e-12
              ? source.effectiveLocPinY + pad
              : source.locPinYInches,
        );
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX,
    pinY: source.pinY,
    width: box.width,
    height: box.height,
    imagePartName: imagePartName,
    name: '$kLibvisioSoftEdgesShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: box.locPinX,
    locPinYInches: box.locPinY,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

void _collectSoftEdgesPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioSoftEdgesSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectSoftEdgesPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioGeometrySoftEdgesBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioSoftEdgesPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioGeometrySoftEdgesBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

typedef _SoftEdgesImageSink = void Function(VsdxImage image);

List<VsdxShape> _bakeGeometrySoftEdgesTree(
  List<VsdxShape> shapes, {
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
  required String Function(int shapeId) allocatePart,
  required _SoftEdgesImageSink addImage,
}) {
  final out = <VsdxShape>[];
  final delayedSoft = <VsdxShape>[];
  final delayedSketch = <VsdxShape>[];
  var changed = false;
  void flushSketchGroup() {
    if (delayedSoft.isEmpty && delayedSketch.isEmpty) return;
    out.addAll(delayedSoft);
    out.addAll(delayedSketch);
    delayedSoft.clear();
    delayedSketch.clear();
  }

  for (final shape in shapes) {
    if (isLibvisioSoftEdgesPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeGeometrySoftEdgesTree(
        shape.children,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
        allocatePart: allocatePart,
        addImage: addImage,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    VsdxShape? plate;
    var leftover = next;
    if (shapeNeedsLibvisioGeometrySoftEdgesBake(next)) {
      final payload = _softEdgesBakePayload(next, theme);
      if (payload != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: payload.png,
            mimeType: 'image/png',
          ),
        );
        plate = _softEdgesPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          imagePartName: part,
          padInches: payload.padInches,
          useStrokeRibbonAabb: next.is1D ||
              isLibvisioSketchPlate(next) ||
              _openArrowheadsBlockStrokeBake(next) ||
              (_lineHasLibvisioUnrepresentableGradient(next.line) &&
                  next.line.softEdgesInches <= 1e-6 &&
                  _softEdgesStrokeSilhouetteKind(next) == null),
        );
        leftover = _sourceForLibvisioGeometrySoftEdgesWrite(next);
        changed = true;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            plate = candidate;
            changed = true;
            break;
          }
        }
      }
    }
    if (isLibvisioSketchPlate(next)) {
      if (plate != null) delayedSoft.add(plate);
      delayedSketch.add(leftover);
      if (!identical(leftover, shape)) changed = true;
      continue;
    }
    flushSketchGroup();
    if (plate != null) out.add(plate);
    out.add(leftover);
    if (!identical(leftover, shape)) changed = true;
  }
  flushSketchGroup();
  return changed ? out : shapes;
}

/// Insert (or keep) the feathered PNG siblings Draw uses for geometry SoftEdges.
/// Sketch jiggle copies SoftEdgesSize onto those plates; Foreign PNGs
/// composite onto opaque white, so a save hangs every Sketch halo under
/// both jiggle leftovers.
VsdxDocument bakeGeometrySoftEdgesForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_soft_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_soft_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioGeometrySoftEdgesBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectSoftEdgesPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeGeometrySoftEdgesTree(
      page.shapes,
      theme: document.theme,
      plateIds: plateIds,
      nextId: () => nextId++,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Canvas fallback when ShadowForegnd is unset (`_drawShadow`).
const _kLibvisioShadowFallback = VsdxColor(0x99000000);

/// `true` when ShadowBlur — or a hard shadow whose body will become a
/// Foreign PNG — must become a silhouette sibling for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has
/// ShdwPattern / ShdwOffset* / ShdwForegnd but no ShadowBlur, so Draw
/// paints a hard `draw:shadow` on vector fill. A filled 2-D vector
/// with blur bakes the same Gaussian silhouette canvas and SVG already
/// paint into a locked Foreign sibling, then ShdwPattern and ShadowBlur
/// go to 0 so Draw does not add a second copy. Theme-only colour
/// resolves through the document theme then Office into that PNG —
/// Draw never sees THEMEVAL() on ShadowBlur. A Foreign picture bakes
/// the same filled image-frame silhouette canvas `_drawShadow` uses,
/// hard or blurred: `_flushCurrentForeignData` emits an empty graphic
/// style, so `draw:shadow` never lands on the bitmap. A FillGradient
/// whose opaque stops use more than two unique colours (or any other
/// fill that already bakes a SoftEdges PNG) also bakes that silhouette
/// at sigma 0 for the same empty-style reason. An unfilled LineGradient
/// that already bakes a stroke PNG uses the stroke-ring silhouette —
/// two-colour LineGradient stays a filled 25–40 ribbon whose
/// `draw:shadow` Draw still honours. A 1-D three-colour wash bakes the
/// same 2-D ribbon plate (Foreign cannot hang a shadow on a zero-height
/// XForm1D). On an oblique page (`ShdwObliqueAngle` is not a token) the
/// same stroke ring is sheared about LocPin — factory rectangles keep
/// Geometry NoFill=0 even when unfilled, so filling that box would paint
/// a solid parallelogram. Groups and unrecognised geometry stay native.
bool shapeNeedsLibvisioShadowBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.children.isNotEmpty) return false;
  if (!shape.shadow.enabled) return false;
  if (shape.is1D) {
    return _shapeNeedsLibvisioStrokeSoftEdgesBake(shape);
  }
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  if (shape.hasImage) {
    return _foreignFrameSilhouetteKind(shape) != null;
  }
  if (!_shapePaintsFill(shape, shape.geometries)) {
    return _shapeNeedsLibvisioStrokeSoftEdgesBake(shape);
  }
  if (_softEdgesSilhouetteKind(shape) == null) return false;
  if (shape.shadow.blurInches > 1e-6) return true;
  return _shapeNeedsLibvisioFillSoftEdgesBake(shape);
}

/// RGB canvas `_colourOrTheme` would paint. Theme-only ShdwForegnd still
/// has to freeze into a ShadowBlur PNG because `ShadowBlur` is not a token.
VsdxColor _shadowRgbForLibvisioWrite(VsdxShadow shadow, VsdxTheme theme) {
  if (shadow.color != null) return shadow.color!;
  final slot = shadow.themeColorIndex;
  if (slot == null) return _kLibvisioShadowFallback;
  return theme.resolve(slot) ??
      VsdxTheme.office.resolve(slot) ??
      _kLibvisioShadowFallback;
}

({Uint8List png, double padInches})? _shadowPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  // Geometry NoFill=0 is not "paints fill" — factory rectangles keep that
  // flag with FillPattern 0. Using the fill silhouette here would bake a
  // solid box shadow under a LineGradient stroke PNG.
  final SoftEdgesSilhouetteKind? kind;
  if (shape.hasImage) {
    kind = _foreignFrameSilhouetteKind(shape);
  } else if (_shapePaintsFill(shape, shape.geometries)) {
    kind = _softEdgesSilhouetteKind(shape);
  } else {
    kind = null;
  }
  final strokeRings = kind == null
      ? _lineGradientStrokePolygons(shape)
      : const <List<Offset2D>>[];
  if (kind == null && strokeRings.isEmpty) return null;
  final color = _shadowRgbForLibvisioWrite(shape.shadow, theme);
  final trans = shape.shadow.transparency.clamp(0.0, 1.0);
  final fillTrans =
      kind == null ? 0.0 : shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final alpha =
      (color.alpha * (1 - trans) * (1 - fillTrans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.shadow.blurInches / w * innerWidthPx;
  var padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  if (kind == null) {
    final aabb = _polygonsAabb(strokeRings);
    if (aabb != null) {
      final overflow = math.max(
        0.0,
        math.max(
          math.max(-aabb.minX, aabb.maxX - w),
          math.max(-aabb.minY, aabb.maxY - h),
        ),
      );
      padPx = math.max(
        padPx,
        (overflow / w * innerWidthPx).ceil() + 1,
      );
    }
  }
  final polygon = <({double x, double y})>[];
  var evenOddPolygons = const <List<({double x, double y})>>[];
  if (kind == null) {
    evenOddPolygons = _softEdgesRingsToPx(
      strokeRings,
      w: w,
      h: h,
      widthPx: innerWidthPx,
      heightPx: innerHeightPx,
    );
    if (evenOddPolygons.isEmpty) return null;
    polygon.addAll(evenOddPolygons.first);
  } else if (kind == SoftEdgesSilhouetteKind.polygon) {
    final rings = _softEdgesFillPolygonsInches(shape);
    if (rings == null) return null;
    evenOddPolygons = _softEdgesRingsToPx(
      rings,
      w: w,
      h: h,
      widthPx: innerWidthPx,
      heightPx: innerHeightPx,
    );
    polygon.addAll(evenOddPolygons.first);
  }
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: kind ?? SoftEdgesSilhouetteKind.polygon,
    polygon: polygon,
    evenOddPolygons:
        kind == null ? const <List<({double x, double y})>>[] : evenOddPolygons,
    ribbons:
        kind == null ? evenOddPolygons : const <List<({double x, double y})>>[],
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

/// Stroke-ring shadow whose inner box is the ribbon AABB, not Width×Height.
///
/// 1-D connectors are often Height=0; mapping the ring through that box
/// collapses the PNG. SoftEdges already uses this AABB for the wash plate.
({
  Uint8List png,
  double minX,
  double minY,
  double width,
  double height,
  double padInches,
})? _strokeShadowPngForLibvisioWrite(VsdxShape shape, VsdxTheme theme) {
  final rings = _lineGradientStrokePolygons(shape);
  final aabb = _polygonsAabb(rings);
  if (aabb == null) return null;
  final color = _shadowRgbForLibvisioWrite(shape.shadow, theme);
  final trans = shape.shadow.transparency.clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  if (alpha <= 0) return null;
  final originX = aabb.minX;
  final originY = aabb.minY;
  final aabbW = math.max(aabb.maxX - aabb.minX, 1e-6);
  final aabbH = math.max(aabb.maxY - aabb.minY, 1e-6);
  const minPx = 16;
  var innerWidthPx =
      math.max(minPx, (aabbW * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx =
      math.max(minPx, (aabbH * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(minPx, (innerWidthPx * scale).round());
    innerHeightPx = math.max(minPx, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.shadow.blurInches / aabbW * innerWidthPx;
  final padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  ({double x, double y}) toPx(Offset2D p) => (
        x: (p.x - originX) / aabbW * (innerWidthPx - 1),
        y: (1 - (p.y - originY) / aabbH) * (innerHeightPx - 1),
      );
  final ribbons = <List<({double x, double y})>>[
    for (final ring in rings)
      if (ring.length >= 3)
        <({double x, double y})>[for (final p in ring) toPx(p)],
  ];
  if (ribbons.isEmpty) return null;
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: SoftEdgesSilhouetteKind.polygon,
    ribbons: ribbons,
  );
  if (png == null) return null;
  return (
    png: png,
    minX: originX,
    minY: originY,
    width: aabbW,
    height: aabbH,
    padInches: padPx / innerWidthPx * aabbW,
  );
}

/// Gaussian PNG of the scaled, sheared silhouette an oblique page needs.
///
/// The plain path rasterizes the shape's own box, which cannot hold a sheared
/// silhouette. Here the inner box is the transformed ring's bounding box, so
/// the plate has to carry that box back to the source's local frame. Pictures
/// use the same NoFill frame ring canvas `_drawShadow` shears. An unfilled
/// LineGradient must shear the stroke ribbon — factory rectangles keep
/// Geometry NoFill=0 even when FillPattern is 0, and filling that box would
/// paint a solid parallelogram under a hollow wash.
({
  Uint8List png,
  double minX,
  double minY,
  double width,
  double height,
  double padInches,
})? _shearedShadowPngForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
  VsdxTheme theme,
) {
  final paintsFill = _shapePaintsFill(shape, shape.geometries);
  final useStrokeRibbon = !shape.hasImage && !paintsFill;
  final rings = useStrokeRibbon
      ? _shearPolygonsForPageShadow(
          _lineGradientStrokePolygons(shape),
          shape,
          page,
        )
      : _pageShadowRingsForLibvisioWrite(shape, page);
  if (rings.isEmpty) return null;
  Offset2D? first;
  for (final ring in rings) {
    if (ring.length >= 3) {
      first = ring.first;
      break;
    }
  }
  if (first == null) return null;
  var minX = first.x;
  var maxX = minX;
  var minY = first.y;
  var maxY = minY;
  for (final ring in rings) {
    for (final p in ring) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  final w = maxX - minX;
  final h = maxY - minY;
  if (w <= 1e-9 || h <= 1e-9) return null;
  final color = _shadowRgbForLibvisioWrite(shape.shadow, theme);
  final trans = shape.shadow.transparency.clamp(0.0, 1.0);
  final fillTrans =
      paintsFill ? shape.fill.foregroundTransparency.clamp(0.0, 1.0) : 0.0;
  final alpha =
      (color.alpha * (1 - trans) * (1 - fillTrans)).round().clamp(0, 255);
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.shadow.blurInches / w * innerWidthPx;
  final padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  final evenOddPolygons = <List<({double x, double y})>>[
    for (final ring in rings)
      if (ring.length >= 3)
        <({double x, double y})>[
          for (final p in ring)
            (
              x: (p.x - minX) / w * (innerWidthPx - 1),
              y: (1 - (p.y - minY) / h) * (innerHeightPx - 1),
            ),
        ],
  ];
  if (evenOddPolygons.isEmpty) return null;
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: SoftEdgesSilhouetteKind.polygon,
    polygon: evenOddPolygons.first,
    evenOddPolygons: useStrokeRibbon
        ? const <List<({double x, double y})>>[]
        : evenOddPolygons,
    ribbons: useStrokeRibbon
        ? evenOddPolygons
        : const <List<({double x, double y})>>[],
  );
  if (png == null) return null;
  return (
    png: png,
    minX: minX,
    minY: minY,
    width: w,
    height: h,
    padInches: padPx / innerWidthPx * w,
  );
}

/// Plate for a shadow PNG whose inner box is not the shape's own box.
VsdxShape _shadowBoxPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double minX,
  required double minY,
  required double boxWidth,
  required double boxHeight,
  required double padInches,
  required double offsetXInches,
  required double offsetYInches,
}) {
  final pad = padInches < 0 ? 0.0 : padInches;
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX + offsetXInches,
    pinY: source.pinY + offsetYInches,
    width: boxWidth + pad * 2,
    height: boxHeight + pad * 2,
    imagePartName: imagePartName,
    name: '$kLibvisioShadowShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: source.effectiveLocPinX - (minX - pad),
    locPinYInches: source.effectiveLocPinY - (minY - pad),
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioShadowWrite(VsdxShape shape) {
  return shape.copyWith(
    shadow: shape.shadow.copyWith(enabled: false, blurInches: 0),
  );
}

VsdxShape _shadowPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double padInches,
  required double offsetXInches,
  required double offsetYInches,
}) {
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX + offsetXInches,
    pinY: source.pinY + offsetYInches,
    width: source.width.abs() + padInches * 2,
    height: source.height.abs() + padInches * 2,
    imagePartName: imagePartName,
    name: '$kLibvisioShadowShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: source.effectiveLocPinX + padInches,
    locPinYInches: source.effectiveLocPinY + padInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

void _collectShadowPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioShadowSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectShadowPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioShadowBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioShadowPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioShadowBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

typedef _ShadowImageSink = void Function(VsdxImage image);

List<VsdxShape> _bakeShadowTree(
  List<VsdxShape> shapes, {
  required VsdxPage page,
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
  required String Function(int shapeId) allocatePart,
  required _ShadowImageSink addImage,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioShadowPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeShadowTree(
        shape.children,
        page: page,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
        allocatePart: allocatePart,
        addImage: addImage,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioShadowBake(next)) {
      final dx = libvisioEffectiveShadowOffset(
        next.shadow.offsetXInches,
        page.pageSheet.shadowOffsetXInches,
      );
      final dy = libvisioEffectiveShadowOffset(
        next.shadow.offsetYInches,
        page.pageSheet.shadowOffsetYInches,
      );
      // An oblique page also skews the blur, and the sheared silhouette no
      // longer fits the shape's own box.
      final sheared = pageSheetShearsLibvisioShadows(page.pageSheet)
          ? _shearedShadowPngForLibvisioWrite(next, page, theme)
          : null;
      if (sheared != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: sheared.png,
            mimeType: 'image/png',
          ),
        );
        out.add(
          _shadowBoxPlateForLibvisioWrite(
            next,
            id: plateIds[next.id] ?? nextId(),
            imagePartName: part,
            minX: sheared.minX,
            minY: sheared.minY,
            boxWidth: sheared.width,
            boxHeight: sheared.height,
            padInches: sheared.padInches,
            offsetXInches: dx,
            offsetYInches: dy,
          ),
        );
        out.add(_sourceForLibvisioShadowWrite(next));
        changed = true;
        continue;
      }
      if (next.is1D) {
        final stroke = _strokeShadowPngForLibvisioWrite(next, theme);
        if (stroke != null) {
          final part = allocatePart(next.id);
          addImage(
            VsdxImage(
              partName: part,
              bytes: stroke.png,
              mimeType: 'image/png',
            ),
          );
          out.add(
            _shadowBoxPlateForLibvisioWrite(
              next,
              id: plateIds[next.id] ?? nextId(),
              imagePartName: part,
              minX: stroke.minX,
              minY: stroke.minY,
              boxWidth: stroke.width,
              boxHeight: stroke.height,
              padInches: stroke.padInches,
              offsetXInches: dx,
              offsetYInches: dy,
            ),
          );
          out.add(_sourceForLibvisioShadowWrite(next));
          changed = true;
          continue;
        }
        // Width×Height raster divides by Height; 1-D connectors are often 0.
      } else {
        final raster = _shadowPngForLibvisioWrite(next, theme);
        if (raster != null) {
          final part = allocatePart(next.id);
          addImage(
            VsdxImage(
              partName: part,
              bytes: raster.png,
              mimeType: 'image/png',
            ),
          );
          final plate = _shadowPlateForLibvisioWrite(
            next,
            id: plateIds[next.id] ?? nextId(),
            imagePartName: part,
            padInches: raster.padInches,
            offsetXInches: dx,
            offsetYInches: dy,
          );
          out.add(plate);
          out.add(_sourceForLibvisioShadowWrite(next));
          changed = true;
          continue;
        }
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
          changed = true;
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the Gaussian PNG siblings Draw uses for ShadowBlur.
VsdxDocument bakeShadowForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_shdw_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_shdw_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioShadowBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectShadowPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeShadowTree(
      page.shapes,
      page: page,
      theme: document.theme,
      plateIds: plateIds,
      nextId: () => nextId++,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Name prefix of the sheared sibling a page oblique shadow becomes for Draw.
const kLibvisioPageShadowShapeNamePrefix = 'LibvisioPageShadow.';

bool isLibvisioPageShadowPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioPageShadowShapeNamePrefix);

int? libvisioPageShadowSourceId(VsdxShape plate) {
  if (!isLibvisioPageShadowPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioPageShadowShapeNamePrefix.length),
  );
}

/// `true` when the PageSheet skews or scales drop shadows.
///
/// `readPageSheetProperties` only collects `ShdwOffsetX` / `ShdwOffsetY`;
/// `ShdwType`, `ShdwObliqueAngle` and `ShdwScaleFactor` are not even in
/// `tokens.txt`, so Draw always paints a plain offset copy.
bool pageSheetShearsLibvisioShadows(VsdxPageSheet sheet) =>
    sheet.shadowType != 0 ||
    sheet.shadowObliqueAngle.abs() > 1e-9 ||
    (sheet.shadowScaleFactor - 1.0).abs() > 1e-9;

/// `true` when a page oblique shadow must become a sheared sibling for Draw.
///
/// Canvas `_applyPageShadowXform` scales and shears the silhouette about the
/// shape LocPin before offsetting it. Blurred shadows already bake a Gaussian
/// PNG, so this covers the hard-edged ones Draw would otherwise draw
/// unsheared. Theme-only colour resolves through the document theme then
/// Office into the plate FillForegnd — Draw never sees THEMEVAL() on
/// `ShdwType`. 1-D and groups stay native.
bool shapeNeedsLibvisioPageShadowBake(VsdxShape shape, VsdxPage page) {
  if (!pageSheetShearsLibvisioShadows(page.pageSheet)) return false;
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  if (!shape.shadow.enabled) return false;
  // Blur takes the Gaussian PNG path instead.
  if (shape.shadow.blurInches > 1e-6) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  if (!_shapePaintsFill(shape, shape.geometries) && !shape.hasImage) {
    return false;
  }
  return _pageShadowGeometriesForLibvisioWrite(shape, page).isNotEmpty;
}

Offset2D _pageShadowMappedPoint(
  Offset2D p,
  VsdxShape shape,
  VsdxPage page,
) {
  final sheet = page.pageSheet;
  final scale = sheet.shadowScaleFactor;
  final shear = math.tan(sheet.shadowObliqueAngle);
  final cx = shape.effectiveLocPinX;
  final cy = shape.effectiveLocPinY;
  final qy = (p.y - cy) * scale;
  final qx = (p.x - cx) * scale + shear * qy;
  return Offset2D(qx + cx, qy + cy);
}

List<List<Offset2D>> _shearPolygonsForPageShadow(
  List<List<Offset2D>> rings,
  VsdxShape shape,
  VsdxPage page,
) =>
    <List<Offset2D>>[
      for (final ring in rings)
        if (ring.length >= 3)
          <Offset2D>[
            for (final p in ring) _pageShadowMappedPoint(p, shape, page),
          ],
    ];

/// The shape silhouette scaled and sheared about LocPin, matching canvas.
///
/// The page-space shadow offset rides on the plate pin (like the Gaussian PNG
/// plate) so a rotated shape does not rotate its offset.
List<List<Offset2D>> _pageShadowRingsForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow) continue;
    // A Foreign frame is NoFill but still supplies the image silhouette.
    if (geometry.noFill && !shape.hasImage) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 3) continue;
    out.add(<Offset2D>[
      for (final p in points) _pageShadowMappedPoint(p, shape, page),
    ]);
  }
  return out;
}

List<VsdxGeometry> _pageShadowGeometriesForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final out = <VsdxGeometry>[];
  for (final ring in _pageShadowRingsForLibvisioWrite(shape, page)) {
    final commands = _closedCommandsForRing(ring);
    if (commands.length < 3) continue;
    out.add(VsdxGeometry(noFill: false, noLine: true, commands: commands));
  }
  return out;
}

VsdxShape _pageShadowPlateForLibvisioWrite(
  VsdxShape source,
  VsdxPage page, {
  required int id,
  required VsdxTheme theme,
}) {
  final sheet = page.pageSheet;
  final dx = libvisioEffectiveShadowOffset(
    source.shadow.offsetXInches,
    sheet.shadowOffsetXInches,
  );
  final dy = libvisioEffectiveShadowOffset(
    source.shadow.offsetYInches,
    sheet.shadowOffsetYInches,
  );
  final colour = _shadowRgbForLibvisioWrite(source.shadow, theme);
  // Canvas opacity is colourAlpha × (1 - ShdwForegndTrans) × (1 - FillTrans);
  // FillForegndTrans is a token, so carry all three there.
  final opacity = colour.alpha /
      255 *
      (1 - source.shadow.transparency.clamp(0.0, 1.0)) *
      (1 - source.fill.foregroundTransparency.clamp(0.0, 1.0));
  return VsdxShape(
    id: id,
    name: '$kLibvisioPageShadowShapeNamePrefix${source.id}',
    pinX: source.pinX + dx,
    pinY: source.pinY + dy,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _pageShadowGeometriesForLibvisioWrite(source, page),
    fill: VsdxFill(
      foreground: VsdxColor.argb(255, colour.red, colour.green, colour.blue),
      pattern: 1,
      foregroundTransparency: (1 - opacity).clamp(0.0, 1.0),
    ),
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

/// `ShdwPattern` 0 so Draw does not add its own unsheared copy.
VsdxShape _sourceForLibvisioPageShadowWrite(VsdxShape shape) =>
    shape.copyWith(shadow: shape.shadow.copyWith(enabled: false));

void _collectPageShadowPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioPageShadowSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectPageShadowPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioPageShadowBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioPageShadowPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioPageShadowBake(shape, page)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakePageShadowTree(
  List<VsdxShape> shapes, {
  required VsdxPage page,
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioPageShadowPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakePageShadowTree(
        shape.children,
        page: page,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioPageShadowBake(next, page)) {
      final plate = _pageShadowPlateForLibvisioWrite(
        next,
        page,
        id: plateIds[next.id] ?? nextId(),
        theme: theme,
      );
      if (plate.geometries.isNotEmpty) {
        out.add(plate);
        out.add(_sourceForLibvisioPageShadowWrite(next));
        changed = true;
        continue;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
          changed = true;
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the sheared siblings Draw uses for a page oblique shadow.
VsdxDocument bakePageShadowForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioPageShadowBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectPageShadowPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakePageShadowTree(
      page.shapes,
      page: page,
      theme: document.theme,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Cells and Geometry the writer should emit so Draw paints this shape.
class LibvisioShapeWrite {
  const LibvisioShapeWrite({
    required this.geometries,
    required this.line,
    required this.fill,
    required this.geometryRewritten,
  });

  final List<VsdxGeometry> geometries;
  final VsdxLine line;
  final VsdxFill fill;
  final bool geometryRewritten;
}

/// Map [shape] onto the Fill / Line / Geometry libvisio will actually draw.
LibvisioShapeWrite libvisioShapeWrite(
  VsdxShape shape, {
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (shape.libvisioCollapsedHidden || shape.libvisioCoveredHidden) {
    return LibvisioShapeWrite(
      geometries: <VsdxGeometry>[
        for (final geometry in shape.geometries)
          geometry.noShow ? geometry : geometry.copyWith(noShow: true),
      ],
      line: shape.line.copyWith(pattern: 0),
      fill: shape.fill.copyWith(pattern: 0, gradient: null),
      geometryRewritten: true,
    );
  }
  var geometries = shape.geometries;
  var line = shape.line;
  var fill = fillForLibvisioWrite(shape.fill);
  var geometryRewritten = false;

  var working = shape;
  List<VsdxGeometry> arrowGeoms = const <VsdxGeometry>[];
  if (shapeNeedsLibvisioArrowedStrokeBake(shape)) {
    arrowGeoms = bakeArrowGeometriesForLibvisio(shape);
    working = shape.copyWith(
      line: shape.line.copyWith(beginArrow: 0, endArrow: 0),
    );
    geometries = working.geometries;
    line = working.line;
    if (arrowGeoms.isNotEmpty) geometryRewritten = true;
  }

  final baked = bakeCompoundTypeForLibvisio(working);
  if (baked != null) {
    geometries = baked.geometries;
    line = baked.line;
    if (baked.fill != null) fill = baked.fill!;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
      fill: fill,
    );
  }

  final dashed = bakeCustomDashForLibvisio(
    working,
    geometries: geometries,
    line: line,
  );
  if (dashed != null) {
    geometries = dashed.geometries;
    line = dashed.line;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
    );
  }

  final flowed = bakeFlowDashForLibvisio(
    working,
    geometries: geometries,
    line: line,
  );
  if (flowed != null) {
    geometries = flowed.geometries;
    line = flowed.line;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
    );
  }

  final patterned = bakeLinePatternDashForLibvisio(
    working,
    geometries: geometries,
    line: line,
  );
  if (patterned != null) {
    geometries = patterned.geometries;
    line = patterned.line;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
    );
  }

  final pattern = linePatternForLibvisioWrite(line);
  if (pattern != line.pattern) {
    line = line.copyWith(pattern: pattern);
  }

  final color = lineColorForLibvisioWrite(line);
  if (color != null && line.color == null && line.themeColorIndex == null) {
    line = line.copyWith(color: color);
  }

  final ribbon = bakeStrokeRibbonForLibvisio(
    shape: working,
    geometries: geometries,
    line: line,
    theme: theme,
  );
  if (ribbon != null) {
    geometries = ribbon.geometries;
    line = ribbon.line;
    fill = ribbon.fill;
    geometryRewritten = true;
  }

  if (arrowGeoms.isNotEmpty) {
    geometries = <VsdxGeometry>[...geometries, ...arrowGeoms];
    if (!fill.hasFill) {
      fill = VsdxFill(
        foreground: _lineRgbForLibvisioWrite(line, theme),
        pattern: 1,
        foregroundTransparency: line.transparency.clamp(0.0, 1.0),
      );
    }
    line = line.copyWith(beginArrow: 0, endArrow: 0);
  }

  final sourceLine = shape.line;
  if (roundingForLibvisioWrite(sourceLine) > 1e-12) {
    line = line.copyWith(roundingInches: 0);
  }
  if ((chamferForLibvisioWrite(sourceLine) ||
          shapeNeedsLibvisioRoundCapMiterFlatten(shape)) &&
      sourceLine.cap == LineCap.round) {
    line = line.copyWith(cap: LineCap.extended);
  }
  if (miterLimitForLibvisioChamfer(sourceLine) != null ||
      shapeNeedsLibvisioMiterSpikeBake(shape)) {
    line = line.copyWith(miterLimit: 4.0);
  }
  if (line.transparency > 1e-9 &&
      !shapeNeedsLibvisioFilledStrokeRibbonBake(shape)) {
    line = line.copyWith(
      color: colourForLibvisioAlpha(
        _lineRgbForLibvisioWrite(line, theme),
        line.transparency,
      ),
      transparency: 0,
      clearThemeColorIndex: true,
    );
  } else if (line.color == null && line.themeColorIndex != null) {
    // Cache RGB in LineColor V= so libvisio's override does not paint
    // palette 0 black. Keep the slot — the writer still emits THEMEVAL().
    line = line.copyWith(color: _lineRgbForLibvisioWrite(line, theme));
  }

  final glow = bakeGlowForLibvisio(
    shape: shape,
    geometries: geometries,
    line: line,
    fill: fill,
    theme: theme,
  );
  if (glow != null) {
    geometries = glow.geometries;
    line = glow.line;
    fill = glow.fill;
    geometryRewritten = true;
  }

  fill = _fillWithoutStaleLibvisioPattern(fill, geometries);
  fill = fillThemeTransForLibvisioWrite(
    fill,
    theme,
    shape.quickStyleFillMatrix,
  );
  fill = fillHatchTransForLibvisioWrite(
    fill,
    theme,
    shape.quickStyleFillMatrix,
  );

  final bezier = <VsdxGeometry>[
    for (final geometry in geometries)
      geometryForLibvisioWrite(
        geometry,
        width: shape.width,
        height: shape.height,
      ),
  ];
  if (bezier.length == geometries.length) {
    for (var i = 0; i < bezier.length; i++) {
      if (!identical(bezier[i], geometries[i])) {
        geometries = bezier;
        geometryRewritten = true;
        break;
      }
    }
  } else {
    geometries = bezier;
    geometryRewritten = true;
  }

  return LibvisioShapeWrite(
    geometries: geometries,
    line: line,
    fill: fill,
    geometryRewritten: geometryRewritten,
  );
}

List<Offset2D>? _strokedVertices(VsdxGeometry geometry, VsdxShape shape) {
  final points = geometry.polylineVertices(
        widthInches: shape.width,
        heightInches: shape.height,
      ) ??
      ShapePerimeter.sampledGeometryVertices(
        geometry,
        width: shape.width,
        height: shape.height,
      );
  if (points == null || points.length < 2) return points;
  if (!_geometryHasInfiniteLine(geometry)) return points;
  final w = math.max(shape.width.abs(), 1e-6);
  final h = math.max(shape.height.abs(), 1e-6);
  return clipInfiniteLineToPage(
        points.first,
        points.last,
        pageWidth: w,
        pageHeight: h,
      ) ??
      points;
}

bool _geometryHasInfiniteLine(VsdxGeometry geometry) {
  for (final command in geometry.commands) {
    if (command is InfiniteLineCmd) return true;
  }
  return false;
}

bool _shapePaintsFill(VsdxShape shape, List<VsdxGeometry> geometries) {
  if (!shape.fill.hasFill) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noFill) return true;
  }
  return false;
}

bool _geometriesPaintFill(VsdxFill fill, List<VsdxGeometry> geometries) {
  if (!fill.hasFill) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noFill) return true;
  }
  return false;
}

/// Drop a leftover FillPattern when libvisio will never collect a path.
///
/// Edraw text labels (「专业知识」, 「70% 隐性」, …) store FillPattern=1 and
/// FillForegnd but omit Geometry. Visio / libvisio then paint text only.
/// A save that keeps FillPattern=1 lets Edraw fill the Width×Height box —
/// a white plate that hides white glyphs on the header wash.
VsdxFill _fillWithoutStaleLibvisioPattern(
  VsdxFill fill,
  List<VsdxGeometry> geometries,
) {
  if (fill.pattern == 0 || fill.hasGradient) return fill;
  if (_geometriesPaintFill(fill, geometries)) return fill;
  return fill.copyWith(pattern: 0);
}

bool _geometriesPaintLine(VsdxLine line, List<VsdxGeometry> geometries) {
  if (!line.hasLine) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noLine) return true;
  }
  return false;
}

/// Canvas `_drawGlow` uses `(1 - trans) * 0.6` fill-opacity; invert for Trans.
double _glowHaloTransparency(VsdxGlow glow) =>
    0.4 + 0.6 * glow.transparency.clamp(0.0, 1.0);

const _kLibvisioGlowFallback = VsdxColor(0xFFFFC107);

/// Glow ribbon fill Draw collects. `FillForegndTrans` *is* a token, so only
/// the RGB has to freeze: `QuickStyleFillColor` would go through the same
/// `getThemeColour` table that stops at 8, so a THEMEVAL() ribbon lost the
/// slot canvas `_drawGlow` paints.
VsdxFill _glowFillForLibvisio(
  VsdxGlow glow, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  return VsdxFill(
    foreground: _glowRgbForLibvisioWrite(glow, theme),
    pattern: 1,
    foregroundTransparency: _glowHaloTransparency(glow),
  );
}

/// LineWeight halo Draw collects when Glow cannot become a Gaussian PNG.
///
/// Theme-only colour has to freeze into RGB here. `Glow*` is not a token,
/// so the slot would have to survive as `QuickStyleLineColor`, but
/// `VSDXTheme::getThemeColour` maps 0–8 onto dk1/lt1/accent1–6/bkgnd and
/// returns nothing above that, and `VSDLineStyle::override` applies the
/// explicit `LineColor` *after* the theme. A THEMEVAL() halo therefore
/// painted opaque black instead of the faded slot canvas `_drawGlow`
/// blends. LineColorTrans is not a token either, so the halo alpha is
/// premultiplied toward white the same way the resolved-RGB path does.
VsdxLine _glowLineForLibvisio(
  VsdxLine line,
  VsdxGlow glow, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final weight = math.max(glow.sizeInches * 2, 0.02);
  return line.copyWith(
    color: colourForLibvisioAlpha(
      _glowRgbForLibvisioWrite(glow, theme),
      _glowHaloTransparency(glow),
    ),
    weightInches: weight,
    pattern: 1,
    transparency: 0,
    cap: LineCap.round,
    clearThemeColorIndex: true,
  );
}

/// `true` when Glow* must become Line / Fill Draw actually collects.
///
/// `tokens.txt` has no GlowSize. Filled 2-D that already paints a stroke
/// keeps that outline — Line is shape-level, so a halo would replace
/// CompoundType / dashes; that case bakes a Gaussian PNG sibling.
/// Unfilled 1-D strokes bake a Gaussian PNG plate. Unfilled 2-D bakes a
/// Gaussian PNG ring. Filled NoLine bakes the same Gaussian PNG sibling.
/// Pictures bake a Gaussian PNG ring around the image frame. Theme-only
/// colour resolves into those PNGs (document theme, then Office) so Draw
/// keeps the blur canvas `_colourOrTheme` already paints. Remaining
/// theme-only NoLine that cannot PNG still becomes a LineWeight halo
/// (`xmlStringToColour` zeros LineColorTrans, so RGB is premultiplied
/// toward white).
bool shapeNeedsLibvisioGlowBake(VsdxShape shape) {
  if (_shapeCanLibvisioGlowPng(shape)) return false;
  if (_shapeCanLibvisioGlowStrokePng(shape)) return false;
  if (_shapeCanLibvisioGlowPicturePng(shape)) return false;
  final glow = shape.glow;
  if (!glow.enabled || glow.sizeInches <= 1e-12) return false;
  if (glow.transparency >= 1 - 1e-9) return false;
  final paintsFill = _shapePaintsFill(shape, shape.geometries);
  if (!paintsFill && !shape.line.hasLine && !shape.hasImage) return false;
  if (!paintsFill && shapeNeedsLibvisioArrowedStrokeBake(shape)) {
    return false;
  }
  if (paintsFill || shape.hasImage) return !shape.line.hasLine;
  return true;
}

/// Glow cells Draw will collect. Size is 0 after a Line / Fill bake.
VsdxGlow glowForLibvisioWrite(VsdxShape shape) {
  if (!shapeNeedsLibvisioGlowBake(shape) &&
      !shapeNeedsLibvisioGlowPlateBake(shape)) {
    return shape.glow;
  }
  return shape.glow.copyWith(enabled: false, sizeInches: 0);
}

({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeGlowForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
  required VsdxFill fill,
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (!shapeNeedsLibvisioGlowBake(shape)) return null;
  final glow = shape.glow;
  final paintsFill = _geometriesPaintFill(fill, geometries);
  final paintsLine = _geometriesPaintLine(line, geometries);
  if (!paintsFill) {
    final out = <VsdxGeometry>[...geometries];
    var added = false;
    for (final geometry in geometries) {
      if (geometry.noShow || geometry.noLine) continue;
      final points = _strokedVertices(geometry, shape);
      if (points == null || points.length < 2) continue;
      final closed = polylineLooksClosed(points, noFill: geometry.noFill);
      final commands = strokeRibbonCommands(
        points,
        halfWidth: math.max(glow.sizeInches, 0.01),
        closed: closed,
      );
      if (commands.length < 3) continue;
      out.add(
        VsdxGeometry(
          noFill: false,
          noLine: true,
          commands: commands,
        ),
      );
      added = true;
    }
    if (added) {
      return (
        geometries: out,
        line: line,
        fill: _glowFillForLibvisio(glow, theme),
      );
    }
    if (!paintsLine) {
      return (
        geometries: geometries,
        line: _glowLineForLibvisio(line, glow, theme),
        fill: fill,
      );
    }
    return null;
  }
  if (!paintsLine) {
    return (
      geometries: geometries,
      line: _glowLineForLibvisio(line, glow, theme),
      fill: fill,
    );
  }
  return null;
}

bool _hasArrowheads(VsdxLine line) =>
    line.beginArrow != 0 || line.endArrow != 0;

/// libvisio / LibreOffice suppress `draw:marker-*` on Z-closed subpaths
/// (`VSD_EPSILON` 1E-6), matching canvas `_paintLineEndings`. Arrow cells
/// on a closed 2-D box therefore must not block a stroke bake.
bool _shapeHasOpenLineEndings(VsdxShape shape) {
  final w = shape.width.abs();
  final h = shape.height.abs();
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine || geometry.commands.isEmpty) {
      continue;
    }
    if (geometrySubpathEndpointTangents(
      geometry,
      widthInches: w,
      heightInches: h,
    ).isNotEmpty) {
      return true;
    }
  }
  return false;
}

bool _openArrowheadsBlockStrokeBake(VsdxShape shape) =>
    _hasArrowheads(shape.line) && _shapeHasOpenLineEndings(shape);

VsdxShape _withoutArrowheads(VsdxShape shape) => shape.copyWith(
      line: shape.line.copyWith(beginArrow: 0, endArrow: 0),
    );

/// Marker width `VSDContentCollector::_lineProperties` actually emits.
///
/// `tokens.txt` has no BeginArrowSize / EndArrowSize. Draw uses
/// `markerScale * (0.1/(width²+1) + 2.54*width) * pageScale` (inches),
/// matching `_linePropertiesMarkerScale` for ids 10–11 / 14–18 / 22.
double libvisioMarkerSizeInches({
  required int marker,
  required double strokeWidthInches,
  double pageScale = 1.0,
}) {
  final markerScale = switch (marker) {
    10 || 11 => 0.7,
    14 || 15 || 16 || 17 || 18 || 22 => 1.2,
    _ => 1.0,
  };
  final width = strokeWidthInches.isFinite ? strokeWidthInches : 0.0;
  final scale = pageScale.isFinite ? pageScale : 1.0;
  return scale * markerScale * (0.1 / (width * width + 1.0) + 2.54 * width);
}

bool _hasVsdImportedArrowSize(VsdxShape shape) => shape.userCells.any(
      (cell) =>
          cell.name == VsdxShape.userVsdBeginArrowSize ||
          cell.name == VsdxShape.userVsdEndArrowSize,
    );

bool _arrowSizeMismatchesLibvisio({
  required int arrowId,
  required double authoredInches,
  required double weightInches,
}) {
  if (arrowId == 0) return false;
  final expected = libvisioMarkerSizeInches(
    marker: arrowId,
    strokeWidthInches: weightInches,
  );
  final authored = authoredInches <= 0 ? 0.125 : authoredInches;
  // Visio bucket 2 is 0.125" for every marker id. Draw then scales ids
  // 10–11 / 14–18 / 22 by 0.7 / 1.2 from LineWeight, so an untouched
  // default arrow already "mismatches" that formula. Baking those would
  // drop native BeginArrow on every save (export of ids 1–45, VDX
  // inherited arrows). Only a non-default bucket is worth a Geometry bake.
  const defaultBucketInches = 0.125;
  if ((authored - defaultBucketInches).abs() <= 0.02) return false;
  final span = math.max(authored, expected);
  if (span < 1e-9) return false;
  return (authored - expected).abs() > math.max(0.02, 0.15 * span);
}

/// Arrowed 1-D that also needs rails / a ribbon, or whose size Draw would
/// take from LineWeight instead of BeginArrowSize: bake markers as Geometry.
///
/// libvisio hangs `draw:marker-*` on every open path, so CompoundType rails
/// would duplicate arrowheads, and a closed LineGradient / LineColorTrans
/// ribbon cannot carry shape-level markers. Dash bakes multiply open
/// subpaths the same way — a flattened `veDashPattern` or Flow Animation
/// route puts one marker on *every* dash — so those bake markers too.
/// `tokens.txt` also has no
/// BeginArrowSize cell — marker width follows line weight — so baking the
/// polygon at [VsdxLine.beginArrowSizeInches] is the size Draw will paint.
bool shapeNeedsLibvisioArrowedStrokeBake(VsdxShape shape) {
  if (!_hasArrowheads(shape.line)) return false;
  if (!_shapeHasOpenLineEndings(shape)) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (_strokeTips(shape) == null) return false;
  if (!_hasVsdImportedArrowSize(shape) &&
      (libvisioMarkerPathIsIncomplete(shape.line.beginArrow) ||
          libvisioMarkerPathIsIncomplete(shape.line.endArrow))) {
    return true;
  }
  if (!_hasVsdImportedArrowSize(shape) &&
      (_arrowSizeMismatchesLibvisio(
            arrowId: shape.line.beginArrow,
            authoredInches: shape.line.beginArrowSizeInches,
            weightInches: shape.line.weightInches,
          ) ||
          _arrowSizeMismatchesLibvisio(
            arrowId: shape.line.endArrow,
            authoredInches: shape.line.endArrowSizeInches,
            weightInches: shape.line.weightInches,
          ))) {
    return true;
  }
  final stripped = _withoutArrowheads(shape);
  if (_customDashCanBake(stripped, stripped.line, stripped.geometries)) {
    return true;
  }
  if (_flowDashCanBake(stripped, stripped.geometries)) return true;
  return shapeNeedsLibvisioCompoundBake(stripped) ||
      shapeNeedsLibvisioStrokeRibbon(stripped);
}

/// `true` when CompoundType would otherwise vanish in Draw.
///
/// 1-D connectors with arrowheads are left alone unless
/// [shapeNeedsLibvisioArrowedStrokeBake] will turn the markers into Geometry
/// first: libvisio hangs a marker on every open path, so splitting a
/// connector into rails would otherwise duplicate the arrow.
bool shapeNeedsLibvisioCompoundBake(VsdxShape shape) {
  if (shape.is1D && _hasArrowheads(shape.line)) return false;
  if (shape.line.compoundType <= 0 || !shape.line.hasLine) return false;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  if (compoundRails(shape.line.compoundType, weight).isEmpty) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Whether an unfilled CompoundType 2–4 can keep thick/thin contrast in Draw.
///
/// LineWeight is shape-level, so stroked rails must share one width (the
/// thinnest, or they blob). Unfilled solid / gradient / transparent strokes
/// can instead become filled ribbons of each rail's own width — FillPattern
/// and FillForegndTrans are tokens. Dashes 2–23 stay stroked so
/// `_lineProperties` still paints them. Filled 2-D keeps stroked rails
/// because the shape's Fill is already the body colour.
bool _useVariableWidthCompoundRibbons(VsdxShape shape) {
  if (shape.line.compoundType < 2) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  final pattern = linePatternForLibvisioWrite(shape.line);
  if (pattern >= 2 &&
      pattern <= 23 &&
      !shape.line.hasGradient &&
      shape.line.transparency <= 1e-9) {
    return false;
  }
  return true;
}

/// Offset each stroked polyline into rails libvisio can stroke (or fill).
///
/// CompoundType 1 (equal double) stays two strokes. Unfilled 2–4 become
/// per-rail ribbons so Draw keeps thick-thin / triple contrast; filled 2-D
/// and dashed unfilled strokes keep parallel strokes at the thinnest rail
/// width so they do not blob into one fat line.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill? fill})?
    bakeCompoundTypeForLibvisio(
  VsdxShape shape,
) {
  if (!shapeNeedsLibvisioCompoundBake(shape)) return null;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final rails = compoundRails(shape.line.compoundType, weight);
  if (rails.isEmpty) return null;
  final useRibbons = _useVariableWidthCompoundRibbons(shape);

  final out = <VsdxGeometry>[];
  var addedRails = false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow) {
      out.add(geometry);
      continue;
    }
    if (geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    // Keep the authored fill body only while Fill still paints. After a
    // multi-stop FillGradient becomes a SoftEdges PNG, FillPattern is 0
    // but Geometry may still say NoFill=0; filling that leftover with
    // LineColor would cover the plate. CompoundType 2–4 ribbons then
    // paint only the rails.
    if (!geometry.noFill && shape.fill.hasFill) {
      out.add(geometry.copyWith(noLine: true));
    }
    for (final rail in rails) {
      final offset = offsetPolyline(points, rail.offset, closed: closed);
      if (offset.length < 2) continue;
      if (useRibbons) {
        final commands = strokeRibbonCommands(
          offset,
          halfWidth: rail.width / 2,
          closed: closed,
          miterLimit: shape.line.miterLimit,
        );
        if (commands.length < 3) continue;
        out.add(
          VsdxGeometry(
            noFill: false,
            noLine: true,
            commands: commands,
          ),
        );
      } else {
        out.add(
          VsdxGeometry(
            noFill: true,
            noLine: false,
            commands: polylineCommands(offset, closed: closed),
          ),
        );
      }
      addedRails = true;
    }
  }
  if (!addedRails) return null;

  if (useRibbons) {
    final fill =
        _fillFromLineStroke(shape.line) ?? _opaqueFillFromLine(shape.line);
    return (
      geometries: out,
      line: shape.line.copyWith(
        compoundType: 0,
        pattern: 0,
        gradient: null,
        transparency: 0,
      ),
      fill: fill,
    );
  }

  var railWeight = rails.first.width;
  for (final rail in rails) {
    if (rail.width < railWeight) railWeight = rail.width;
  }
  return (
    geometries: out,
    line: shape.line.copyWith(
      compoundType: 0,
      weightInches: railWeight,
    ),
    fill: null,
  );
}

/// `true` when a round cap would make Draw round-join an explicit miter elbow.
///
/// `_lineProperties` maps join from LineCap only. Canvas / SVG honour
/// `User.veLineJoin` miter / miter-clip even on a round cap, so a 90°
/// corner is sharp here and a round join in Draw. Flattening LineCap to
/// extended makes Draw miter, matching the bevel-on-round-cap bake.
/// Straight edges have no join and keep the round endpoints. Sketch
/// jiggle copies the live cap / join onto those plates, so the same
/// flatten applies; leftover Geometry is already NoLine.
bool shapeNeedsLibvisioRoundCapMiterFlatten(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  if (!shape.line.hasLine) return false;
  if (shape.line.cap != LineCap.round) return false;
  if (shape.line.join != VsdxLineJoin.miter &&
      shape.line.join != VsdxLineJoin.miterClip) {
    return false;
  }
  if (shape.line.roundingInches > 1e-12) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 3) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    if (polylineHasElbow(points, closed: closed)) return true;
  }
  return false;
}

bool _shapeHasLibvisioMiterSpikeCorners(VsdxShape shape) {
  if (shape.line.cap == LineCap.round &&
      !shapeNeedsLibvisioRoundCapMiterFlatten(shape)) {
    return false;
  }
  if (shape.line.roundingInches > 1e-12) return false;
  if (!_lineUsesMiterJoin(shape.line)) return false;
  if (shape.line.miterLimit <= 4.0 + 1e-6) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 3) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    if (polylineHasDrawClippedMiter(points, closed: closed)) return true;
  }
  return false;
}

/// `true` when a miter spike longer than Draw's default 4 must become a ribbon.
///
/// `_lineProperties` never emits `svg:stroke-miterlimit`; ODF/Draw default
/// to 4. Canvas / SVG honour `User.veMiterLimit` above that, so a sharp
/// elbow (ratio>4) is a long spike here and a bevel in Draw. Unfilled
/// solid polylines expand to a filled ribbon whose outline uses that
/// limit. Filled 2-D keeps FillPattern for the body and bakes a sibling
/// instead ([shapeNeedsLibvisioFilledStrokeRibbonBake]). Dashed strokes keep
/// LinePattern. A round cap with an implicit join stays native; an explicit
/// miter join flattens the cap first so Draw does not round the elbow.
/// Sketch jiggle copies `veMiterLimit` onto those plates — leftover
/// Geometry is already NoLine — so the same ribbon keeps the spike.
bool shapeNeedsLibvisioMiterSpikeBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  if (_openArrowheadsBlockStrokeBake(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.pattern != 1) return false;
  final custom = shape.line.customDashPattern;
  if (custom != null && custom.isNotEmpty) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  return _shapeHasLibvisioMiterSpikeCorners(shape);
}

VsdxFill _opaqueFillFromLine(
  VsdxLine line, [
  VsdxTheme theme = VsdxTheme.empty,
]) =>
    VsdxFill(
      foreground: _lineRgbForLibvisioWrite(line, theme),
      background: _lineRgbForLibvisioWrite(line, theme),
      pattern: 1,
    );

/// `true` when an unfilled LineGradient / LineColorTrans stroke vanishes in Draw.
///
/// `tokens.txt` has no LineGradient or LineColorTrans cell, and
/// `xmlStringToColour` always stores Colour.a = 0, so `VSDContentCollector`
/// paints every VSDX stroke opaque. Arrowheads stay shape-level markers and
/// cannot follow a filled ribbon, so connectors with arrows keep LineColor
/// unless [shapeNeedsLibvisioArrowedStrokeBake] turns the markers into
/// Geometry first. Arrow-less 1-D strokes bake the same ribbon as 2-D:
/// XForm1D / glue cells are untouched, matching CompoundType. Filled
/// shapes already occupy FillPattern, so they keep LineColor (Draw will
/// show an opaque stroke). A `veMiterLimit` above 4 on an unfilled solid
/// polyline uses the same ribbon so Draw does not bevel ratio>4 elbows.
bool shapeNeedsLibvisioStrokeRibbon(VsdxShape shape) {
  if (_openArrowheadsBlockStrokeBake(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (!shape.line.hasGradient &&
      shape.line.transparency <= 1e-9 &&
      !shapeNeedsLibvisioMiterSpikeBake(shape)) {
    return false;
  }
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Back-compat name for the LineGradient half of [shapeNeedsLibvisioStrokeRibbon].
bool shapeNeedsLibvisioLineGradientRibbon(VsdxShape shape) =>
    shape.line.hasGradient && shapeNeedsLibvisioStrokeRibbon(shape);

({Offset2D begin, Offset2D beginFrom, Offset2D end, Offset2D endFrom})?
    _strokeTips(VsdxShape shape) {
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    var beginFrom = points[1];
    var endFrom = points[points.length - 2];
    if ((beginFrom.x - points.first.x).abs() < 1e-12 &&
        (beginFrom.y - points.first.y).abs() < 1e-12 &&
        points.length > 2) {
      beginFrom = points[2];
    }
    if ((endFrom.x - points.last.x).abs() < 1e-12 &&
        (endFrom.y - points.last.y).abs() < 1e-12 &&
        points.length > 2) {
      endFrom = points[points.length - 3];
    }
    return (
      begin: points.first,
      beginFrom: beginFrom,
      end: points.last,
      endFrom: endFrom,
    );
  }
  return null;
}

/// Marker ids whose LibreOffice path is a TODO stub in
/// `VSDContentCollector::_linePropertiesMarkerPath` (copies a sibling).
bool libvisioMarkerPathIsIncomplete(int arrowId) {
  switch (arrowId) {
    case 26:
    case 31:
    case 32:
    case 33:
    case 34:
    case 36:
    case 37:
    case 38:
    case 40:
    case 43:
    case 44:
    case 45:
      return true;
    default:
      return false;
  }
}

/// Local-space arrow bake: tip at the origin, body along −X, unit size.
///
/// Matches `lib/render/arrow_library.dart` so Visio (native markers gone)
/// and Draw (Geometry only) see the same silhouette. Open ids are later
/// expanded to filled ribbons because LineWeight is shape-level.
class _ArrowBakeSpec {
  const _ArrowBakeSpec({
    required this.polylines,
    required this.closed,
    required this.filled,
    this.centered = false,
  });

  final List<List<Offset2D>> polylines;
  final bool closed;
  final bool filled;
  final bool centered;
}

List<Offset2D> _regularPolygon({
  required double cx,
  required double cy,
  required double radius,
  int sides = 16,
}) =>
    [
      for (var i = 0; i < sides; i++)
        Offset2D(
          cx + radius * math.cos(i * 2 * math.pi / sides),
          cy + radius * math.sin(i * 2 * math.pi / sides),
        ),
    ];

_ArrowBakeSpec _arrowBakeSpec(int arrowId) {
  switch (arrowId) {
    case 1:
    case 3:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, -0.4), Offset2D(0, 0), Offset2D(-1, 0.4)],
        ],
        closed: false,
        filled: false,
      );
    case 43:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.5, -0.4), Offset2D(0, 0), Offset2D(-0.5, 0.4)],
          [Offset2D(-1.0, -0.4), Offset2D(-0.5, 0), Offset2D(-1.0, 0.4)],
        ],
        closed: false,
        filled: false,
      );
    case 44:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, -0.4), Offset2D(0, 0), Offset2D(-1, 0.4)],
          [Offset2D(-1.2, -0.5), Offset2D(-1.2, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 45:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.5, -0.4), Offset2D(0, 0), Offset2D(-0.5, 0.4)],
          [Offset2D(-1.0, -0.4), Offset2D(-0.5, 0), Offset2D(-1.0, 0.4)],
          [Offset2D(-1.2, -0.5), Offset2D(-1.2, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 2:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.25), Offset2D(-1, 0.25)],
        ],
        closed: true,
        filled: true,
      );
    case 5:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1, -0.4),
            Offset2D(-0.7, 0),
            Offset2D(-1, 0.4),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 6:
    case 8:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1.1, -0.45),
            Offset2D(-0.85, 0),
            Offset2D(-1.1, 0.45),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 7:
    case 19:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.55, -0.5), Offset2D(0, 0), Offset2D(-0.55, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 9:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, -1.1), Offset2D(0, 1.1)],
          [Offset2D(-0.5, -1.1), Offset2D(-0.5, 1.1)],
        ],
        closed: false,
        filled: false,
        centered: true,
      );
    case 10:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.5)],
        closed: true,
        filled: true,
        centered: true,
      );
    case 11:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(-0.85, -0.4),
            Offset2D(0, -0.4),
            Offset2D(0, 0.4),
            Offset2D(-0.85, 0.4),
          ],
        ],
        closed: true,
        filled: true,
        centered: true,
      );
    case 12:
    case 18:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1.1, -0.45),
            Offset2D(-0.85, 0),
            Offset2D(-1.1, 0.45),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 13:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1.4, -1.4 / 3),
            Offset2D(-1.4, 1.4 / 3),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 14:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-0.85, -0.55), Offset2D(-0.85, 0.55)],
        ],
        closed: true,
        filled: false,
      );
    case 15:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.25), Offset2D(-1, 0.25)],
        ],
        closed: true,
        filled: false,
      );
    case 16:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.4), Offset2D(-1, 0.4)],
        ],
        closed: true,
        filled: false,
      );
    case 17:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1, -0.4),
            Offset2D(-0.7, 0),
            Offset2D(-1, 0.4),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 20:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.4)],
        closed: true,
        filled: false,
        centered: true,
      );
    case 21:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(-0.85, -0.4),
            Offset2D(0, -0.4),
            Offset2D(0, 0.4),
            Offset2D(-0.85, 0.4),
          ],
        ],
        closed: true,
        filled: false,
        centered: true,
      );
    case 22:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-0.5, -0.35),
            Offset2D(-1, 0),
            Offset2D(-0.5, 0.35),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 23:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, 0.5), Offset2D(0, -0.5)],
          [Offset2D(-0.5, -0.5), Offset2D(-0.5, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 24:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.3, -0.5), Offset2D(-0.3, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 25:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.3, -0.5), Offset2D(-0.3, 0.5)],
          [Offset2D(-0.55, -0.5), Offset2D(-0.55, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 26:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.2, -0.5), Offset2D(-0.2, 0.5)],
          [Offset2D(-0.4, -0.5), Offset2D(-0.4, 0.5)],
          [Offset2D(-0.6, -0.5), Offset2D(-0.6, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 27:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(0.85, -0.5)],
          [Offset2D(0, 0), Offset2D(0.85, 0)],
          [Offset2D(0, 0), Offset2D(0.85, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 28:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(0.72, -0.5)],
          [Offset2D(0, 0), Offset2D(0.72, 0)],
          [Offset2D(0, 0), Offset2D(0.72, 0.5)],
          [Offset2D(0.88, -0.5), Offset2D(0.88, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 29:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: 0.4, cy: 0, radius: 0.18),
          const [Offset2D(0.6, -0.05), Offset2D(1.1, -0.5)],
          const [Offset2D(0.6, 0), Offset2D(1.1, 0)],
          const [Offset2D(0.6, 0.05), Offset2D(1.1, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 30:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: 0.6, cy: 0, radius: 0.18),
          const [Offset2D(0.3, -0.5), Offset2D(0.3, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 31:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [Offset2D(-1.0, -0.5), Offset2D(-1.0, 0.5)],
        ],
        closed: true,
        filled: false,
      );
    case 32:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [Offset2D(-0.95, -0.5), Offset2D(-0.95, 0.5)],
          const [Offset2D(-1.2, -0.5), Offset2D(-1.2, 0.5)],
        ],
        closed: true,
        filled: false,
      );
    case 33:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [Offset2D(-0.9, -0.5), Offset2D(-0.9, 0.5)],
          const [Offset2D(-1.15, -0.5), Offset2D(-1.15, 0.5)],
          const [Offset2D(-1.4, -0.5), Offset2D(-1.4, 0.5)],
        ],
        closed: true,
        filled: false,
      );
    case 34:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.35, cy: 0, radius: 0.35),
          const [
            Offset2D(-0.8, 0),
            Offset2D(-1.15, -0.35),
            Offset2D(-1.5, 0),
            Offset2D(-1.15, 0.35),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 41:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.5)],
        closed: true,
        filled: false,
      );
    case 35:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [
            Offset2D(-1.0, -0.5),
            Offset2D(-0.8, -0.5),
            Offset2D(-0.8, 0.5),
            Offset2D(-1.0, 0.5),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 36:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [
            Offset2D(-1.0, -0.5),
            Offset2D(-0.8, -0.5),
            Offset2D(-0.8, 0.5),
            Offset2D(-1.0, 0.5),
          ],
          const [
            Offset2D(-1.25, -0.5),
            Offset2D(-1.05, -0.5),
            Offset2D(-1.05, 0.5),
            Offset2D(-1.25, 0.5),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 37:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [
            Offset2D(-1.0, -0.5),
            Offset2D(-0.8, -0.5),
            Offset2D(-0.8, 0.5),
            Offset2D(-1.0, 0.5),
          ],
          const [
            Offset2D(-1.25, -0.5),
            Offset2D(-1.05, -0.5),
            Offset2D(-1.05, 0.5),
            Offset2D(-1.25, 0.5),
          ],
          const [
            Offset2D(-1.5, -0.5),
            Offset2D(-1.3, -0.5),
            Offset2D(-1.3, 0.5),
            Offset2D(-1.5, 0.5),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 38:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.35, cy: 0, radius: 0.35),
          const [
            Offset2D(-0.8, 0),
            Offset2D(-1.15, -0.35),
            Offset2D(-1.5, 0),
            Offset2D(-1.15, 0.35),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 42:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.5)],
        closed: true,
        filled: true,
      );
    case 39:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-0.6, -0.35), Offset2D(-0.6, 0.35)],
          [Offset2D(-0.6, 0), Offset2D(-1.2, -0.35), Offset2D(-1.2, 0.35)],
        ],
        closed: true,
        filled: true,
      );
    case 40:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-0.6, -0.35), Offset2D(-0.6, 0.35)],
          [Offset2D(-0.6, 0), Offset2D(-1.2, -0.35), Offset2D(-1.2, 0.35)],
        ],
        closed: true,
        filled: false,
      );
    default:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.4), Offset2D(-1, 0.4)],
        ],
        closed: true,
        filled: true,
      );
  }
}

/// Shape-local filled polygons / ribbons for BeginArrow / EndArrow.
List<VsdxGeometry> bakeArrowGeometriesForLibvisio(VsdxShape shape) {
  final tips = _strokeTips(shape);
  if (tips == null) return const <VsdxGeometry>[];
  final out = <VsdxGeometry>[];
  final halfWeight =
      (shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01) / 2;
  void add(int id, double size, Offset2D tip, Offset2D from) {
    if (id == 0) return;
    final dx = tip.x - from.x;
    final dy = tip.y - from.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-12) return;
    final ux = dx / len;
    final uy = dy / len;
    final mw = size <= 0 ? 0.125 : size;
    final spec = _arrowBakeSpec(id);
    var localPolys = spec.polylines;
    if (spec.centered) {
      var minX = double.infinity;
      var maxX = -double.infinity;
      for (final poly in localPolys) {
        for (final p in poly) {
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
        }
      }
      if (minX.isFinite) {
        final shift = (minX + maxX) / 2;
        localPolys = [
          for (final poly in localPolys)
            [for (final p in poly) Offset2D(p.x - shift, p.y)],
        ];
      }
    }
    for (final local in localPolys) {
      final world = <Offset2D>[
        for (final p in local)
          Offset2D(
            tip.x + p.x * mw * ux - p.y * mw * uy,
            tip.y + p.x * mw * uy + p.y * mw * ux,
          ),
      ];
      if (spec.filled) {
        if (world.length < 3) continue;
        out.add(
          VsdxGeometry(
            noFill: false,
            noLine: true,
            commands: polylineCommands(world, closed: spec.closed),
          ),
        );
        continue;
      }
      if (world.length < 2) continue;
      final closed = (spec.closed && world.length >= 3) || world.length >= 8;
      final commands = strokeRibbonCommands(
        world,
        halfWidth: halfWeight,
        closed: closed,
      );
      if (commands.length < 3) continue;
      out.add(
        VsdxGeometry(
          noFill: false,
          noLine: true,
          commands: commands,
        ),
      );
    }
  }

  add(
    shape.line.beginArrow,
    shape.line.beginArrowSizeInches,
    tips.begin,
    tips.beginFrom,
  );
  add(
    shape.line.endArrow,
    shape.line.endArrowSizeInches,
    tips.end,
    tips.endFrom,
  );
  return out;
}

/// Expand an unfilled gradient, transparent, or high-miter stroke into a
/// closed ribbon FillPattern 25–40 / FillForegndTrans can paint. Compound
/// rails, when present, are expanded one by one. Dash gaps must already live
/// in Geometry (custom arrays or LinePattern 2–23); a single ribbon of the
/// whole polyline would be solid. A `veMiterLimit` above Draw's default 4
/// uses that limit on the outline so sharp elbows keep the canvas spike.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeStrokeRibbonForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (!shapeNeedsLibvisioStrokeRibbon(shape)) return null;
  if (!line.hasLine) return null;
  var fill = _fillFromLineStroke(line, theme);
  if (fill == null) {
    if (!shapeNeedsLibvisioMiterSpikeBake(
      shape.copyWith(geometries: geometries, line: line),
    )) {
      return null;
    }
    fill = _opaqueFillFromLine(line, theme);
  }

  final weight = line.weightInches > 1e-9 ? line.weightInches : 0.01;
  final half = weight / 2;
  final out = <VsdxGeometry>[];
  var added = false;
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final commands = strokeRibbonCommands(
      points,
      halfWidth: half,
      closed: closed,
      miterLimit: line.miterLimit,
    );
    if (commands.length < 3) {
      out.add(geometry);
      continue;
    }
    out.add(
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: commands,
      ),
    );
    added = true;
  }
  if (!added) return null;

  return (
    geometries: out,
    line: line.copyWith(pattern: 0, gradient: null, transparency: 0),
    fill: fill,
  );
}

VsdxFill? _fillFromLineStroke(
  VsdxLine line, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final transparency = line.transparency.clamp(0.0, 1.0);
  if (line.hasGradient) {
    final gradient = line.gradient!;
    VsdxColor? firstColor;
    VsdxColor? lastColor;
    var saw = false;
    for (final stop in gradient.stops) {
      final color = _gradientStopRgbForLibvisioWrite(stop, theme);
      if (color == null) continue;
      if (!saw) {
        firstColor = color;
        saw = true;
      }
      lastColor = color;
    }
    if (!saw) {
      firstColor = line.color ??
          _gradientStopRgbForLibvisioWrite(
            VsdxGradientStop(
              position: 0,
              themeColorIndex: line.themeColorIndex,
            ),
            theme,
          ) ??
          const VsdxColor(0xFF000000);
      lastColor = firstColor;
    }
    return VsdxFill(
      foreground: firstColor,
      background: lastColor,
      pattern: 1,
      gradient: gradient,
      foregroundTransparency: transparency,
      backgroundTransparency: transparency,
    );
  }
  if (transparency <= 1e-9) return null;
  // Freeze theme LineColor: writer emits hex whenever foreground is set, and
  // the previous black fallback plus THEMEVAL painted a grey wash. FillForegndTrans
  // is a token, so Draw still composites this RGB over the page / body.
  final color = _lineRgbForLibvisioWrite(line, theme);
  return VsdxFill(
    foreground: color,
    background: color,
    pattern: 1,
    foregroundTransparency: transparency,
    backgroundTransparency: transparency,
  );
}

/// Closed polygon covering a stroked polyline, used as a filled ribbon.
List<VsdxPathCommand> strokeRibbonCommands(
  List<Offset2D> points, {
  required double halfWidth,
  required bool closed,
  double miterLimit = 4,
}) {
  final left = offsetPolyline(
    points,
    halfWidth,
    closed: closed,
    miterLimit: miterLimit,
  );
  final right = offsetPolyline(
    points,
    -halfWidth,
    closed: closed,
    miterLimit: miterLimit,
  );
  if (left.length < 2 || right.length < 2) {
    return const <VsdxPathCommand>[];
  }
  if (closed) {
    return <VsdxPathCommand>[
      ...polylineCommands(left, closed: true),
      ...polylineCommands(List<Offset2D>.of(right.reversed), closed: true),
    ];
  }
  return polylineCommands(
    <Offset2D>[...left, ...right.reversed],
    closed: true,
  );
}

/// `true` when `User.veDashPattern` must become Geometry Draw can stroke.
///
/// `_lineProperties` only dashes ids 2–23. Custom draw.io arrays snap onto
/// that table as a fallback, but a sequence that is not one of those ids
/// (and every `veFixedDash` array, which is CSS-px rather than weight-
/// scaled) has to be MoveTo/LineTo dashes with LinePattern=1. Filled 2-D
/// keeps the original ring as NoLine so FillPattern is untouched.
/// Sketch jiggle copies `veDashPattern` onto those plates — leftover
/// Geometry is already NoLine — so the same flatten keeps the gaps.
bool shapeNeedsLibvisioCustomDashBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  return _customDashCanBake(shape, shape.line, shape.geometries);
}

bool _customDashCanBake(
  VsdxShape shape,
  VsdxLine line,
  List<VsdxGeometry> geometries,
) {
  if (!line.hasLine) return false;
  final custom = line.customDashPattern;
  if (custom == null || custom.isEmpty) return false;
  final inches = effectiveDashPatternForLine(line);
  if (inches == null || inches.isEmpty) return false;
  return _dashBakeHasStrokableGeometry(shape, geometries);
}

bool _dashBakeHasStrokableGeometry(
  VsdxShape shape,
  List<VsdxGeometry> geometries,
) {
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Dash canvas / SVG paint for draw.io Flow Animation, in inches.
///
/// `User.veFlowAnimation*` rows are not tokens, and an animated connector
/// carries no dash cell of its own — canvas `_effectiveStrokeDashes` and the
/// SVG `_flowStrokePaint` both synthesise 8 CSS px of ink and gap. Draw
/// would otherwise stroke the route solid. Connectors that already dash
/// (`LinePattern` or `veDashPattern`) keep that authored pattern. Sketch
/// jiggle copies `veFlowAnimation` onto those plates — leftover Geometry
/// is already NoLine, and copies are `is1D=false` — so the same flatten
/// keeps the 8 CSS-px gaps.
List<double>? flowAnimationDashInchesForLibvisioWrite(VsdxShape shape) {
  if (!_libvisioFlowAnimationOn(shape)) return null;
  if (!shape.line.hasLine) return null;
  final authored = effectiveDashPatternForLine(shape.line);
  if (authored != null && authored.isNotEmpty) return null;
  const dash = 8 * drawioDashUnitInches;
  return const <double>[dash, dash];
}

/// `true` when Flow Animation's synthetic dash must become Geometry.
bool shapeNeedsLibvisioFlowDashBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  return _flowDashCanBake(shape, shape.geometries);
}

/// `true` when `veFlowAnimation` must go to 0 so a reopen does not dash
/// already-flattened segments a second time.
///
/// Flattening either the synthesised 8 CSS-px flow dash or an authored
/// `veDashPattern` turns the route into solid MoveTo/LineTo pieces. The
/// canvas would then synthesise another 8 CSS-px array on top if the User
/// row stayed 1.
bool shapeNeedsLibvisioFlowAnimationClear(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  if (!_libvisioFlowAnimationOn(shape)) return false;
  return shapeNeedsLibvisioFlowDashBake(shape) ||
      shapeNeedsLibvisioCustomDashBake(shape);
}

/// Glueable 1-D, or a Sketch copy of one (`is1D=false`, Height=0).
bool _libvisioFlowAnimationOn(VsdxShape shape) {
  if (!shape.flowAnimation) return false;
  return shape.supportsFlowAnimation || isLibvisioSketchPlate(shape);
}

bool _flowDashCanBake(VsdxShape shape, List<VsdxGeometry> geometries) {
  if (flowAnimationDashInchesForLibvisioWrite(shape) == null) return false;
  return _dashBakeHasStrokableGeometry(shape, geometries);
}

/// Flatten the Flow Animation dash into MoveTo/LineTo subpaths.
({List<VsdxGeometry> geometries, VsdxLine line})? bakeFlowDashForLibvisio(
  VsdxShape shape, {
  List<VsdxGeometry>? geometries,
  VsdxLine? line,
}) {
  final sourceLine = line ?? shape.line;
  final sourceGeoms = geometries ?? shape.geometries;
  if (!_flowDashCanBake(shape, sourceGeoms)) return null;
  final inches = flowAnimationDashInchesForLibvisioWrite(shape);
  if (inches == null) return null;
  final flattened = _flattenDashGeometries(shape, sourceGeoms, inches);
  if (flattened == null) return null;
  return (geometries: flattened, line: sourceLine.copyWith(pattern: 1));
}

/// Drop `User.veDashPattern` / `veFixedDash` once dashes live in Geometry,
/// write `veFlowAnimation=0` once the flow dash does, and drop
/// `User.veMiterLimit` once a tighter clip is baked as chamfers or a
/// longer spike is baked as a ribbon.
List<VsdxUserCell> userCellsForLibvisioWrite(VsdxShape shape) {
  final dropDash = shapeNeedsLibvisioCustomDashBake(shape);
  final zeroFlow = shapeNeedsLibvisioFlowAnimationClear(shape);
  final dropMiter = miterLimitForLibvisioChamfer(shape.line) != null ||
      shapeNeedsLibvisioMiterSpikeBake(shape) ||
      (shapeNeedsLibvisioFilledStrokeRibbonBake(shape) &&
          _shapeHasLibvisioMiterSpikeCorners(shape));
  if (!dropDash && !zeroFlow && !dropMiter) return shape.userCells;
  final kept = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (!(dropDash &&
              (cell.name == VsdxShape.userDashPattern ||
                  cell.name == VsdxShape.userFixedDash)) &&
          !(dropMiter && cell.name == VsdxShape.userMiterLimit) &&
          !(zeroFlow && cell.name == VsdxShape.userFlowAnimation))
        cell,
  ];
  if (!zeroFlow) return kept;
  // Re-opening must not dash the already-dashed segments a second time.
  return <VsdxUserCell>[
    ...kept,
    const VsdxUserCell(name: VsdxShape.userFlowAnimation, value: '0'),
  ];
}

/// Flatten [line]'s custom dash array into MoveTo/LineTo subpaths.
({List<VsdxGeometry> geometries, VsdxLine line})? bakeCustomDashForLibvisio(
  VsdxShape shape, {
  List<VsdxGeometry>? geometries,
  VsdxLine? line,
}) {
  final sourceLine = line ?? shape.line;
  final sourceGeoms = geometries ?? shape.geometries;
  if (!_customDashCanBake(shape, sourceLine, sourceGeoms)) return null;
  final inches = effectiveDashPatternForLine(sourceLine);
  if (inches == null || inches.isEmpty) return null;
  final flattened = _flattenDashGeometries(shape, sourceGeoms, inches);
  if (flattened == null) return null;
  return (
    geometries: flattened,
    line: sourceLine.copyWith(
      pattern: 1,
      customDashPattern: null,
      fixedDash: false,
    ),
  );
}

/// `true` when built-in LinePattern 2–23 must flatten before a stroke ribbon.
///
/// `_lineProperties` dashes those ids, but a FillForegndTrans / classic
/// gradient ribbon is a filled silhouette and cannot. Opaque dashed
/// strokes stay native. Sketch jiggle copies LinePattern onto those
/// plates, so the same flatten keeps the gaps on a later ribbon.
bool shapeNeedsLibvisioLinePatternDashBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape) && !isLibvisioSketchPlate(shape)) {
    return false;
  }
  if (!shapeNeedsLibvisioStrokeRibbon(shape)) return false;
  return _linePatternDashCanBake(shape, shape.line, shape.geometries);
}

bool _linePatternDashCanBake(
  VsdxShape shape,
  VsdxLine line,
  List<VsdxGeometry> geometries,
) {
  if (!line.hasLine) return false;
  final custom = line.customDashPattern;
  if (custom != null && custom.isNotEmpty) return false;
  if (line.pattern < 2 || line.pattern > 23) return false;
  final inches = dashPatternFor(
    line.pattern,
    weightInches: line.weightInches,
  );
  if (inches == null || inches.isEmpty) return false;
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Flatten LinePattern 2–23 into MoveTo/LineTo so a later ribbon keeps gaps.
({List<VsdxGeometry> geometries, VsdxLine line})?
    bakeLinePatternDashForLibvisio(
  VsdxShape shape, {
  List<VsdxGeometry>? geometries,
  VsdxLine? line,
}) {
  final sourceLine = line ?? shape.line;
  final sourceGeoms = geometries ?? shape.geometries;
  final probe = shape.copyWith(line: sourceLine, geometries: sourceGeoms);
  if (!shapeNeedsLibvisioStrokeRibbon(probe)) return null;
  if (!_linePatternDashCanBake(shape, sourceLine, sourceGeoms)) return null;
  final inches = dashPatternFor(
    sourceLine.pattern,
    weightInches: sourceLine.weightInches,
  );
  if (inches == null || inches.isEmpty) return null;
  final flattened = _flattenDashGeometries(shape, sourceGeoms, inches);
  if (flattened == null) return null;
  return (
    geometries: flattened,
    line: sourceLine.copyWith(pattern: 1),
  );
}

List<VsdxGeometry>? _flattenDashGeometries(
  VsdxShape shape,
  List<VsdxGeometry> sourceGeoms,
  List<double> inches,
) {
  final out = <VsdxGeometry>[];
  var added = false;
  for (final geometry in sourceGeoms) {
    if (geometry.noShow || geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final segments = _dashPolyline(points, inches, closed: closed);
    if (segments.isEmpty) {
      out.add(geometry);
      continue;
    }
    final dashGeoms = <VsdxGeometry>[];
    for (final segment in segments) {
      final commands = polylineCommands(segment, closed: false);
      if (commands.length < 2) continue;
      dashGeoms.add(
        VsdxGeometry(
          noFill: true,
          noLine: false,
          commands: commands,
        ),
      );
    }
    if (dashGeoms.isEmpty) {
      out.add(geometry);
      continue;
    }
    if (!geometry.noFill) {
      out.add(geometry.copyWith(noLine: true));
    }
    out.addAll(dashGeoms);
    added = true;
  }
  if (!added) return null;
  return out;
}

/// Resample [points] into dash/gap strokes. Even [pattern] slots are ink.
List<List<Offset2D>> _dashPolyline(
  List<Offset2D> points,
  List<double> pattern, {
  required bool closed,
}) {
  if (points.length < 2) return const <List<Offset2D>>[];
  var dashes = pattern;
  if (dashes.isEmpty) return <List<Offset2D>>[points];
  if (dashes.length.isOdd) {
    dashes = <double>[...dashes, ...dashes];
  }
  final cycle = dashes.fold<double>(0, (sum, value) => sum + value);
  if (cycle <= 1e-12) return <List<Offset2D>>[List<Offset2D>.of(points)];

  final ring = List<Offset2D>.of(points);
  if (closed && ring.length >= 2) {
    final a = ring.first;
    final b = ring.last;
    if ((a.x - b.x).abs() > 1e-9 || (a.y - b.y).abs() > 1e-9) {
      ring.add(a);
    }
  }

  final out = <List<Offset2D>>[];
  var patternIdx = 0;
  var draw = true;
  var remaining = dashes[0];
  List<Offset2D>? current;

  void emit() {
    if (current != null && current!.length >= 2) {
      out.add(current!);
    }
    current = null;
  }

  for (var i = 0; i < ring.length - 1; i++) {
    var ax = ring[i].x;
    var ay = ring[i].y;
    final bx = ring[i + 1].x;
    final by = ring[i + 1].y;
    final dx = bx - ax;
    final dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 1e-12) continue;
    final ux = dx / len;
    final uy = dy / len;
    var pos = 0.0;
    while (pos < len - 1e-12) {
      if (remaining <= 1e-12) {
        if (draw) emit();
        patternIdx = (patternIdx + 1) % dashes.length;
        draw = patternIdx.isEven;
        remaining = dashes[patternIdx];
        continue;
      }
      final take = math.min(remaining, len - pos);
      final nx = ax + ux * take;
      final ny = ay + uy * take;
      if (draw) {
        current ??= <Offset2D>[Offset2D(ax, ay)];
        current!.add(Offset2D(nx, ny));
      }
      ax = nx;
      ay = ny;
      pos += take;
      remaining -= take;
    }
  }
  if (draw) emit();
  return out;
}

/// Built-in `LinePattern` 0–23 that libvisio's `_lineProperties` switch
/// actually dashes. Custom draw.io arrays that [bakeCustomDashForLibvisio]
/// could not flatten still snap onto this table; unknown ids become solid.
int linePatternForLibvisioWrite(VsdxLine line) {
  if (line.pattern == 0) return 0;
  final custom = line.customDashPattern;
  if (custom != null && custom.isNotEmpty) {
    return nearestLibvisioLinePattern(custom);
  }
  if (line.pattern >= 1 && line.pattern <= 23) return line.pattern;
  return 1;
}

/// Fillet / chamfer radius Draw will actually paint.
///
/// Shape-level `Rounding` is not in `readShapeProperties` (only stylesheet
/// `readLine`). Explicit draw.io joins are also dropped: `_lineProperties`
/// maps join from `LineCap`, so a square/flat cap becomes a miter. Bake
/// round / arcs as RelQuadBezTo and bevel as a LineTo chamfer, at half the
/// line weight, without writing a Rounding cell Visio would apply a second
/// time on top of the geometry. An already-authored Rounding cell wins over
/// a bevel chamfer so Visio's round corners stay round.
double roundingForLibvisioWrite(VsdxLine line) {
  var radius = line.roundingInches;
  final joinRadius = (line.weightInches > 1e-9 ? line.weightInches : 0.01) / 2;
  if (line.cap == LineCap.round) {
    // Draw already round-joins a round cap. Bevel still has to be baked
    // (and the cap flattened) or Draw paints a round elbow.
    if (line.join == VsdxLineJoin.bevel && radius <= 1e-12) return joinRadius;
    if (miterLimitForLibvisioChamfer(line) != null && radius <= 1e-12) {
      return joinRadius;
    }
    return radius;
  }
  switch (line.join) {
    case VsdxLineJoin.round:
    case VsdxLineJoin.arcs:
      if (joinRadius > radius) radius = joinRadius;
    case VsdxLineJoin.bevel:
      if (radius <= 1e-12) radius = joinRadius;
    case VsdxLineJoin.miter:
    case VsdxLineJoin.miterClip:
    case null:
      if (miterLimitForLibvisioChamfer(line) != null && radius <= 1e-12) {
        radius = joinRadius;
      }
  }
  return radius;
}

/// `true` when the baked corner must be a LineTo chamfer, not RelQuadBezTo.
///
/// Bevel joins, and miter joins whose `veMiterLimit` is tighter than Draw's
/// default 4, when there is no shape-level Rounding (that cell still means
/// a Visio fillet). Round / arcs keep the quadratic. A round cap is
/// flattened to LineCap.extended on write so Draw does not round the
/// chamfer (`_lineProperties` join comes from LineCap only).
bool chamferForLibvisioWrite(VsdxLine line) =>
    line.roundingInches <= 1e-12 &&
    (line.join == VsdxLineJoin.bevel ||
        miterLimitForLibvisioChamfer(line) != null);

bool _lineUsesMiterJoin(VsdxLine line) {
  if (line.join == VsdxLineJoin.round ||
      line.join == VsdxLineJoin.arcs ||
      line.join == VsdxLineJoin.bevel) {
    return false;
  }
  if (line.cap == LineCap.round && line.join == null) return false;
  final join = line.effectiveJoin;
  return join == VsdxLineJoin.miter || join == VsdxLineJoin.miterClip;
}

/// Tighter-than-Draw miter clip that must become LineTo chamfers.
///
/// `_lineProperties` never emits `svg:stroke-miterlimit`; ODF/Draw default
/// to 4. Limits at or above 4 match that default and stay native. `null`
/// means leave the polyline's corners alone.
double? miterLimitForLibvisioChamfer(VsdxLine line) {
  if (!line.hasLine) return null;
  if (line.roundingInches > 1e-12) return null;
  if (!_lineUsesMiterJoin(line)) return null;
  if (line.miterLimit >= 4.0 - 1e-6) return null;
  return line.miterLimit.clamp(1.0, 4.0);
}

/// Closest of libvisio's dash ids 2–23 for a draw.io / custom array.
int nearestLibvisioLinePattern(List<double> custom) {
  var best = 2;
  var bestScore = double.infinity;
  for (var id = 2; id <= 23; id++) {
    final built = dashPatternFor(id, weightInches: 1);
    if (built == null) continue;
    final score = _dashDistance(custom, built);
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
}

/// First authored stop colour, used when Draw cannot collect LineGradient.
VsdxColor? lineColorForLibvisioWrite(VsdxLine line) {
  if (line.color != null) return line.color;
  if (line.themeColorIndex != null) return null;
  final gradient = line.gradient;
  if (gradient == null) return null;
  for (final stop in gradient.stops) {
    if (stop.color != null) return stop.color;
  }
  return null;
}

List<VsdxPathCommand> polylineCommands(
  List<Offset2D> points, {
  required bool closed,
}) {
  if (points.isEmpty) return const <VsdxPathCommand>[];
  var ring = List<Offset2D>.of(points);
  if (closed && ring.length >= 2) {
    final a = ring.first;
    final b = ring.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      ring = ring.sublist(0, ring.length - 1);
    }
  }
  if (ring.isEmpty) return const <VsdxPathCommand>[];
  final commands = <VsdxPathCommand>[
    MoveTo(ring.first.x, ring.first.y),
    for (var i = 1; i < ring.length; i++) LineTo(ring[i].x, ring[i].y),
  ];
  if (closed) {
    commands.add(LineTo(ring.first.x, ring.first.y));
  }
  return commands;
}

double _dashDistance(List<double> a, List<double> b) {
  if (a.length == b.length) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sum;
  }
  final na = _normalizedDash(a);
  final nb = _normalizedDash(b);
  final n = na.length < nb.length ? na.length : nb.length;
  var sum = (na.length - nb.length).abs() * 4.0;
  for (var i = 0; i < n; i++) {
    final d = na[i] - nb[i];
    sum += d * d;
  }
  return sum;
}

List<double> _normalizedDash(List<double> values) {
  var max = 0.0;
  for (final value in values) {
    if (value > max) max = value;
  }
  if (max < 1e-12) return values;
  return <double>[for (final value in values) value / max];
}

/// Shared Character Highlight of every non-empty run, or `null` if mixed / absent.
VsdxColor? uniformCharacterHighlight(VsdxShape shape) {
  VsdxColor? highlight;
  var sawText = false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    sawText = true;
    final color = run.charStyle.highlight;
    if (color == null) return null;
    if (highlight == null) {
      highlight = color;
    } else if (highlight.value != color.value) {
      return null;
    }
  }
  if (sawText) return highlight;
  final plain = shape.text?.trim() ?? '';
  if (plain.isEmpty || shape.richText.runs.isEmpty) return null;
  return shape.richText.runs.first.charStyle.highlight;
}

/// `true` when Character Highlight must be written as TextBkgnd for Draw.
///
/// `readCharIX` has `case XML_HIGHLIGHT: break;`. `TextBkgnd` is a token
/// `VSDContentCollector` paints as span `fo:background-color`. Skip when the
/// block already has a fill — that cell is the user's text-block colour.
bool shapeNeedsLibvisioTextBkgndBake(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  if (block.backgroundColor != null) return false;
  return uniformCharacterHighlight(shape) != null;
}

/// `true` when TextBkgnd / Highlight cells must be rewritten for Draw.
///
/// `TextBkgndTrans` is in `tokens.txt` but `readShapeProperties` has no
/// case for it, and `xmlStringToColour` stores Colour.a = 0, so a
/// semi-transparent plate becomes opaque in Draw unless the RGB is
/// premultiplied and Trans is written 0.
bool shapeNeedsLibvisioTextBlockBake(VsdxShape shape) {
  if (shapeNeedsLibvisioTextBkgndBake(shape)) return true;
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  return block.backgroundColor != null && block.backgroundTransparency > 1e-9;
}

/// Text block cells the writer should emit so Draw paints Highlight / Trans.
VsdxTextBlock textBlockForLibvisioWrite(VsdxShape shape) {
  var block = shape.richText.textBlock;
  if (shapeNeedsLibvisioTextBkgndBake(shape)) {
    block = block.copyWith(backgroundColor: uniformCharacterHighlight(shape));
  }
  if (block.backgroundColor != null && block.backgroundTransparency > 1e-9) {
    block = block.copyWith(
      backgroundColor: colourForLibvisioAlpha(
        block.backgroundColor!,
        block.backgroundTransparency,
      ),
      backgroundTransparency: 0,
    );
  }
  return block;
}

/// Character Highlight to paint here. `null` when a save already inserted
/// per-run FillForegnd siblings, so canvas / SVG do not stack a second halo.
VsdxColor? characterHighlightForPaint(
  VsdxTextRun run, {
  VsdxShape? shape,
  VsdxPage? page,
}) {
  final highlight = run.charStyle.highlight;
  if (highlight == null) return null;
  if (shape != null &&
      page != null &&
      pageHasLibvisioHighlightPlate(page, shape.id)) {
    return null;
  }
  return highlight;
}

/// TextBkgnd to paint here. `null` when it is only the LibreOffice stand-in
/// for Character Highlight, so canvas / SVG keep the tighter highlight halo.
VsdxColor? textBlockBackgroundForPaint(VsdxShape shape) {
  final background = shape.richText.textBlock.backgroundColor;
  if (background == null) return null;
  final highlight = uniformCharacterHighlight(shape);
  if (highlight != null && highlight.value == background.value) return null;
  return background;
}

/// [VsdxShape.richText] text block with a Highlight-stand-in TextBkgnd cleared.
VsdxTextBlock textBlockForPaint(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (textBlockBackgroundForPaint(shape) != null ||
      block.backgroundColor == null) {
    return block;
  }
  return block.withoutBackgroundColor();
}

/// Fill cells Draw will collect. `FillForegndTrans` / `FillBkgndTrans`
/// *are* tokens, so transparency stays. Theme-only FillForegnd /
/// FillBkgnd still have to freeze into RGB because
/// `VSDXTheme::getThemeColour` only maps 0–8 (dk1/lt1/accent1–6/bkgnd)
/// and `VSDFillStyle::override` applies explicit FillForegnd after the
/// theme — THEMEVAL() plus `QuickStyleFillColor=9` paints faded black,
/// while canvas already multiplies `_colourOrTheme` by
/// (1 − FillForegndTrans). Opaque theme-bound colours keep THEMEVAL()
/// *and* cache the resolved RGB in `V=` so Draw does not paint palette
/// 0 black (`V="0"` is libvisio's explicit FillForegnd after the theme).
VsdxFill fillThemeTransForLibvisioWrite(
  VsdxFill fill, [
  VsdxTheme theme = VsdxTheme.empty,
  int? fillMatrix,
]) {
  final fgTrans = fill.foregroundTransparency > 1e-9;
  final bgTrans = fill.backgroundTransparency > 1e-9;
  if (!fgTrans && !bgTrans) {
    return fillThemeRgbCacheForLibvisioWrite(fill, theme, fillMatrix);
  }

  var foreground = fill.foreground;
  var background = fill.background;
  var clearFg = false;
  var clearBg = false;
  if (fgTrans && foreground == null && fill.themeForegroundIndex != null) {
    foreground = _fillRgbForLibvisioWrite(
      fill,
      theme,
      fillMatrix: fillMatrix,
    );
    clearFg = true;
  }
  if (bgTrans && background == null && fill.themeBackgroundIndex != null) {
    final resolved = _fillBackgroundRgbForLibvisioWrite(fill, theme);
    if (resolved != null) {
      background = resolved;
      clearBg = true;
    }
  }
  if (!clearFg && !clearBg) return fill;
  return fill.copyWith(
    foreground: foreground,
    background: background,
    clearThemeForegroundIndex: clearFg,
    clearThemeBackgroundIndex: clearBg,
  );
}

/// Cache resolved theme RGB on [fill] without dropping QuickStyle slots.
/// Writer still emits `F="THEMEVAL()"`; `V=` becomes the hex Draw paints.
VsdxFill fillThemeRgbCacheForLibvisioWrite(
  VsdxFill fill, [
  VsdxTheme theme = VsdxTheme.empty,
  int? fillMatrix,
]) {
  var foreground = fill.foreground;
  var background = fill.background;
  if (foreground == null && fill.themeForegroundIndex != null) {
    foreground = _fillRgbForLibvisioWrite(
      fill,
      theme,
      fillMatrix: fillMatrix,
    );
  }
  if (background == null && fill.themeBackgroundIndex != null) {
    background = _fillBackgroundRgbForLibvisioWrite(fill, theme);
  }
  if (identical(foreground, fill.foreground) &&
      identical(background, fill.background)) {
    return fill;
  }
  return fill.copyWith(foreground: foreground, background: background);
}

/// Cache theme RGB on every shape so the writer can emit hex `V=` even
/// when [libvisioShapeWrite] is called without a theme (the writer path).
VsdxDocument bakeThemeRgbCacheForLibvisioWrite(VsdxDocument document) {
  final theme = document.theme;
  if (theme.isEmpty) return document;
  VsdxShape bakeShape(VsdxShape shape) {
    var fill = fillThemeTransForLibvisioWrite(
      shape.fill,
      theme,
      shape.quickStyleFillMatrix,
    );
    var line = shape.line;
    if (line.color == null && line.themeColorIndex != null) {
      line = line.copyWith(color: _lineRgbForLibvisioWrite(line, theme));
    }
    return shape.copyWith(
      fill: fill,
      line: line,
      children: shape.children.map(bakeShape).toList(growable: false),
    );
  }

  return document.copyWith(
    pages: [
      for (final page in document.pages)
        page.copyWith(
          shapes: page.shapes.map(bakeShape).toList(growable: false),
        ),
    ],
  );
}

/// `true` when FillPattern 2–24 FillForegndTrans cannot survive Draw's
/// hatch mapping. `_fillAndShadowProperties` emits `draw:fill=hatch`;
/// FillBkgndTrans==1 becomes `hatch-solid=false` with **no**
/// `draw:opacity`, and a solid background becomes one `draw:opacity`
/// from `1 - max(fg,bg)` that fades the whole box.
bool fillNeedsLibvisioHatchTransBake(VsdxFill fill) {
  if (libvisioHatchSpec(fill.pattern) == null) return false;
  return fill.foregroundTransparency > 1e-9;
}

/// Hatch FillForegnd / FillBkgnd Draw will paint when FillForegndTrans
/// cannot become ODF hatch opacity.
///
/// Hollow hatch (`FillBkgndTrans==1`) keeps the transparent background
/// so page colour still shows through the gaps, and freezes paler
/// strokes toward white. Solid hatch composites the strokes over
/// FillBkgnd (then toward white when that cell is also translucent)
/// and writes both Trans cells 0 so Draw does not fade the box.
VsdxFill fillHatchTransForLibvisioWrite(
  VsdxFill fill, [
  VsdxTheme theme = VsdxTheme.empty,
  int? fillMatrix,
]) {
  if (!fillNeedsLibvisioHatchTransBake(fill)) return fill;
  if (fill.foreground == null && fill.themeForegroundIndex == null) {
    return fill;
  }
  final fg = _fillRgbForLibvisioWrite(fill, theme, fillMatrix: fillMatrix);
  final fgT = fill.foregroundTransparency.clamp(0.0, 1.0);
  final bgT = fill.backgroundTransparency.clamp(0.0, 1.0);
  if (bgT >= 1 - 1e-9) {
    return fill.copyWith(
      foreground: colourForLibvisioAlpha(fg, fgT),
      foregroundTransparency: 0,
      clearThemeForegroundIndex: true,
    );
  }
  final bg = _fillBackgroundRgbForLibvisioWrite(fill, theme) ??
      const VsdxColor(0xFFFFFFFF);
  final gap = colourForLibvisioAlpha(bg, bgT);
  return fill.copyWith(
    foreground: _colourOver(gap, fg, fgT),
    background: gap,
    foregroundTransparency: 0,
    backgroundTransparency: 0,
    clearThemeForegroundIndex: true,
    clearThemeBackgroundIndex: true,
  );
}

/// Freeze hatch FillForegndTrans into RGB cells Draw will paint.
VsdxDocument bakeHatchTransForLibvisioWrite(VsdxDocument document) {
  final theme = document.theme;
  var pagesChanged = false;
  final pages = <VsdxPage>[];
  VsdxShape bakeShape(VsdxShape shape) {
    final fill = fillHatchTransForLibvisioWrite(
      shape.fill,
      theme,
      shape.quickStyleFillMatrix,
    );
    final children = <VsdxShape>[
      for (final child in shape.children) bakeShape(child),
    ];
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (identical(fill, shape.fill) && !childrenChanged) return shape;
    return shape.copyWith(fill: fill, children: children);
  }

  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) bakeShape(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

VsdxColor _colourOver(VsdxColor dst, VsdxColor src, double srcTransparency) {
  final a = 1 - srcTransparency.clamp(0.0, 1.0);
  if (a >= 1 - 1e-9) return src;
  if (a <= 1e-9) return dst;
  int mix(int s, int d) => (s * a + d * (1 - a)).round().clamp(0, 255);
  return VsdxColor.argb(
    0xFF,
    mix(src.red, dst.red),
    mix(src.green, dst.green),
    mix(src.blue, dst.blue),
  );
}

/// RGB Draw will paint when libvisio strips alpha (`xmlStringToColour`
/// always stores Colour.a = 0, and ColorTrans / LineColorTrans /
/// ShdwForegndTrans are not tokens). Blends [foreground] toward white.
VsdxColor colourForLibvisioAlpha(VsdxColor foreground, double transparency) {
  final t = transparency.clamp(0.0, 1.0);
  if (t <= 1e-9) return foreground;
  int mix(int channel) => (channel * (1 - t) + 255 * t).round().clamp(0, 255);
  return VsdxColor.argb(
    0xFF,
    mix(foreground.red),
    mix(foreground.green),
    mix(foreground.blue),
  );
}

/// RGB canvas `_colourOrTheme` would paint for a character run.
VsdxColor? _charRgbForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (style.color != null) return style.color;
  final slot = style.themeColorIndex;
  if (slot == null) return null;
  return theme.resolve(slot) ?? VsdxTheme.office.resolve(slot);
}

/// `Color` cell Draw will collect. Character ColorTrans is not a token.
///
/// Theme-only Color still has to freeze into this RGB blend because
/// `readCharIX` never stores ColorTrans — Draw would otherwise paint
/// THEMEVAL() fully opaque, while canvas already multiplies
/// `_colourOrTheme` by (1 − ColorTrans).
VsdxColor? charColorForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (style.transparency <= 1e-9) return style.color;
  final color = _charRgbForLibvisioWrite(style, theme);
  if (color == null && style.themeColorIndex != null) return style.color;
  return colourForLibvisioAlpha(
    color ?? const VsdxColor(0xFF000000),
    style.transparency,
  );
}

/// `ColorTrans` cell. Zeroed when [charColorForLibvisioWrite] baked alpha
/// into RGB so Visio does not fade the already-blended colour a second time.
double charTransparencyForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (style.transparency <= 1e-9) return style.transparency;
  if (charColorForLibvisioWrite(style, theme) == null) {
    return style.transparency;
  }
  return 0;
}

/// Theme slot still written as THEMEVAL() after [charColorForLibvisioWrite].
///
/// A ColorTrans bake emits hex Color, so the slot must not survive as
/// THEMEVAL() or Draw would ignore the faded RGB.
int? charThemeColorIndexForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (charColorForLibvisioWrite(style, theme) != null) return null;
  return style.themeColorIndex;
}

/// `ShdwForegnd` / `ShdwForegndTrans` Draw will collect. Shadow alpha is
/// `shadowFgColour.a`, which VSDX `xmlStringToColour` forces to 0.
///
/// Theme-only Color still has to freeze into this RGB blend when the
/// edge is hard: `ShdwForegndTrans` is not a token, so Draw would
/// paint THEMEVAL() fully opaque, while canvas already multiplies
/// `_colourOrTheme` by (1 − ShdwForegndTrans). Soft theme shadows keep
/// THEMEVAL() on the leftover after the Gaussian PNG bake.
VsdxShadow shadowForLibvisioWrite(
  VsdxShadow shadow, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (!shadow.enabled || shadow.transparency <= 1e-9) {
    return shadow;
  }
  if (shadow.color == null && shadow.themeColorIndex != null) {
    if (shadow.blurInches > 1e-6) return shadow;
    return shadow.copyWith(
      color: colourForLibvisioAlpha(
        _shadowRgbForLibvisioWrite(shadow, theme),
        shadow.transparency,
      ),
      transparency: 0,
      clearThemeColorIndex: true,
    );
  }
  return shadow.copyWith(
    color: colourForLibvisioAlpha(
      shadow.color ?? const VsdxColor(0xFF000000),
      shadow.transparency,
    ),
    transparency: 0,
    clearThemeColorIndex: true,
  );
}

/// Every shadow cell Draw will collect for [shape].
///
/// Adds the shape-level half [shadowForLibvisioWrite] cannot see: `ShdwPattern`
/// and `ShadowBlur` go to 0 once a Gaussian PNG sibling carries the blur, so
/// Draw does not add a second hard copy. Mirrors
/// [reflectionForLibvisioWrite].
VsdxShadow shadowCellsForLibvisioWrite(VsdxShape shape) {
  final shadow = shadowForLibvisioWrite(shape.shadow);
  if (!shapeNeedsLibvisioShadowBake(shape)) return shadow;
  return shadow.copyWith(enabled: false, blurInches: 0);
}

/// Layer `Color` / `ColorTrans` Draw will collect.
///
/// `readLayerIX` stores `Color` and skips `ColorTrans` (not a token).
/// `xmlStringToColour` also forces Colour.a = 0. A tint with no RGB is
/// left alone.
VsdxLayer layerForLibvisioWrite(VsdxLayer layer) {
  if (layer.color == null || layer.colorTrans <= 1e-9) return layer;
  return layer.copyWith(
    color: colourForLibvisioAlpha(layer.color!, layer.colorTrans),
    colorTrans: 0,
  );
}

/// Face libvisio's `readCharIX` will actually load (`tokens.txt` has `Font`,
/// not `AsianFont` / `ComplexScriptFont`).
const kLibvisioDefaultAsianFont = 'Microsoft YaHei';

bool _isLatinLetterRune(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

/// Han / Kana / Hangul / Bopomofo with no Latin or complex-script letters.
bool _isAsianOnly(String text) {
  var hasAsian = false;
  for (final rune in text.runes) {
    if (isVisioAsianScriptRune(rune)) {
      hasAsian = true;
      continue;
    }
    if (isVisioComplexScriptRune(rune) || _isLatinLetterRune(rune)) {
      return false;
    }
  }
  return hasAsian;
}

/// Arabic / Hebrew / Indic / … with no Latin or East-Asian letters.
bool _isComplexScriptOnly(String text) {
  var hasComplex = false;
  for (final rune in text.runes) {
    if (isVisioComplexScriptRune(rune)) {
      hasComplex = true;
      continue;
    }
    if (isVisioAsianScriptRune(rune) || _isLatinLetterRune(rune)) {
      return false;
    }
  }
  return hasComplex;
}

bool _isLatinUiFace(String? face) {
  if (face == null || face.isEmpty) return true;
  switch (face.toLowerCase()) {
    case 'arial':
    case 'calibri':
    case 'cambria':
    case 'candara':
    case 'consolas':
    case 'constantia':
    case 'corbel':
    case 'courier new':
    case 'georgia':
    case 'helvetica':
    case 'segoe ui':
    case 'tahoma':
    case 'times':
    case 'times new roman':
    case 'trebuchet ms':
    case 'verdana':
      return true;
    default:
      return false;
  }
}

/// `Font` cell Draw will collect. Asian-only runs whose Visio `Font` is a
/// Latin UI face are rewritten to `AsianFont` (or YaHei); complex-script-only
/// runs use `ComplexScriptFont`. Mixed Latin+CJK / Latin+Arabic runs are
/// split first so each script still goes through this helper.
String? fontFamilyForLibvisioWrite(VsdxCharStyle style, String text) {
  final current = style.fontFamily;
  if (_isAsianOnly(text)) {
    final asian = style.asianFont?.trim();
    if (asian != null && asian.isNotEmpty) return asian;
    if (_isLatinUiFace(current)) return kLibvisioDefaultAsianFont;
    return current;
  }
  if (_isComplexScriptOnly(text)) {
    final complex = style.complexScriptFont?.trim();
    if (complex != null && complex.isNotEmpty) return complex;
  }
  return current;
}

/// `Size` cell Draw will collect. `ComplexScriptSize` is not a token, so a
/// complex-script-only run writes that size into `Size`. Mixed runs keep
/// `Size` so Latin glyphs do not jump.
double fontSizeForLibvisioWrite(VsdxCharStyle style, String text) {
  final complex = style.complexScriptSizeInches;
  if (complex != null &&
      _isComplexScriptOnly(text) &&
      (complex - style.fontSizeInches).abs() > 1e-12) {
    return complex;
  }
  return style.fontSizeInches;
}

/// Mean Latin advance used to fold Letterspace into FontScale for Draw.
///
/// `Letterspace` is not a token. Canvas / SVG paint it as tracking and apply
/// FontScale as a true width scale (`style:text-scale`). A save therefore
/// stretches glyphs by this extra amount so Draw's collected scale still
/// matches the tracked line width.
const kLibvisioMeanLatinAdvance = 0.55;

/// `FontScale` Draw will collect. Letterspace is not a token, so extra
/// tracking is folded into this scale with [kLibvisioMeanLatinAdvance].
/// Super/subscript use the same 0.7× Size canvas and SVG apply before
/// adding FontScale tracking.
double fontScaleForLibvisioWrite(VsdxCharStyle style, [String text = '']) {
  var fs = fontSizeForLibvisioWrite(style, text);
  switch (style.position) {
    case VsdxTextPosition.superscript:
    case VsdxTextPosition.subscript:
      fs *= 0.7;
    case VsdxTextPosition.normal:
      break;
  }
  var scale = style.fontScale;
  if (style.letterSpacingInches.abs() > 1e-12 && fs > 1e-9) {
    scale += style.letterSpacingInches / (fs * kLibvisioMeanLatinAdvance);
  }
  return scale;
}

/// `Letterspace` cell. Zeroed when [fontScaleForLibvisioWrite] absorbed it.
double letterSpacingForLibvisioWrite(VsdxCharStyle style, [String text = '']) {
  if ((fontScaleForLibvisioWrite(style, text) - style.fontScale).abs() >
      1e-12) {
    return 0;
  }
  return style.letterSpacingInches;
}

bool shapeNeedsLibvisioFontBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    final baked = fontFamilyForLibvisioWrite(run.charStyle, run.text);
    final current = run.charStyle.fontFamily;
    if ((baked ?? '') != (current ?? '')) return true;
    if ((fontSizeForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.fontSizeInches)
            .abs() >
        1e-12) {
      return true;
    }
    if (charTransparencyForLibvisioWrite(run.charStyle) !=
        run.charStyle.transparency) {
      return true;
    }
    if ((fontScaleForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.fontScale)
            .abs() >
        1e-12) {
      return true;
    }
    if ((letterSpacingForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.letterSpacingInches)
            .abs() >
        1e-12) {
      return true;
    }
  }
  return false;
}
