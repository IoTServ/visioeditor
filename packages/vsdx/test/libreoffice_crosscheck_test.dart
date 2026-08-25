import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Optional LibreOffice headless cross-check.
///
/// Skips when `soffice` / `libreoffice` is not on PATH and `SOFFICE` is unset,
/// unless `REQUIRE_SOFFICE=1` (CI) — then missing soffice fails the test.
///
/// When available, writes a round-tripped `.vsdx` and asks soffice to convert
/// it to PDF (proves LibreOffice can open the package).
void main() {
  final soffice = _resolveSoffice();
  final pdftoppm = _resolveExecutable('pdftoppm');
  final require = Platform.environment['REQUIRE_SOFFICE'] == '1';

  test('LibreOffice soffice opens a writer round-trip .vsdx', () async {
    if (soffice == null) {
      if (require) {
        fail('REQUIRE_SOFFICE=1 but LibreOffice soffice was not found '
            '(set SOFFICE or install LibreOffice)');
      }
      // ignore: avoid_print
      print('skip: LibreOffice soffice not installed '
          '(set SOFFICE or install LibreOffice)');
      return;
    }

    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final pageWithBox = doc.pages.first.addShape(
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 3,
        width: 2,
        height: 1,
        name: 'Box',
      ).copyWith(
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Hello LO')],
        ),
      ),
    );
    final pageWithInfinite = pageWithBox.addShape(
      VsdxShape(
        id: id + 1,
        name: 'InfiniteLine',
        pinX: 5,
        pinY: 3,
        width: 0.01,
        height: 0.01,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              InfiniteLineCmd(x: 0, y: 0.005, a: 0.01, b: 0.005),
            ],
          ),
        ],
      ),
    );
    final pageWithArc = pageWithInfinite.addShape(
      VsdxShape(
        id: id + 2,
        name: 'ArcTo',
        pinX: 5,
        pinY: 1.5,
        width: 2,
        height: 1,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              ArcTo(x: 2, y: 0, bow: 0.6),
            ],
          ),
        ],
      ),
    );
    final pageWithDegenerateArc = pageWithArc.addShape(
      VsdxShape(
        id: id + 3,
        name: 'DegenerateEllipticalArcTo',
        pinX: 2,
        pinY: 1.5,
        width: 2,
        height: 1,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              EllipticalArcTo(
                x: 2,
                y: 0,
                controlX: 1,
                controlY: 1,
                angle: 0,
                eccentricity: 0,
              ),
            ],
          ),
        ],
      ),
    );
    final pageWithDegenerateEllipse = pageWithDegenerateArc.addShape(
      VsdxShape(
        id: id + 4,
        name: 'DegenerateEllipse',
        pinX: 4,
        pinY: 4,
        width: 2,
        height: 2,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              EllipseCmd(
                cx: 1,
                cy: 1,
                aX: 1,
                aY: 1,
                bX: 1,
                bY: 2,
              ),
            ],
          ),
        ],
      ),
    );
    doc = doc.replacePage(
      0,
      pageWithDegenerateEllipse
          .addShape(
            VsdxShape(
              id: id + 5,
              name: 'HighDegreeNURBS',
              pinX: 5.5,
              pinY: 6.5,
              width: 9,
              height: 1,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0.5),
                    NurbsTo(
                      x: 9,
                      y: 0.5,
                      controlPoints: <Offset2D>[
                        Offset2D(1, 1),
                        Offset2D(2, 0),
                        Offset2D(3, 1),
                        Offset2D(4, 0),
                        Offset2D(5, 1),
                        Offset2D(6, 0),
                        Offset2D(7, 1),
                        Offset2D(8, 0),
                      ],
                      weights: <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                      knots: <double>[
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0.5,
                        1,
                        1,
                        1,
                        1,
                        1,
                        1,
                        1,
                        1,
                        1,
                      ],
                      degree: 9,
                    ),
                  ],
                ),
              ],
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 6,
              name: 'CubBezTo',
              pinX: 2,
              pinY: 6,
              width: 2,
              height: 1,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    CubBezTo(x: 2, y: 0, x1: 0.5, y1: 1, x2: 1.5, y2: 1),
                  ],
                ),
              ],
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 7,
              name: 'QuadBezTo',
              pinX: 4.5,
              pinY: 6,
              width: 2,
              height: 1,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    QuadBezTo(x: 2, y: 0, x1: 1, y1: 1),
                  ],
                ),
              ],
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 8,
              name: 'RelArcTo',
              pinX: 7,
              pinY: 5,
              width: 2,
              height: 1,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    RelMoveTo(0, 0),
                    RelArcTo(fx: 1, fy: 0, fbow: 0.2),
                  ],
                ),
              ],
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 9,
              pinX: 2,
              pinY: 7.5,
              width: 1.5,
              height: 0.8,
              name: 'HatchFill',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFFF0000),
                background: VsdxColor(0xFF0000FF),
                pattern: 2,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 10,
              pinX: 4,
              pinY: 7.5,
              width: 1.5,
              height: 0.8,
              name: 'ClassicRadialFill',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFFF0000),
                background: VsdxColor(0xFF0000FF),
                pattern: 40,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 11,
              pinX: 6,
              pinY: 7.5,
              width: 1.5,
              height: 0.8,
              name: 'FillGradient',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFFF0000),
                background: VsdxColor(0xFF0000FF),
                pattern: 1,
                gradient: VsdxGradient(
                  stops: [
                    VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                    VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
                  ],
                ),
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 12,
              pinX: 8,
              pinY: 7.5,
              width: 1.5,
              height: 0.8,
              name: 'Rounding',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFF00), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                roundingInches: 0.15,
                pattern: 2,
                endArrow: 4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 13,
              pinX: 2,
              pinY: 6.5,
              width: 1.5,
              height: 0.8,
              name: 'CompoundDouble',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 1,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 14,
              ax: 4,
              ay: 6.5,
              bx: 7,
              by: 6.5,
              name: 'Compound1D',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 1,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 15,
              ax: 1,
              ay: 5.5,
              bx: 4,
              by: 5.5,
              name: 'LineGradient1D',
              line: const VsdxLine(
                pattern: 1,
                weightInches: 0.06,
                gradient: VsdxGradient(
                  stops: [
                    VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                    VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
                  ],
                ),
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 16,
              ax: 5,
              ay: 5.5,
              bx: 8,
              by: 5.5,
              name: 'CapFlat',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                cap: LineCap.extended,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 17,
              ax: 1,
              ay: 6.2,
              bx: 4,
              by: 6.2,
              name: 'LineColorTrans1D',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                transparency: 0.5,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 18,
              ax: 5,
              ay: 6.2,
              bx: 8,
              by: 6.2,
              name: 'ArrowedCompound1D',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 1,
                beginArrow: 4,
                endArrow: 13,
                beginArrowSizeInches: 0.25,
                endArrowSizeInches: 0.25,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 19,
              ax: 1,
              ay: 4.8,
              bx: 4,
              by: 4.8,
              name: 'ArrowedLineGradient1D',
              line: const VsdxLine(
                pattern: 1,
                weightInches: 0.06,
                beginArrow: 4,
                endArrow: 13,
                beginArrowSizeInches: 0.25,
                endArrowSizeInches: 0.25,
                gradient: VsdxGradient(
                  stops: [
                    VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                    VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
                  ],
                ),
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 20,
              ax: 5,
              ay: 4.8,
              bx: 8,
              by: 4.8,
              name: 'ArrowedLineColorTrans1D',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                transparency: 0.5,
                beginArrow: 4,
                endArrow: 13,
                beginArrowSizeInches: 0.25,
                endArrowSizeInches: 0.25,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 21,
              pinX: 8,
              pinY: 3.5,
              width: 1.4,
              height: 0.7,
              name: 'Highlight',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: 'Hi',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: 'Hi',
                    charStyle: VsdxCharStyle(highlight: VsdxColor(0xFFFF00FF)),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 22,
              pinX: 8,
              pinY: 2.5,
              width: 1.4,
              height: 0.7,
              name: 'CJK',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: '你好',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: '你好',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      asianFont: 'Microsoft YaHei',
                    ),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 23,
              pinX: 6,
              pinY: 2.5,
              width: 1.4,
              height: 0.7,
              name: 'Hangul',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: '안녕',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: '안녕',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      asianFont: 'Microsoft YaHei',
                    ),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 24,
              pinX: 4,
              pinY: 2.5,
              width: 1.4,
              height: 0.7,
              name: 'Arabic',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: 'سلام',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: 'سلام',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      complexScriptFont: 'Times New Roman',
                      complexScriptSizeInches: 18 / 72,
                    ),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 25,
              pinX: 2,
              pinY: 8.2,
              width: 1.5,
              height: 0.8,
              name: 'FillUnknown',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFFF0000),
                background: VsdxColor(0xFF0000FF),
                pattern: 41,
              ),
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 26,
              name: 'RoundJoin',
              pinX: 8,
              pinY: 8.2,
              width: 1.4,
              height: 1.4,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(1.4, 0),
                    LineTo(1.4, 1.4),
                  ],
                ),
              ],
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                cap: LineCap.square,
                join: VsdxLineJoin.round,
              ),
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 27,
              name: 'BevelJoin',
              pinX: 6,
              pinY: 8.2,
              width: 1.4,
              height: 1.4,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(1.4, 0),
                    LineTo(1.4, 1.4),
                  ],
                ),
              ],
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                cap: LineCap.square,
                join: VsdxLineJoin.bevel,
              ),
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 28,
              name: 'ArcsJoin',
              pinX: 4,
              pinY: 8.2,
              width: 1.4,
              height: 1.4,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(1.4, 0),
                    LineTo(1.4, 1.4),
                  ],
                ),
              ],
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                cap: LineCap.square,
                join: VsdxLineJoin.arcs,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 29,
              pinX: 2,
              pinY: 3.5,
              width: 1.5,
              height: 0.8,
              name: 'CompoundThinThick',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 3,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 30,
              pinX: 4,
              pinY: 3.5,
              width: 1.5,
              height: 0.8,
              name: 'CompoundTriple',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 31,
              ax: 1,
              ay: 0.4,
              bx: 4,
              by: 0.4,
              name: 'CompoundThinThick1D',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 3,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 32,
              ax: 5,
              ay: 0.4,
              bx: 8,
              by: 0.4,
              name: 'CompoundTriple1D',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                compoundType: 4,
              ),
            ),
          )
          .addShape(
            VsdxShape(
              id: id + 33,
              name: 'BevelRoundCap',
              pinX: 6,
              pinY: 9.5,
              width: 1.4,
              height: 1.4,
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(1.4, 0),
                    LineTo(1.4, 1.4),
                  ],
                ),
              ],
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.08,
                cap: LineCap.round,
                join: VsdxLineJoin.bevel,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 34,
              pinX: 3.5,
              pinY: 9.5,
              width: 1.5,
              height: 0.8,
              name: 'FilledLineTrans',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.04,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 35,
              ax: 1,
              ay: 9.9,
              bx: 4,
              by: 9.9,
              name: 'LargeArrow',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.01,
                beginArrow: 4,
                endArrow: 1,
                beginArrowSizeInches: 0.35,
                endArrowSizeInches: 0.35,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 36,
              pinX: 6,
              pinY: 1.6,
              width: 1.4,
              height: 0.7,
              name: 'TextBkgndTrans',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: 'Hi',
              richText: const VsdxRichText(
                textBlock: VsdxTextBlock(
                  backgroundColor: VsdxColor(0xFF0000FF),
                  backgroundTransparency: 0.5,
                ),
                runs: [VsdxTextRun(text: 'Hi')],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 37,
              ax: 0.4,
              ay: 10.5,
              bx: 3.2,
              by: 10.5,
              name: 'JumpUnder',
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 38,
              ax: 1.8,
              ay: 10.95,
              bx: 1.8,
              by: 10.05,
              name: 'JumpOver',
            ),
          )
          .addShape(
            VsdxShapeFactory.picture(
              id: id + 39,
              pinX: 7.2,
              pinY: 10.5,
              width: 1.2,
              height: 0.8,
              imagePartName: '/visio/media/image_lo_tone.png',
              name: 'PictureTone',
            ).copyWith(
              imageTransparency: 0.4,
              imageBrightness: 0.7,
              imageContrast: 0.35,
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 40,
              ax: 4.2,
              ay: 10.5,
              bx: 6.4,
              by: 10.5,
              name: 'GlowStroke',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.04,
              ),
            ).copyWith(
              glow: const VsdxGlow(
                color: VsdxColor(0xFFFF00FF),
                sizeInches: 0.08,
                transparency: 0.5,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 41,
              pinX: 0.9,
              pinY: 9.4,
              width: 1.4,
              height: 0.6,
              name: 'GlowNoLine',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
              line: const VsdxLine(pattern: 0),
            ).copyWith(
              glow: const VsdxGlow(
                color: VsdxColor(0xFFFF00FF),
                sizeInches: 0.08,
                transparency: 0.5,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 42,
              pinX: 2.6,
              pinY: 9.4,
              width: 1.4,
              height: 0.6,
              name: 'Overline',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: 'AB',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: 'AB',
                    charStyle: VsdxCharStyle(overline: true),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 43,
              pinX: 4.3,
              pinY: 9.4,
              width: 1.4,
              height: 0.6,
              name: 'Letterspace',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: 'Hi',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: 'Hi',
                    charStyle: VsdxCharStyle(letterSpacingInches: 0.02),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.picture(
              id: id + 44,
              pinX: 6.0,
              pinY: 9.4,
              width: 1.2,
              height: 0.8,
              imagePartName: '/visio/media/image_lo_tone.png',
              name: 'PictureSoft',
            ).copyWith(
              line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
            ),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: id + 45,
              ax: 1.0,
              ay: 9.4,
              bx: 2.6,
              by: 9.4,
              name: 'TodoArrow',
              line: const VsdxLine(
                color: VsdxColor.black,
                weightInches: 0.04,
                endArrow: 40,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 46,
              pinX: 4.4,
              pinY: 8.4,
              width: 2.2,
              height: 1.6,
              name: 'Bullets',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: '1234567',
              richText: VsdxRichText(
                runs: <VsdxTextRun>[
                  for (var bullet = 1; bullet <= 7; bullet++)
                    VsdxTextRun(
                      text: bullet == 7 ? '$bullet' : '$bullet\n',
                      paraStyle: VsdxParaStyle(bullet: bullet),
                    ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 47,
              pinX: 7.2,
              pinY: 8.4,
              width: 1.6,
              height: 0.8,
              name: 'Reflection',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFCC5533), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              reflection: const VsdxReflection(
                enabled: true,
                sizeInches: 0.45,
                distanceInches: 0.06,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 48,
              pinX: 7.2,
              pinY: 9.4,
              width: 1.4,
              height: 0.6,
              name: 'GlowFillStroke',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                pattern: 1,
                weightInches: 0.02,
              ),
            ).copyWith(
              glow: const VsdxGlow(
                color: VsdxColor(0xFF00CC66),
                sizeInches: 0.08,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 49,
              pinX: 8.8,
              pinY: 9.4,
              width: 1.4,
              height: 0.6,
              name: 'SketchBox',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFF2244AA), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                pattern: 1,
                weightInches: 0.02,
              ),
            )
                .withSketchEffect(true)
                .withSketchJiggle(3)
                .withSketchFillStyle(VsdxSketchFillStyle.hachure),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 50,
              pinX: 8.8,
              pinY: 8.4,
              width: 1.4,
              height: 0.6,
              name: 'GlassBox',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor.black,
                pattern: 1,
                weightInches: 0.02,
              ),
            ).withGlassEffect(true),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 51,
              pinX: 7.2,
              pinY: 7.4,
              width: 1.4,
              height: 0.6,
              name: 'OpacityBox',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
              line: const VsdxLine(pattern: 0),
            ).withShapeOpacity(0.4),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 52,
              pinX: 5.6,
              pinY: 7.4,
              width: 1.4,
              height: 0.6,
              name: 'LabelBorderBox',
              fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
              line: const VsdxLine(pattern: 0),
            )
                .copyWith(
                  richText: const VsdxRichText(
                    runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
                  ),
                )
                .withLabelBorderColor(const VsdxColor(0xFF1565C0)),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 53,
              pinX: 4.2,
              pinY: 7.4,
              width: 1.4,
              height: 0.6,
              name: 'LabelPaddingBox',
              fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
              line: const VsdxLine(pattern: 0),
            )
                .copyWith(
                  richText: const VsdxRichText(
                    runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
                    textBlock: VsdxTextBlock(
                      marginLeftInches: 0,
                      marginRightInches: 0,
                      marginTopInches: 0,
                      marginBottomInches: 0,
                    ),
                  ),
                )
                .withLabelPadding(
                  const VsdxLabelPadding(
                      left: 48, right: 24, top: 12, bottom: 36),
                ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 54,
              pinX: 2.6,
              pinY: 7.4,
              width: 0.8,
              height: 0.6,
              name: 'WordWrapBox',
              fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
              line: const VsdxLine(pattern: 0),
            )
                .copyWith(
                  richText: const VsdxRichText(
                    runs: <VsdxTextRun>[
                      VsdxTextRun(text: 'NO WRAP NO WRAP NO WRAP'),
                    ],
                  ),
                )
                .withWordWrap(false),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 55,
              pinX: 1.0,
              pinY: 8.6,
              width: 1.4,
              height: 0.6,
              name: 'GeometrySoft',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
              line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 56,
              pinX: 5.5,
              pinY: 8.6,
              width: 1.4,
              height: 0.6,
              name: 'ShadowBlur',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
              line: const VsdxLine(pattern: 0),
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: true,
                color: VsdxColor(0xFF000000),
                offsetXInches: 0.18,
                offsetYInches: -0.12,
                blurInches: 0.08,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 57,
              pinX: 3.2,
              pinY: 7.6,
              width: 1.4,
              height: 0.6,
              name: 'StrokeSoft',
              fill: const VsdxFill(pattern: 0),
              line: const VsdxLine(
                color: VsdxColor(0xFF000000),
                weightInches: 0.08,
                softEdgesInches: 0.08,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 58,
              pinX: 7.0,
              pinY: 7.6,
              width: 1.4,
              height: 0.6,
              name: 'FillStrokeSoft',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
              line: const VsdxLine(
                color: VsdxColor(0xFF000000),
                weightInches: 0.08,
                softEdgesInches: 0.08,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 59,
              pinX: 5.1,
              pinY: 7.6,
              width: 1.4,
              height: 0.6,
              name: 'GlowNoFill',
              fill: const VsdxFill(pattern: 0),
              line: const VsdxLine(
                color: VsdxColor.black,
                pattern: 1,
                weightInches: 0.04,
              ),
            ).copyWith(
              glow: const VsdxGlow(
                color: VsdxColor(0xFF00CC66),
                sizeInches: 0.08,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.picture(
              id: id + 60,
              pinX: 3.2,
              pinY: 6.6,
              width: 1.2,
              height: 0.8,
              imagePartName: '/visio/media/image_lo_tone.png',
              name: 'PictureGlow',
            ).copyWith(
              glow: const VsdxGlow(
                color: VsdxColor(0xFF00CC66),
                sizeInches: 0.08,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.picture(
              id: id + 61,
              pinX: 5.0,
              pinY: 6.6,
              width: 1.2,
              height: 0.8,
              imagePartName: '/visio/media/image_lo_tone.png',
              name: 'PictureShadow',
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: true,
                color: VsdxColor(0xFF000000),
                offsetXInches: 0.2,
                offsetYInches: -0.15,
                blurInches: 0.08,
                transparency: 0.4,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.picture(
              id: id + 62,
              pinX: 6.8,
              pinY: 6.6,
              width: 1.2,
              height: 0.8,
              imagePartName: '/visio/media/image_lo_reflection.png',
              name: 'PictureReflection',
            ).copyWith(
              reflection: const VsdxReflection(
                enabled: true,
                sizeInches: 0.5,
                distanceInches: 0.08,
                transparency: 0.4,
                blurInches: 0,
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 63,
              pinX: 2.2,
              pinY: 6.6,
              width: 1.4,
              height: 0.7,
              name: 'LangIdRtl',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: '123',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: '123',
                    charStyle: VsdxCharStyle(langId: 'ar-SA'),
                  ),
                ],
              ),
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: id + 64,
              pinX: 3.8,
              pinY: 6.6,
              width: 1.4,
              height: 0.7,
              name: 'LangIdLtr',
              fill:
                  const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
              line: const VsdxLine(color: VsdxColor.black, pattern: 0),
            ).copyWith(
              text: '123',
              richText: const VsdxRichText(
                runs: [
                  VsdxTextRun(
                    text: '123',
                    charStyle: VsdxCharStyle(langId: 'en-US'),
                  ),
                ],
              ),
            ),
          ),
    );
    doc = doc.copyWith(
      images: doc.images
          .withImage(
            VsdxImage(
              partName: '/visio/media/image_lo_tone.png',
              bytes: _solidPng(),
              mimeType: 'image/png',
            ),
          )
          .withImage(
            VsdxImage(
              partName: '/visio/media/image_lo_reflection.png',
              bytes: _splitPng(),
              mimeType: 'image/png',
            ),
          ),
    );
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(backgroundColor: const VsdxColor(0xFF336699)),
    );
    final generated = writer.write(originalBytes: blank, edited: doc);
    final reopenedDoc = parser.parse(generated);
    final reopenedCommands = reopenedDoc.pages.first.shapes
        .expand((shape) => shape.geometries)
        .expand((geometry) => geometry.commands);
    expect(
      reopenedCommands.whereType<InfiniteLineCmd>(),
      hasLength(1),
      reason: 'InfiniteLine must survive the VSDX writer round-trip',
    );
    expect(
      reopenedCommands.whereType<ArcTo>(),
      hasLength(greaterThanOrEqualTo(2)),
      reason: 'ArcTo, rewritten RelArcTo, and baked line jumps',
    );
    expect(
      reopenedCommands.whereType<RelCubBezTo>(),
      isNotEmpty,
      reason: 'CubBezTo is rewritten to RelCubBezTo for LibreOffice',
    );
    expect(reopenedCommands.whereType<CubBezTo>(), isEmpty);
    expect(
      reopenedCommands.whereType<RelQuadBezTo>(),
      isNotEmpty,
      reason: 'QuadBezTo is rewritten to RelQuadBezTo for LibreOffice',
    );
    expect(reopenedCommands.whereType<QuadBezTo>(), isEmpty);
    expect(reopenedCommands.whereType<RelArcTo>(), isEmpty);
    expect(
      reopenedCommands.whereType<EllipticalArcTo>(),
      hasLength(1),
      reason: 'EllipticalArcTo must survive the VSDX writer round-trip',
    );
    expect(
      reopenedCommands.whereType<EllipseCmd>(),
      hasLength(1),
      reason: 'Ellipse must survive the VSDX writer round-trip',
    );
    expect(
      reopenedCommands.whereType<NurbsTo>().single.degree,
      9,
      reason: 'NURBSTo degree must survive the VSDX writer round-trip',
    );
    final lineGradient1d = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LineGradient1D');
    expect(lineGradient1d.is1D, isTrue);
    expect(lineGradient1d.line.hasGradient, isFalse);
    expect(lineGradient1d.geometries.any((g) => !g.noFill), isTrue);
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CapFlat')
          .line
          .cap,
      LineCap.extended,
    );
    final lineColorTrans1d = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LineColorTrans1D');
    expect(lineColorTrans1d.is1D, isTrue);
    expect(lineColorTrans1d.line.pattern, 0);
    expect(lineColorTrans1d.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(lineColorTrans1d.geometries.any((g) => !g.noFill), isTrue);
    final arrowedCompound = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ArrowedCompound1D');
    expect(arrowedCompound.is1D, isTrue);
    expect(arrowedCompound.line.beginArrow, 0);
    expect(arrowedCompound.line.compoundType, 0);
    expect(
      arrowedCompound.geometries.where((g) => !g.noLine).length,
      greaterThan(1),
    );
    expect(
      arrowedCompound.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
    );
    final arrowedGradient = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ArrowedLineGradient1D');
    expect(arrowedGradient.line.beginArrow, 0);
    expect(arrowedGradient.geometries.any((g) => !g.noFill), isTrue);
    final arrowedTrans = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ArrowedLineColorTrans1D');
    expect(arrowedTrans.line.beginArrow, 0);
    expect(arrowedTrans.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    final highlight =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Highlight');
    expect(
        highlight.richText.runs.single.charStyle.highlight?.value, 0xFFFF00FF);
    expect(highlight.richText.textBlock.backgroundColor?.value, 0xFFFF00FF);
    final largeArrow = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LargeArrow');
    expect(largeArrow.line.beginArrow, 0);
    expect(largeArrow.line.endArrow, 0);
    expect(largeArrow.geometries.any((g) => !g.noFill), isTrue);
    final textBkgndTrans = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'TextBkgndTrans');
    expect(textBkgndTrans.richText.textBlock.backgroundTransparency, 0);
    expect(
      textBkgndTrans.richText.textBlock.backgroundColor,
      colourForLibvisioAlpha(const VsdxColor(0xFF0000FF), 0.5),
    );
    final jumpOver =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'JumpOver');
    expect(jumpOver.connectorProps?.conLineJumpCode, 1);
    expect(
      jumpOver.geometries.expand((g) => g.commands).whereType<ArcTo>(),
      isNotEmpty,
      reason: 'ConLineJump hops bake to ArcTo so Draw can paint them',
    );
    final pictureTone = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'PictureTone');
    expect(pictureTone.imageTransparency, closeTo(0, 1e-6));
    expect(pictureTone.imageBrightness, closeTo(0.5, 1e-6));
    expect(pictureTone.imageContrast, closeTo(0.5, 1e-6));
    expect(pictureTone.imagePartName, isNot('/visio/media/image_lo_tone.png'));
    final pictureSoft = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'PictureSoft');
    expect(pictureSoft.line.softEdgesInches, closeTo(0, 1e-6),
        reason: 'SoftEdgesSize is not a token; the halo is PNG alpha');
    expect(pictureSoft.imagePartName, isNot('/visio/media/image_lo_tone.png'));
    final todoArrow =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'TodoArrow');
    expect(todoArrow.line.endArrow, 0,
        reason:
            'libvisio marker 40 is a filled TODO stub; Geometry is the halo');
    expect(todoArrow.geometries.any((g) => !g.noFill), isTrue);
    final bullets =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Bullets');
    expect(
      bullets.richText.runs.map((run) => run.paraStyle.bullet).toList(),
      <int>[0, 0, 0, 0, 0, 0, 0],
      reason: 'Draw never paints text:bullet-char; the glyph is in the text',
    );
    expect(
      [
        for (var i = 0; i < 7; i++)
          bullets.richText.runs[i].text.contains(libvisioBulletGlyph(i + 1)),
      ],
      <bool>[true, true, true, true, true, true, true],
    );
    final glowStroke = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowStroke');
    expect(glowStroke.glow.enabled, isFalse);
    expect(glowStroke.fill.hasFill, isFalse);
    expect(glowStroke.line.pattern, 1);
    final glowStrokePlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowStroke.id}',
    );
    expect(glowStrokePlate.hasImage, isTrue);
    expect(glowStrokePlate.is1D, isFalse);
    expect(glowStrokePlate.height, greaterThan(0.1));
    final glowNoFill = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowNoFill');
    expect(glowNoFill.glow.enabled, isFalse);
    expect(glowNoFill.fill.hasFill, isFalse);
    expect(glowNoFill.line.pattern, 1);
    final glowNoFillPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowNoFill.id}',
    );
    expect(glowNoFillPlate.hasImage, isTrue);
    final pictureGlow = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'PictureGlow');
    expect(pictureGlow.glow.enabled, isFalse);
    expect(pictureGlow.hasImage, isTrue);
    expect(pictureGlow.line.pattern, 0);
    final pictureGlowPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${pictureGlow.id}',
    );
    expect(pictureGlowPlate.hasImage, isTrue);
    expect(pictureGlowPlate.width, greaterThan(pictureGlow.width));
    final pictureShadow = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'PictureShadow');
    expect(pictureShadow.shadow.enabled, isFalse);
    expect(pictureShadow.shadow.blurInches, closeTo(0, 1e-9));
    final pictureReflection = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'PictureReflection');
    expect(pictureReflection.reflection.enabled, isFalse);
    expect(pictureReflection.hasImage, isTrue);
    final pictureReflectionPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) =>
          s.name ==
          '$kLibvisioReflectionShapeNamePrefix${pictureReflection.id}',
    );
    expect(pictureReflectionPlate.hasImage, isTrue);
    expect(glowNoFillPlate.width, greaterThan(glowNoFill.width));
    final glowNoLine = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowNoLine');
    expect(glowNoLine.glow.enabled, isFalse);
    expect(glowNoLine.line.pattern, 0);
    final glowNoLinePlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowNoLine.id}',
    );
    expect(glowNoLinePlate.hasImage, isTrue);
    expect(glowNoLinePlate.width, greaterThan(glowNoLine.width));
    final glowFillStroke = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowFillStroke');
    expect(glowFillStroke.glow.enabled, isFalse);
    expect(glowFillStroke.line.pattern, 1);
    final glowFillPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowFillStroke.id}',
    );
    expect(glowFillPlate.hasImage, isTrue);
    expect(glowFillPlate.locked, isTrue);
    expect(glowFillPlate.width, greaterThan(glowFillStroke.width));
    final sketchBox =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'SketchBox');
    expect(sketchBox.sketchEffect, isFalse);
    expect(sketchBox.fill.pattern, 15);
    expect(
      reopenedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    final glassBox =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'GlassBox');
    expect(glassBox.glassEffect, isFalse);
    final glassPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlassShapeNamePrefix${glassBox.id}',
    );
    expect(glassPlate.locked, isTrue);
    expect(glassPlate.fill.pattern, 1);
    expect(glassPlate.fill.foreground?.value, VsdxColor.white.value);
    expect(glassPlate.fill.foregroundTransparency, closeTo(0.45, 1e-9));
    expect(glassPlate.line.pattern, 0);
    expect(
      glassPlate.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    final opacityBox = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'OpacityBox');
    expect(opacityBox.shapeOpacity, 1);
    expect(opacityBox.fill.foregroundTransparency, closeTo(0.6, 1e-9));
    expect(opacityBox.fill.foreground?.value, 0xFFFF0000);
    final labelBorderBox = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LabelBorderBox');
    expect(labelBorderBox.labelBorderColor, isNull);
    final labelBorderPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) =>
          s.name == '$kLibvisioLabelBorderShapeNamePrefix${labelBorderBox.id}',
    );
    expect(labelBorderPlate.locked, isTrue);
    expect(labelBorderPlate.fill.pattern, 0);
    expect(labelBorderPlate.line.pattern, 1);
    expect(labelBorderPlate.line.color?.value, 0xFF1565C0);
    expect(
      labelBorderPlate.line.weightInches,
      closeTo(1 / kLibvisioLabelBorderPxPerInch, 1e-9),
    );
    final labelPaddingBox = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LabelPaddingBox');
    expect(labelPaddingBox.labelPadding.isZero, isTrue);
    expect(
      labelPaddingBox.richText.textBlock.marginLeftInches,
      closeTo(48 / kLibvisioLabelPaddingPxPerInch, 1e-9),
    );
    expect(
      labelPaddingBox.richText.textBlock.marginRightInches,
      closeTo(24 / kLibvisioLabelPaddingPxPerInch, 1e-9),
    );
    final wordWrapBox = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'WordWrapBox');
    expect(wordWrapBox.wordWrap, isTrue);
    expect(
      wordWrapBox.richText.textBlock.widthInches,
      greaterThan(0.8),
      reason: 'User.veWordWrap is not a token; save expands TxtWidth',
    );
    final geometrySoft = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GeometrySoft');
    expect(geometrySoft.fill.pattern, 0);
    expect(geometrySoft.line.softEdgesInches, closeTo(0, 1e-9));
    expect(
      reopenedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(3),
    );
    final strokeSoft = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'StrokeSoft');
    expect(strokeSoft.line.pattern, 0);
    expect(strokeSoft.line.softEdgesInches, closeTo(0, 1e-9));
    final fillStrokeSoft = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'FillStrokeSoft');
    expect(fillStrokeSoft.fill.pattern, 0);
    expect(fillStrokeSoft.line.pattern, 0);
    expect(fillStrokeSoft.line.softEdgesInches, closeTo(0, 1e-9));
    final shadowBlur = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ShadowBlur');
    expect(shadowBlur.shadow.enabled, isFalse);
    expect(shadowBlur.shadow.blurInches, closeTo(0, 1e-9));
    expect(
      reopenedDoc.pages.first.shapes.where(isLibvisioShadowPlate),
      hasLength(2),
    );
    final overline =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Overline');
    expect(overline.richText.runs.single.charStyle.overline, isFalse);
    expect(
      overline.richText.runs.single.text,
      contains(kLibvisioCombiningOverline),
    );
    final letterspace = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Letterspace')
        .richText
        .runs
        .single
        .charStyle;
    expect(letterspace.letterSpacingInches, closeTo(0, 1e-6),
        reason: 'Letterspace is not a token; tracking bakes into FontScale');
    expect(
      letterspace.fontScale,
      closeTo(
        fontScaleForLibvisioWrite(
          const VsdxCharStyle(letterSpacingInches: 0.02),
          'Hi',
        ),
        1e-9,
      ),
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CJK')
          .richText
          .runs
          .single
          .charStyle
          .fontFamily,
      'Microsoft YaHei',
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'Hangul')
          .richText
          .runs
          .single
          .charStyle
          .fontFamily,
      'Microsoft YaHei',
    );
    final arabic = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Arabic')
        .richText
        .runs
        .single
        .charStyle;
    expect(arabic.fontFamily, 'Times New Roman');
    expect(arabic.fontSizeInches, closeTo(18 / 72, 1e-12));
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'Arabic')
          .richText
          .runs
          .single
          .text,
      isNot(startsWith(kLibvisioRtlMark)),
      reason: 'strong RTL letters already set Unicode bidi in Draw',
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'LangIdRtl')
          .richText
          .runs
          .single
          .text,
      '$kLibvisioRtlMark'
      '123',
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'LangIdLtr')
          .richText
          .runs
          .single
          .text,
      '123',
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'FillUnknown')
          .fill
          .pattern,
      1,
    );
    final pageColorPlate = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == kLibvisioPageColorShapeName);
    expect(reopenedDoc.pages.first.shapes.first.id, pageColorPlate.id);
    expect(pageColorPlate.fill.foreground?.value, 0xFF336699);
    expect(pageColorPlate.line.pattern, 0);
    final reflectionSource = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Reflection');
    expect(reflectionSource.reflection.enabled, isFalse);
    final reflectionPlate = reopenedDoc.pages.first.shapes.firstWhere(
      (s) =>
          s.name == '$kLibvisioReflectionShapeNamePrefix${reflectionSource.id}',
    );
    expect(reflectionPlate.fill.foreground?.value, 0xFFCC5533);
    expect(reflectionPlate.fill.foregroundTransparency, closeTo(0.4, 1e-9));
    expect(reflectionPlate.line.pattern, 0);
    final roundJoin =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'RoundJoin');
    expect(roundJoin.line.cap, LineCap.square);
    expect(
      roundJoin.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    final bevelJoin =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'BevelJoin');
    expect(bevelJoin.line.roundingInches, closeTo(0, 1e-12));
    expect(
      bevelJoin.geometries.single.commands.whereType<RelQuadBezTo>(),
      isEmpty,
    );
    expect(
      bevelJoin.geometries.single.commands.whereType<LineTo>().length,
      greaterThan(2),
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'ArcsJoin')
          .geometries
          .single
          .commands
          .whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CompoundThinThick')
          .geometries
          .where((g) => !g.noLine)
          .length,
      2,
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CompoundTriple')
          .geometries
          .where((g) => !g.noLine)
          .length,
      3,
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CompoundThinThick1D')
          .geometries
          .where((g) => !g.noFill)
          .length,
      2,
    );
    expect(
      reopenedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CompoundTriple1D')
          .geometries
          .where((g) => !g.noFill)
          .length,
      3,
    );
    final rounding =
        reopenedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Rounding');
    expect(rounding.line.roundingInches, closeTo(0, 1e-12));
    expect(
      rounding.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    final bevelRoundCap = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'BevelRoundCap');
    expect(bevelRoundCap.line.cap, LineCap.extended);
    expect(
      bevelRoundCap.geometries.single.commands.whereType<LineTo>().length,
      greaterThan(2),
    );
    final filledLineTrans = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'FilledLineTrans');
    expect(filledLineTrans.line.pattern, 0);
    expect(filledLineTrans.line.transparency, closeTo(0, 1e-12));
    expect(filledLineTrans.fill.foreground?.value, 0xFFFFFFFF);
    expect(
      reopenedDoc.pages.first.shapes.any(
        (s) =>
            s.name ==
            '$kLibvisioStrokeRibbonShapeNamePrefix${filledLineTrans.id}',
      ),
      isTrue,
    );
    var tiffDocument = parser.parse(blank);
    final tiffPage = tiffDocument.pages.first;
    const tiffPart = '/visio/media/libreoffice-crosscheck.tiff';
    final tiffBytes = _uncompressedRgbTiff(width: 32, height: 16);
    expect(
      VsdxImage(
        partName: tiffPart,
        bytes: tiffBytes,
        mimeType: 'image/tiff',
      ).rasterForRendering(),
      isNotNull,
    );
    tiffDocument = tiffDocument
        .copyWith(
          images: tiffDocument.images.withImage(
            VsdxImage(
              partName: tiffPart,
              bytes: tiffBytes,
              mimeType: 'image/tiff',
            ),
          ),
        )
        .replacePage(
          0,
          tiffPage.addShape(
            VsdxShapeFactory.picture(
              id: tiffPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: tiffPart,
            ),
          ),
        );
    var gifDocument = parser.parse(blank);
    final gifPage = gifDocument.pages.first;
    const gifPart = '/visio/media/libreoffice-crosscheck.gif';
    final gifImage = raster.Image(width: 32, height: 16);
    for (var y = 0; y < gifImage.height; y++) {
      for (var x = 0; x < gifImage.width; x++) {
        gifImage.setPixelRgba(
          x,
          y,
          x < gifImage.width ~/ 2 ? 255 : 0,
          0,
          x < gifImage.width ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    final gifBytes = raster.encodeGif(gifImage, singleFrame: true);
    gifDocument = gifDocument
        .copyWith(
          images: gifDocument.images.withImage(
            VsdxImage(
              partName: gifPart,
              bytes: gifBytes,
              mimeType: 'image/gif',
            ),
          ),
        )
        .replacePage(
          0,
          gifPage.addShape(
            VsdxShapeFactory.picture(
              id: gifPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: gifPart,
            ),
          ),
        );
    var webpDocument = parser.parse(blank);
    final webpPage = webpDocument.pages.first;
    const webpPart = '/visio/media/libreoffice-crosscheck.webp';
    final webpBytes = _magentaWebp();
    expect(raster.decodeWebP(webpBytes), isNotNull);
    expect(
      VsdxImage(
        partName: webpPart,
        bytes: webpBytes,
        mimeType: 'image/webp',
      ).compressionType,
      isNull,
    );
    webpDocument = webpDocument
        .copyWith(
          images: webpDocument.images.withImage(
            VsdxImage(
              partName: webpPart,
              bytes: webpBytes,
              mimeType: 'image/webp',
            ),
          ),
        )
        .replacePage(
          0,
          webpPage.addShape(
            VsdxShapeFactory.picture(
              id: webpPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 1.5,
              imagePartName: webpPart,
            ),
          ),
        );
    var dibDocument = parser.parse(blank);
    final dibPage = dibDocument.pages.first;
    const dibPart = '/visio/media/libreoffice-crosscheck.dib';
    final dibBytes = _magentaDib();
    expect(raster.decodeImage(dibBytes), isNull);
    expect(
      VsdxImage(
        partName: dibPart,
        bytes: dibBytes,
        mimeType: 'image/bmp',
      ).looksLikeHeaderlessDib,
      isTrue,
    );
    dibDocument = dibDocument
        .copyWith(
          images: dibDocument.images.withImage(
            VsdxImage(
              partName: dibPart,
              bytes: dibBytes,
              mimeType: 'image/bmp',
            ),
          ),
        )
        .replacePage(
          0,
          dibPage.addShape(
            VsdxShapeFactory.picture(
              id: dibPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 1.5,
              imagePartName: dibPart,
            ),
          ),
        );
    var icoDocument = parser.parse(blank);
    final icoPage = icoDocument.pages.first;
    const icoPart = '/visio/media/libreoffice-crosscheck.ico';
    final icoBytes = _magentaIco();
    expect(raster.decodeIco(icoBytes), isNotNull);
    expect(
      VsdxImage(
        partName: icoPart,
        bytes: icoBytes,
        mimeType: 'image/x-icon',
      ).compressionType,
      isNull,
    );
    icoDocument = icoDocument
        .copyWith(
          images: icoDocument.images.withImage(
            VsdxImage(
              partName: icoPart,
              bytes: icoBytes,
              mimeType: 'image/x-icon',
            ),
          ),
        )
        .replacePage(
          0,
          icoPage.addShape(
            VsdxShapeFactory.picture(
              id: icoPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 1.5,
              imagePartName: icoPart,
            ),
          ),
        );
    var emfDocument = parser.parse(blank);
    final emfPage = emfDocument.pages.first;
    const emfPart = '/visio/media/libreoffice-crosscheck.emf';
    final emfBytes = _rgbDibEmf(width: 32, height: 16);
    expect(
      VsdxImage(
        partName: emfPart,
        bytes: emfBytes,
        mimeType: 'image/x-emf',
      ).rasterForRendering(),
      isNotNull,
    );
    emfDocument = emfDocument
        .copyWith(
          images: emfDocument.images.withImage(
            VsdxImage(
              partName: emfPart,
              bytes: emfBytes,
              mimeType: 'image/x-emf',
            ),
          ),
        )
        .replacePage(
          0,
          emfPage.addShape(
            VsdxShapeFactory.picture(
              id: emfPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: emfPart,
            ),
          ),
        );
    var vectorEmfDocument = parser.parse(blank);
    final vectorEmfPage = vectorEmfDocument.pages.first;
    const vectorEmfPart = '/visio/media/libreoffice-crosscheck-vector.emf';
    final vectorEmfBytes = _vectorMagentaEmf();
    expect(extractEmfEmbeddedBitmap(vectorEmfBytes), isNull);
    vectorEmfDocument = vectorEmfDocument
        .copyWith(
          images: vectorEmfDocument.images.withImage(
            VsdxImage(
              partName: vectorEmfPart,
              bytes: vectorEmfBytes,
              mimeType: 'image/x-emf',
            ),
          ),
        )
        .replacePage(
          0,
          vectorEmfPage.addShape(
            VsdxShapeFactory.picture(
              id: vectorEmfPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 1.5,
              imagePartName: vectorEmfPart,
            ),
          ),
        );
    var textEmfDocument = parser.parse(blank);
    final textEmfPage = textEmfDocument.pages.first;
    const textEmfPart = '/visio/media/libreoffice-crosscheck-text.emf';
    final textEmfBytes = _magentaTextEmf();
    expect(extractEmfEmbeddedBitmap(textEmfBytes), isNull);
    expect(
      parseEmfDrawing(textEmfBytes)!.ops.whereType<MetafileTextOp>().single.text,
      'HI',
    );
    textEmfDocument = textEmfDocument
        .copyWith(
          images: textEmfDocument.images.withImage(
            VsdxImage(
              partName: textEmfPart,
              bytes: textEmfBytes,
              mimeType: 'image/x-emf',
            ),
          ),
        )
        .replacePage(
          0,
          textEmfPage.addShape(
            VsdxShapeFactory.picture(
              id: textEmfPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 1.5,
              imagePartName: textEmfPart,
            ),
          ),
        );
    var hatchEmfDocument = parser.parse(blank);
    final hatchEmfPage = hatchEmfDocument.pages.first;
    const hatchEmfPart = '/visio/media/libreoffice-crosscheck-hatch.emf';
    final hatchEmfBytes = _hatchGreenEmf();
    expect(extractEmfEmbeddedBitmap(hatchEmfBytes), isNull);
    expect(
      parseEmfDrawing(hatchEmfBytes)!
          .ops
          .whereType<MetafilePathOp>()
          .any((op) => op.fillHatch == 4),
      isTrue,
    );
    hatchEmfDocument = hatchEmfDocument
        .copyWith(
          images: hatchEmfDocument.images.withImage(
            VsdxImage(
              partName: hatchEmfPart,
              bytes: hatchEmfBytes,
              mimeType: 'image/x-emf',
            ),
          ),
        )
        .replacePage(
          0,
          hatchEmfPage.addShape(
            VsdxShapeFactory.picture(
              id: hatchEmfPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 1.5,
              imagePartName: hatchEmfPart,
            ),
          ),
        );
    var oleDocument = parser.parse(blank);
    final olePage = oleDocument.pages.first;
    const olePart = '/visio/media/libreoffice-crosscheck.bin';
    final oleBytes = wrapOlePresentation(_rgbDibWmf(width: 32, height: 16));
    expect(extractOlePresentationMetafile(oleBytes), isNotNull);
    oleDocument = oleDocument
        .copyWith(
          images: oleDocument.images.withImage(
            VsdxImage(
              partName: olePart,
              bytes: oleBytes,
              mimeType: 'object/ole',
            ),
          ),
        )
        .replacePage(
          0,
          olePage.addShape(
            VsdxShapeFactory.picture(
              id: olePage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: olePart,
            ).copyWith(foreignType: 'Object'),
          ),
        );
    var flipDocument = parser.parse(blank);
    final flipPage = flipDocument.pages.first;
    const flipPart = '/visio/media/libreoffice-flipy.png';
    final flipImage = raster.Image(width: 32, height: 32);
    for (var y = 0; y < flipImage.height; y++) {
      for (var x = 0; x < flipImage.width; x++) {
        flipImage.setPixelRgba(
          x,
          y,
          y < flipImage.height ~/ 2 ? 255 : 0,
          0,
          y < flipImage.height ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    flipDocument = flipDocument
        .copyWith(
          images: flipDocument.images.withImage(
            VsdxImage(
              partName: flipPart,
              bytes: raster.encodePng(flipImage),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          flipPage.addShape(
            VsdxShapeFactory.picture(
              id: flipPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: flipPart,
            ).copyWith(flipY: true),
          ),
        );
    var geometryImageDocument = parser.parse(blank);
    final geometryImagePage = geometryImageDocument.pages.first;
    const geometryImagePart = '/visio/media/libreoffice-geometry-image.png';
    final geometryImage = raster.Image(width: 32, height: 32);
    for (var y = 0; y < geometryImage.height; y++) {
      for (var x = 0; x < geometryImage.width; x++) {
        geometryImage.setPixelRgba(
          x,
          y,
          x < geometryImage.width ~/ 2 ? 255 : 0,
          0,
          x < geometryImage.width ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    geometryImageDocument = geometryImageDocument
        .copyWith(
          images: geometryImageDocument.images.withImage(
            VsdxImage(
              partName: geometryImagePart,
              bytes: raster.encodePng(geometryImage),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          geometryImagePage.addShape(
            VsdxShapeFactory.picture(
              id: geometryImagePage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: geometryImagePart,
            ).copyWith(
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  noLine: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(2, 0),
                    LineTo(1, 2),
                    LineTo(0, 0),
                  ],
                ),
              ],
            ),
          ),
        );
    var textFlipDocument = parser.parse(blank);
    final textFlipPage = textFlipDocument.pages.first;
    VsdxRichText flipText(String text) => VsdxRichText(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: const VsdxCharStyle(
                fontFamily: 'Arial',
                fontSizeInches: 0.5,
                color: VsdxColor(0xFF000000),
              ),
              paraStyle: const VsdxParaStyle(
                horizontalAlign: VsdxHorzAlign.left,
              ),
            ),
          ],
          textBlock: const VsdxTextBlock(
            verticalAlign: VsdxVertAlign.top,
            marginLeftInches: 0.1,
            marginRightInches: 0.1,
            marginTopInches: 0.1,
            marginBottomInches: 0.1,
          ),
        );
    final flipXText = VsdxShapeFactory.rectangle(
      id: textFlipPage.nextFreeShapeId(),
      pinX: 2,
      pinY: 6,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('LEFT'),
    );
    final flipYText = VsdxShapeFactory.rectangle(
      id: flipXText.id + 1,
      pinX: 2,
      pinY: 3,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipY: true,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('TOP'),
    );
    final nestedText = VsdxShapeFactory.rectangle(
      id: flipYText.id + 2,
      pinX: 1.5,
      pinY: 0.75,
      width: 3,
      height: 1.5,
    ).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('LEFT'),
    );
    final flipXGroup = VsdxShapeFactory.rectangle(
      id: flipYText.id + 1,
      pinX: 6,
      pinY: 6,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      shapeKind: VsdxShapeKind.group,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      children: <VsdxShape>[nestedText],
    );
    textFlipDocument = textFlipDocument.replacePage(
      0,
      textFlipPage.copyWith(
        shapes: <VsdxShape>[flipXText, flipYText, flipXGroup],
      ),
    );
    var glassDocument = parser.parse(blank);
    final glassPage = glassDocument.pages.first;
    var grad3Document = parser.parse(blank);
    final grad3Page = grad3Document.pages.first;
    grad3Document = grad3Document.replacePage(
      0,
      grad3Page.addShape(
        VsdxShapeFactory.rectangle(
          id: grad3Page.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 1.4,
          name: 'Grad3',
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
                VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    glassDocument = glassDocument.replacePage(
      0,
      glassPage.addShape(
        VsdxShapeFactory.rectangle(
          id: glassPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GlassBox',
          fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).withGlassEffect(true),
      ),
    );
    var opacityDocument = parser.parse(blank);
    final opacityPage = opacityDocument.pages.first;
    opacityDocument = opacityDocument.replacePage(
      0,
      opacityPage.addShape(
        VsdxShapeFactory.rectangle(
          id: opacityPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'OpacityBox',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).withShapeOpacity(0.5),
      ),
    );
    var labelBorderDocument = parser.parse(blank);
    final labelBorderPage = labelBorderDocument.pages.first;
    labelBorderDocument = labelBorderDocument.replacePage(
      0,
      labelBorderPage.addShape(
        VsdxShapeFactory.rectangle(
          id: labelBorderPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'LabelBorderBox',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
              ),
            )
            .withLabelBorderColor(const VsdxColor(0xFF1565C0)),
      ),
    );
    var labelBorderEdgeDocument = parser.parse(blank);
    final labelBorderEdgePage = labelBorderEdgeDocument.pages.first;
    labelBorderEdgeDocument = labelBorderEdgeDocument.replacePage(
      0,
      labelBorderEdgePage.addShape(
        VsdxShapeFactory.line(
          id: labelBorderEdgePage.nextFreeShapeId(),
          ax: 1,
          ay: 7,
          bx: 7,
          by: 1,
          name: 'LabelBorderEdge',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.02,
          ),
        ).copyWith(
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(6, 0),
                LineTo(6, -6),
              ],
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'MMMM',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.5,
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ).withLabelBorderColor(const VsdxColor(0xFF1565C0)),
      ),
    );
    var labelPaddingDocument = parser.parse(blank);
    final labelPaddingPage = labelPaddingDocument.pages.first;
    labelPaddingDocument = labelPaddingDocument.replacePage(
      0,
      labelPaddingPage.addShape(
        VsdxShapeFactory.rectangle(
          id: labelPaddingPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'LabelPaddingBox',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'H',
                    charStyle: VsdxCharStyle(
                      fontSizeInches: 0.4,
                      color: VsdxColor.black,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  marginLeftInches: 0,
                  marginRightInches: 0,
                  marginTopInches: 0,
                  marginBottomInches: 0,
                  verticalAlign: VsdxVertAlign.middle,
                ),
              ),
            )
            .withLabelPadding(const VsdxLabelPadding(left: 48)),
      ),
    );
    var labelPaddingEdgeDocument = parser.parse(blank);
    final labelPaddingEdgePage = labelPaddingEdgeDocument.pages.first;
    labelPaddingEdgeDocument = labelPaddingEdgeDocument.replacePage(
      0,
      labelPaddingEdgePage.addShape(
        VsdxShapeFactory.line(
          id: labelPaddingEdgePage.nextFreeShapeId(),
          ax: 1,
          ay: 7,
          bx: 7,
          by: 1,
          name: 'LabelPaddingEdge',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.02,
          ),
        )
            .copyWith(
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(6, 0),
                    LineTo(6, -6),
                  ],
                ),
              ],
              richText: const VsdxRichText(
                textBlock: VsdxTextBlock(
                  marginLeftInches: 0,
                  marginRightInches: 0,
                  marginTopInches: 0,
                  marginBottomInches: 0,
                  verticalAlign: VsdxVertAlign.middle,
                  backgroundColor: VsdxColor(0xFFFF00FF),
                ),
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'M',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.5,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            )
            .withLabelPadding(const VsdxLabelPadding.all(48))
            .withLabelBorderColor(const VsdxColor(0xFF1565C0)),
      ),
    );
    var wordWrapDocument = parser.parse(blank);
    final wordWrapPage = wordWrapDocument.pages.first;
    wordWrapDocument = wordWrapDocument.replacePage(
      0,
      wordWrapPage.addShape(
        VsdxShapeFactory.rectangle(
          id: wordWrapPage.nextFreeShapeId(),
          pinX: 3.0,
          pinY: 5.5,
          width: 0.8,
          height: 2,
          name: 'WordWrapBox',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'NO WRAP NO WRAP NO WRAP NO WRAP',
                    charStyle: VsdxCharStyle(
                      fontSizeInches: 0.22,
                      color: VsdxColor.black,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.middle,
                ),
              ),
            )
            .withWordWrap(false),
      ),
    );
    var wordWrapEdgeDocument = parser.parse(blank);
    final wordWrapEdgePage = wordWrapEdgeDocument.pages.first;
    final wordWrapEdgeStub = VsdxShapeFactory.line(
      id: wordWrapEdgePage.nextFreeShapeId(),
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'WordWrapEdge',
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.02,
      ),
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(6, 0),
            LineTo(6, -6),
          ],
        ),
      ],
    );
    wordWrapEdgeDocument = wordWrapEdgeDocument.replacePage(
      0,
      wordWrapEdgePage.addShape(wordWrapEdgeStub),
    );
    final wordWrapEdgeLocal = wordWrapEdgeDocument.pages.first.pageToLocalDeep(
      wordWrapEdgeStub.id,
      const Offset2D(7, 7),
    );
    wordWrapEdgeDocument = wordWrapEdgeDocument.replacePage(
      0,
      wordWrapEdgeDocument.pages.first.copyWith(
        shapes: <VsdxShape>[
          wordWrapEdgeStub
              .copyWith(
                richText: VsdxRichText(
                  textBlock: VsdxTextBlock(
                    pinXInches: wordWrapEdgeLocal.x,
                    pinYInches: wordWrapEdgeLocal.y,
                    locPinXInches: 0.4,
                    locPinYInches: 0.8,
                    widthInches: 0.8,
                    heightInches: 1.6,
                    marginLeftInches: 0,
                    marginRightInches: 0,
                    marginTopInches: 0,
                    marginBottomInches: 0,
                    verticalAlign: VsdxVertAlign.middle,
                  ),
                  runs: const <VsdxTextRun>[
                    VsdxTextRun(
                      text: 'MMMM',
                      charStyle: VsdxCharStyle(
                        fontFamily: 'Arial',
                        fontSizeInches: 0.35,
                        color: VsdxColor(0xFFFF0000),
                      ),
                      paraStyle: VsdxParaStyle(
                        horizontalAlign: VsdxHorzAlign.left,
                      ),
                    ),
                    VsdxTextRun(
                      text: 'MMMM',
                      charStyle: VsdxCharStyle(
                        fontFamily: 'Arial',
                        fontSizeInches: 0.35,
                        color: VsdxColor(0xFF00FF00),
                      ),
                      paraStyle: VsdxParaStyle(
                        horizontalAlign: VsdxHorzAlign.left,
                      ),
                    ),
                  ],
                ),
              )
              .withWordWrap(false),
        ],
      ),
    );
    var wordWrapTabDocument = parser.parse(blank);
    final wordWrapTabPage = wordWrapTabDocument.pages.first;
    wordWrapTabDocument = wordWrapTabDocument.replacePage(
      0,
      wordWrapTabPage.addShape(
        VsdxShapeFactory.rectangle(
          id: wordWrapTabPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.2,
          height: 0.8,
          name: 'WordWrapTab',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              richText: const VsdxRichText(
                tabSets: <VsdxTabSet>[
                  VsdxTabSet(
                    ix: 0,
                    stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
                  ),
                ],
                textBlock: VsdxTextBlock(
                  marginLeftInches: 0,
                  marginRightInches: 0,
                  marginTopInches: 0,
                  marginBottomInches: 0,
                  verticalAlign: VsdxVertAlign.middle,
                ),
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'A\t',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.35,
                      color: VsdxColor(0xFFFF0000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.left,
                    ),
                  ),
                  VsdxTextRun(
                    text: 'B',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.35,
                      color: VsdxColor(0xFF00FF00),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.left,
                    ),
                  ),
                ],
              ),
            )
            .withWordWrap(false),
      ),
    );
    var overlineTabDocument = parser.parse(blank);
    final overlineTabPage = overlineTabDocument.pages.first;
    overlineTabDocument = overlineTabDocument.replacePage(
      0,
      overlineTabPage.addShape(
        VsdxShapeFactory.rectangle(
          id: overlineTabPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3.2,
          height: 0.8,
          name: 'OverlineTab',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          richText: const VsdxRichText(
            tabSets: <VsdxTabSet>[
              VsdxTabSet(
                ix: 0,
                stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
              ),
            ],
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\t',
                tabIndices: <int>[0],
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  overline: true,
                  color: VsdxColor(0xFFFF0000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
              VsdxTextRun(
                text: 'B',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  overline: true,
                  color: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var overlineFieldDocument = parser.parse(blank);
    overlineFieldDocument = overlineFieldDocument.replacePage(
      0,
      overlineFieldDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: overlineFieldDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 1.4,
          name: 'OverlineField',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: '42',
          fields: const <VsdxFieldRow>[
            VsdxFieldRow(
              ix: 0,
              value: '42',
              valueFormula: 'PAGENUMBER()',
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '42',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.5,
                  overline: true,
                  color: VsdxColor(0xFFFF00FF),
                ),
                fieldSpans: <VsdxFieldSpan>[
                  VsdxFieldSpan(start: 0, length: 2, ix: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var doubleStrikeDocument = parser.parse(blank);
    doubleStrikeDocument = doubleStrikeDocument.replacePage(
      0,
      doubleStrikeDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: doubleStrikeDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 1.4,
          name: 'DoubleStrike',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'IIII',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'IIII',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.5,
                  doubleStrikethrough: true,
                  color: VsdxColor(0xFFFF00FF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var doubleStrikeFieldDocument = parser.parse(blank);
    doubleStrikeFieldDocument = doubleStrikeFieldDocument.replacePage(
      0,
      doubleStrikeFieldDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: doubleStrikeFieldDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 1.4,
          name: 'DoubleStrikeField',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: '42',
          fields: const <VsdxFieldRow>[
            VsdxFieldRow(
              ix: 0,
              value: '42',
              valueFormula: 'PAGENUMBER()',
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '42',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.5,
                  doubleStrikethrough: true,
                  color: VsdxColor(0xFFFF00FF),
                ),
                fieldSpans: <VsdxFieldSpan>[
                  VsdxFieldSpan(start: 0, length: 2, ix: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var langIdRtlFieldDocument = parser.parse(blank);
    langIdRtlFieldDocument = langIdRtlFieldDocument.replacePage(
      0,
      langIdRtlFieldDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: langIdRtlFieldDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 1.4,
          name: 'LangIdRtlField',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: '42',
          fields: const <VsdxFieldRow>[
            VsdxFieldRow(
              ix: 0,
              value: '42',
              valueFormula: 'PAGENUMBER()',
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '42',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.5,
                  color: VsdxColor(0xFFFF00FF),
                  langId: 'ar-SA',
                ),
                fieldSpans: <VsdxFieldSpan>[
                  VsdxFieldSpan(start: 0, length: 2, ix: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var solidSpLineDocument = parser.parse(blank);
    solidSpLineDocument = solidSpLineDocument.replacePage(
      0,
      solidSpLineDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: solidSpLineDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 2.4,
          name: 'SolidSpLine',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'AAA\nBBB\nCCC',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'AAA\nBBB\nCCC',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(lineSpacingSolid: true),
              ),
            ],
          ),
        ),
      ),
    );
    var geometrySoftDocument = parser.parse(blank);
    final geometrySoftPage = geometrySoftDocument.pages.first;
    geometrySoftDocument = geometrySoftDocument.replacePage(
      0,
      geometrySoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: geometrySoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GeometrySoft',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var geometrySoftThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final geometrySoftThemePage = geometrySoftThemeDocument.pages.first;
    geometrySoftThemeDocument = geometrySoftThemeDocument.replacePage(
      0,
      geometrySoftThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: geometrySoftThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GeometrySoftTheme',
          fill: const VsdxFill(
            themeForegroundIndex: ThemeSlot.accent6,
            pattern: 1,
          ),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var gradientSoftDocument = parser.parse(blank);
    final gradientSoftPage = gradientSoftDocument.pages.first;
    gradientSoftDocument = gradientSoftDocument.replacePage(
      0,
      gradientSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: gradientSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GradientSoft',
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  color: VsdxColor(0xFFFF0000),
                ),
                VsdxGradientStop(
                  position: 1,
                  color: VsdxColor(0xFF0000FF),
                ),
              ],
            ),
          ),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var gradientSoftThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final gradientSoftThemePage = gradientSoftThemeDocument.pages.first;
    gradientSoftThemeDocument = gradientSoftThemeDocument.replacePage(
      0,
      gradientSoftThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: gradientSoftThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GradientSoftTheme',
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  themeColorIndex: ThemeSlot.accent6,
                ),
                VsdxGradientStop(
                  position: 1,
                  themeColorIndex: ThemeSlot.accent1,
                ),
              ],
            ),
          ),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var hatchSoftDocument = parser.parse(blank);
    final hatchSoftPage = hatchSoftDocument.pages.first;
    hatchSoftDocument = hatchSoftDocument.replacePage(
      0,
      hatchSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: hatchSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'HatchSoft',
          fill: const VsdxFill(
            foreground: VsdxColor(0xFFFF0000),
            background: VsdxColor(0xFF0000FF),
            pattern: 6,
          ),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var hatchSoftThemeBgDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final hatchSoftThemeBgPage = hatchSoftThemeBgDocument.pages.first;
    hatchSoftThemeBgDocument = hatchSoftThemeBgDocument.replacePage(
      0,
      hatchSoftThemeBgPage.addShape(
        VsdxShapeFactory.rectangle(
          id: hatchSoftThemeBgPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'HatchSoftThemeBg',
          fill: const VsdxFill(
            foreground: VsdxColor(0xFFFF0000),
            themeBackgroundIndex: ThemeSlot.accent6,
            pattern: 6,
          ),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var hatchSoftThemeFgDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final hatchSoftThemeFgPage = hatchSoftThemeFgDocument.pages.first;
    hatchSoftThemeFgDocument = hatchSoftThemeFgDocument.replacePage(
      0,
      hatchSoftThemeFgPage.addShape(
        VsdxShapeFactory.rectangle(
          id: hatchSoftThemeFgPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'HatchSoftThemeFg',
          fill: const VsdxFill(
            themeForegroundIndex: ThemeSlot.accent2,
            background: VsdxColor(0xFF0000FF),
            pattern: 6,
          ),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.2),
        ),
      ),
    );
    var strokeSoftDocument = parser.parse(blank);
    final strokeSoftPage = strokeSoftDocument.pages.first;
    strokeSoftDocument = strokeSoftDocument.replacePage(
      0,
      strokeSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: strokeSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'StrokeSoft',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.14,
            softEdgesInches: 0.18,
          ),
        ),
      ),
    );
    var strokeSoftThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final strokeSoftThemePage = strokeSoftThemeDocument.pages.first;
    strokeSoftThemeDocument = strokeSoftThemeDocument.replacePage(
      0,
      strokeSoftThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: strokeSoftThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'StrokeSoftTheme',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            themeColorIndex: ThemeSlot.accent6,
            weightInches: 0.14,
            softEdgesInches: 0.18,
          ),
        ),
      ),
    );
    var dashSoftDocument = parser.parse(blank);
    final dashSoftPage = dashSoftDocument.pages.first;
    dashSoftDocument = dashSoftDocument.replacePage(
      0,
      dashSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: dashSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 2,
          height: 1.2,
          name: 'DashSoft',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.16,
            pattern: 2,
            softEdgesInches: 0.12,
          ),
        ),
      ),
    );
    var fillStrokeSoftDocument = parser.parse(blank);
    final fillStrokeSoftPage = fillStrokeSoftDocument.pages.first;
    fillStrokeSoftDocument = fillStrokeSoftDocument.replacePage(
      0,
      fillStrokeSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: fillStrokeSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'FillStrokeSoft',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.22,
            softEdgesInches: 0.1,
          ),
        ),
      ),
    );
    var fillStrokeSoftArrowDocument = parser.parse(blank);
    final fillStrokeSoftArrowPage = fillStrokeSoftArrowDocument.pages.first;
    fillStrokeSoftArrowDocument = fillStrokeSoftArrowDocument.replacePage(
      0,
      fillStrokeSoftArrowPage.addShape(
        VsdxShapeFactory.rectangle(
          id: fillStrokeSoftArrowPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'FillStrokeSoftArrows',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.22,
            softEdgesInches: 0.1,
            beginArrow: 4,
            endArrow: 13,
          ),
        ),
      ),
    );
    var fillDashSoftDocument = parser.parse(blank);
    final fillDashSoftPage = fillDashSoftDocument.pages.first;
    fillDashSoftDocument = fillDashSoftDocument.replacePage(
      0,
      fillDashSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: fillDashSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 2,
          height: 1.2,
          name: 'FillDashSoft',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.16,
            pattern: 2,
            softEdgesInches: 0.12,
          ),
        ),
      ),
    );
    var gradStrokeSoftDocument = parser.parse(blank);
    final gradStrokeSoftPage = gradStrokeSoftDocument.pages.first;
    gradStrokeSoftDocument = gradStrokeSoftDocument.replacePage(
      0,
      gradStrokeSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: gradStrokeSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GradStrokeSoft',
          fill: const VsdxFill(
            pattern: 1,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  color: VsdxColor(0xFFFF0000),
                ),
                VsdxGradientStop(
                  position: 1,
                  color: VsdxColor(0xFF0000FF),
                ),
              ],
            ),
          ),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.22,
            softEdgesInches: 0.1,
          ),
        ),
      ),
    );
    var compoundSoftDocument = parser.parse(blank);
    final compoundSoftPage = compoundSoftDocument.pages.first;
    compoundSoftDocument = compoundSoftDocument.replacePage(
      0,
      compoundSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: compoundSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'CompoundSoft',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.28,
            compoundType: 1,
            softEdgesInches: 0.1,
          ),
        ),
      ),
    );
    var lineGradSoftDocument = parser.parse(blank);
    final lineGradSoftPage = lineGradSoftDocument.pages.first;
    lineGradSoftDocument = lineGradSoftDocument.replacePage(
      0,
      lineGradSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: lineGradSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'LineGradSoft',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.22,
            softEdgesInches: 0.1,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  color: VsdxColor(0xFFFF0000),
                ),
                VsdxGradientStop(
                  position: 1,
                  color: VsdxColor(0xFF0000FF),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    var lineGradThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final lineGradThemePage = lineGradThemeDocument.pages.first;
    lineGradThemeDocument = lineGradThemeDocument.replacePage(
      0,
      lineGradThemePage.addShape(
        VsdxShape(
          id: lineGradThemePage.nextFreeShapeId(),
          name: 'LineGradTheme',
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 0.24,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0.12),
                LineTo(3, 0.12),
              ],
            ),
          ],
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            pattern: 1,
            weightInches: 0.18,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  themeColorIndex: ThemeSlot.accent6,
                ),
                VsdxGradientStop(
                  position: 1,
                  themeColorIndex: ThemeSlot.accent1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    var roundSoftDocument = parser.parse(blank);
    final roundSoftPage = roundSoftDocument.pages.first;
    roundSoftDocument = roundSoftDocument.replacePage(
      0,
      roundSoftPage.addShape(
        VsdxShapeFactory.rectangle(
          id: roundSoftPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'RoundSoft',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            pattern: 0,
            roundingInches: 0.85,
            softEdgesInches: 0.08,
          ),
        ),
      ),
    );
    var shadowBlurDocument = parser.parse(blank);
    final shadowBlurPage = shadowBlurDocument.pages.first;
    shadowBlurDocument = shadowBlurDocument.replacePage(
      0,
      shadowBlurPage.addShape(
        VsdxShapeFactory.rectangle(
          id: shadowBlurPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ShadowBlur',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            color: VsdxColor(0xFF000000),
            offsetXInches: 0.4,
            offsetYInches: -0.35,
            blurInches: 0.15,
            transparency: 0.35,
          ),
        ),
      ),
    );
    var shadowThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final shadowThemePage = shadowThemeDocument.pages.first;
    shadowThemeDocument = shadowThemeDocument.replacePage(
      0,
      shadowThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: shadowThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ShadowThemePng',
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            themeColorIndex: ThemeSlot.accent6,
            offsetXInches: 0.4,
            offsetYInches: -0.35,
            blurInches: 0.15,
            transparency: 0.35,
          ),
        ),
      ),
    );
    var shadowTransThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final shadowTransThemePage = shadowTransThemeDocument.pages.first;
    shadowTransThemeDocument = shadowTransThemeDocument.replacePage(
      0,
      shadowTransThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: shadowTransThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ShadowTransTheme',
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            themeColorIndex: ThemeSlot.accent6,
            offsetXInches: 0.4,
            offsetYInches: -0.35,
            blurInches: 0,
            transparency: 0.7,
          ),
        ),
      ),
    );
    var glowPngDocument = parser.parse(blank);
    final glowPngPage = glowPngDocument.pages.first;
    glowPngDocument = glowPngDocument.replacePage(
      0,
      glowPngPage.addShape(
        VsdxShapeFactory.rectangle(
          id: glowPngPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GlowPng',
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.04,
          ),
        ).copyWith(
          glow: const VsdxGlow(
            color: VsdxColor(0xFF00CC66),
            sizeInches: 0.28,
            transparency: 0.15,
          ),
        ),
      ),
    );
    var glowNolineDocument = parser.parse(blank);
    final glowNolinePage = glowNolineDocument.pages.first;
    glowNolineDocument = glowNolineDocument.replacePage(
      0,
      glowNolinePage.addShape(
        VsdxShapeFactory.rectangle(
          id: glowNolinePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GlowNoLinePng',
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          glow: const VsdxGlow(
            color: VsdxColor(0xFF00CC66),
            sizeInches: 0.28,
            transparency: 0.15,
          ),
        ),
      ),
    );
    var glowThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final glowThemePage = glowThemeDocument.pages.first;
    glowThemeDocument = glowThemeDocument.replacePage(
      0,
      glowThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: glowThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GlowThemePng',
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          glow: const VsdxGlow(
            themeColorIndex: ThemeSlot.accent6,
            sizeInches: 0.28,
            transparency: 0.15,
          ),
        ),
      ),
    );
    var glowSplineThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final glowSplineThemePage = glowSplineThemeDocument.pages.first;
    glowSplineThemeDocument = glowSplineThemeDocument.replacePage(
      0,
      glowSplineThemePage.addShape(
        VsdxShape(
          id: glowSplineThemePage.nextFreeShapeId(),
          name: 'GlowSplineTheme',
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          // A spline body has no SoftEdges silhouette, so Glow cannot become
          // a Gaussian PNG and falls back to the LineWeight halo.
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                SplineStart(x: 0.75, y: 1.6, a: 0, b: 0, c: 3),
                SplineKnot(x: 2.25, y: 1.6, knot: 1),
                LineTo(3, 0),
                LineTo(0, 0),
              ],
            ),
          ],
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          glow: const VsdxGlow(
            themeColorIndex: ThemeSlot.accent6,
            sizeInches: 0.28,
            transparency: 0.15,
          ),
        ),
      ),
    );
    var charTransThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final charTransThemePage = charTransThemeDocument.pages.first;
    charTransThemeDocument = charTransThemeDocument.replacePage(
      0,
      charTransThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: charTransThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'CharTransTheme',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'H',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'H',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  themeColorIndex: ThemeSlot.accent6,
                  transparency: 0.7,
                  fontSizeInches: 1.1,
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
          ),
        ),
      ),
    );
    var fillTransThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final fillTransThemePage = fillTransThemeDocument.pages.first;
    fillTransThemeDocument = fillTransThemeDocument.replacePage(
      0,
      fillTransThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: fillTransThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'FillTransTheme',
          fill: const VsdxFill(
            themeForegroundIndex: ThemeSlot.accent6,
            foregroundTransparency: 0.7,
            pattern: 1,
          ),
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    var fillThemeOpaqueDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final fillThemeOpaquePage = fillThemeOpaqueDocument.pages.first;
    fillThemeOpaqueDocument = fillThemeOpaqueDocument.replacePage(
      0,
      fillThemeOpaquePage.addShape(
        VsdxShapeFactory.rectangle(
          id: fillThemeOpaquePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'FillThemeOpaque',
          fill: const VsdxFill(
            themeForegroundIndex: ThemeSlot.accent6,
            pattern: 1,
          ),
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    var highlightMixedDocument = parser.parse(blank);
    final highlightMixedPage = highlightMixedDocument.pages.first;
    highlightMixedDocument = highlightMixedDocument.replacePage(
      0,
      highlightMixedPage.addShape(
        VsdxShapeFactory.rectangle(
          id: highlightMixedPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4,
          height: 2,
          name: 'HighlightMixed',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'MM',
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
            runs: [
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var highlightMixedNlDocument = parser.parse(blank);
    final highlightMixedNlPage = highlightMixedNlDocument.pages.first;
    highlightMixedNlDocument = highlightMixedNlDocument.replacePage(
      0,
      highlightMixedNlPage.addShape(
        VsdxShapeFactory.rectangle(
          id: highlightMixedNlPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4,
          height: 2.4,
          name: 'HighlightMixedNl',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'M\nM',
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
            runs: [
              VsdxTextRun(
                text: 'M\n',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var highlightMixedWrapDocument = parser.parse(blank);
    final highlightMixedWrapPage = highlightMixedWrapDocument.pages.first;
    highlightMixedWrapDocument = highlightMixedWrapDocument.replacePage(
      0,
      highlightMixedWrapPage.addShape(
        VsdxShapeFactory.rectangle(
          id: highlightMixedWrapPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.5,
          height: 2.4,
          name: 'HighlightMixedWrap',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'MMMM MMMM',
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
            runs: [
              VsdxTextRun(
                text: 'MMMM ',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'MMMM',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var highlightMixedTabDocument = parser.parse(blank);
    final highlightMixedTabPage = highlightMixedTabDocument.pages.first;
    highlightMixedTabDocument = highlightMixedTabDocument.replacePage(
      0,
      highlightMixedTabPage.addShape(
        VsdxShapeFactory.rectangle(
          id: highlightMixedTabPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4,
          height: 2,
          name: 'HighlightMixedTab',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'M\tM',
          richText: const VsdxRichText(
            tabSets: <VsdxTabSet>[
              VsdxTabSet(
                ix: 0,
                stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
              ),
            ],
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
            runs: [
              VsdxTextRun(
                text: 'M\t',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var textDirectionDocument = parser.parse(blank);
    final textDirectionPage = textDirectionDocument.pages.first;
    textDirectionDocument = textDirectionDocument.replacePage(
      0,
      textDirectionPage.addShape(
        VsdxShapeFactory.rectangle(
          id: textDirectionPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 0.8,
          name: 'TextDirection',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        )
            .copyWith(
              text: 'MMMM',
              richText: const VsdxRichText(
                textBlock: VsdxTextBlock(
                  marginLeftInches: 0,
                  marginRightInches: 0,
                  marginTopInches: 0,
                  marginBottomInches: 0,
                  verticalAlign: VsdxVertAlign.middle,
                  textDirection: 1,
                  backgroundColor: VsdxColor(0xFFFF00FF),
                ),
                runs: [
                  VsdxTextRun(
                    text: 'MMMM',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.5,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            )
            .withWordWrap(false),
      ),
    );
    var textDirectionEdgeDocument = parser.parse(blank);
    final textDirectionEdgePage = textDirectionEdgeDocument.pages.first;
    textDirectionEdgeDocument = textDirectionEdgeDocument.replacePage(
      0,
      textDirectionEdgePage.addShape(
        VsdxShapeFactory.line(
          id: textDirectionEdgePage.nextFreeShapeId(),
          ax: 1,
          ay: 7,
          bx: 7,
          by: 1,
          name: 'TextDirectionEdge',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.02,
          ),
        ).copyWith(
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(6, 0),
                LineTo(6, -6),
              ],
            ),
          ],
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
              textDirection: 1,
              backgroundColor: VsdxColor(0xFFFF00FF),
            ),
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'MMMM',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.5,
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var highlightMixedVertDocument = parser.parse(blank);
    final highlightMixedVertPage = highlightMixedVertDocument.pages.first;
    highlightMixedVertDocument = highlightMixedVertDocument.replacePage(
      0,
      highlightMixedVertPage.addShape(
        VsdxShapeFactory.rectangle(
          id: highlightMixedVertPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4,
          height: 2,
          name: 'HighlightMixedVert',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'MM',
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
              textDirection: 1,
            ),
            runs: [
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var glowStrokeDocument = parser.parse(blank);
    final glowStrokePage = glowStrokeDocument.pages.first;
    glowStrokeDocument = glowStrokeDocument.replacePage(
      0,
      glowStrokePage.addShape(
        VsdxShapeFactory.rectangle(
          id: glowStrokePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GlowStrokePng',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.04,
          ),
        ).copyWith(
          glow: const VsdxGlow(
            color: VsdxColor(0xFF00CC66),
            sizeInches: 0.28,
            transparency: 0.15,
          ),
        ),
      ),
    );
    var glowStroke1dDocument = parser.parse(blank);
    final glowStroke1dPage = glowStroke1dDocument.pages.first;
    glowStroke1dDocument = glowStroke1dDocument.replacePage(
      0,
      glowStroke1dPage.addShape(
        VsdxShapeFactory.line(
          id: glowStroke1dPage.nextFreeShapeId(),
          ax: 2,
          ay: 5.5,
          bx: 6.5,
          by: 5.5,
          name: 'GlowStroke1d',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.08,
          ),
        ).copyWith(
          glow: const VsdxGlow(
            color: VsdxColor(0xFFFF00FF),
            sizeInches: 0.16,
            transparency: 0.2,
          ),
        ),
      ),
    );
    var glowStrokeCompoundDocument = parser.parse(blank);
    final glowStrokeCompoundPage = glowStrokeCompoundDocument.pages.first;
    glowStrokeCompoundDocument = glowStrokeCompoundDocument.replacePage(
      0,
      glowStrokeCompoundPage.addShape(
        VsdxShapeFactory.rectangle(
          id: glowStrokeCompoundPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'GlowStrokeCompound',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.14,
            compoundType: 1,
          ),
        ).copyWith(
          glow: const VsdxGlow(
            color: VsdxColor(0xFF00CC66),
            sizeInches: 0.28,
            transparency: 0.15,
          ),
        ),
      ),
    );
    var glowPictureDocument = parser.parse(blank);
    final glowPicturePage = glowPictureDocument.pages.first;
    const glowPicturePart = '/visio/media/glow_picture.png';
    glowPictureDocument = glowPictureDocument
        .copyWith(
          images: glowPictureDocument.images.withImage(
            VsdxImage(
              partName: glowPicturePart,
              bytes: _solidPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          glowPicturePage.addShape(
            VsdxShapeFactory.picture(
              id: glowPicturePage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: glowPicturePart,
              name: 'GlowPicturePng',
            ).copyWith(
              glow: const VsdxGlow(
                color: VsdxColor(0xFF00CC66),
                sizeInches: 0.28,
                transparency: 0.15,
              ),
            ),
          ),
        );
    var shadowPictureDocument = parser.parse(blank);
    final shadowPicturePage = shadowPictureDocument.pages.first;
    const shadowPicturePart = '/visio/media/shadow_picture.png';
    shadowPictureDocument = shadowPictureDocument
        .copyWith(
          images: shadowPictureDocument.images.withImage(
            VsdxImage(
              partName: shadowPicturePart,
              bytes: _solidPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          shadowPicturePage.addShape(
            VsdxShapeFactory.picture(
              id: shadowPicturePage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: shadowPicturePart,
              name: 'ShadowPicturePng',
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: true,
                color: VsdxColor(0xFF000000),
                offsetXInches: 0.4,
                offsetYInches: -0.35,
                blurInches: 0.15,
                transparency: 0.35,
              ),
            ),
          ),
        );
    var reflectionStrokeDocument = parser.parse(blank);
    final reflectionStrokePage = reflectionStrokeDocument.pages.first;
    reflectionStrokeDocument = reflectionStrokeDocument.replacePage(
      0,
      reflectionStrokePage.addShape(
        VsdxShapeFactory.rectangle(
          id: reflectionStrokePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ReflectionStrokePng',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.06,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.6,
            distanceInches: 0.06,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final reflectionThemePage = reflectionThemeDocument.pages.first;
    reflectionThemeDocument = reflectionThemeDocument.replacePage(
      0,
      reflectionThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: reflectionThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ReflectionThemePng',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            themeColorIndex: ThemeSlot.accent6,
            weightInches: 0.06,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.6,
            distanceInches: 0.06,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionStroke1dDocument = parser.parse(blank);
    final reflectionStroke1dPage = reflectionStroke1dDocument.pages.first;
    reflectionStroke1dDocument = reflectionStroke1dDocument.replacePage(
      0,
      reflectionStroke1dPage.addShape(
        VsdxShapeFactory.line(
          id: reflectionStroke1dPage.nextFreeShapeId(),
          ax: 2,
          ay: 5.5,
          bx: 6.5,
          by: 5.5,
          name: 'ReflectionStroke1d',
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.14,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 1,
            distanceInches: 0.1,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionStrokeFlipDocument = parser.parse(blank);
    final reflectionStrokeFlipPage = reflectionStrokeFlipDocument.pages.first;
    reflectionStrokeFlipDocument = reflectionStrokeFlipDocument.replacePage(
      0,
      reflectionStrokeFlipPage.addShape(
        VsdxShapeFactory.rectangle(
          id: reflectionStrokeFlipPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ReflectionStrokeFlipY',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.06,
          ),
        ).copyWith(
          flipY: true,
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.6,
            distanceInches: 0.06,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionStrokeDashDocument = parser.parse(blank);
    final reflectionStrokeDashPage = reflectionStrokeDashDocument.pages.first;
    reflectionStrokeDashDocument = reflectionStrokeDashDocument.replacePage(
      0,
      reflectionStrokeDashPage.addShape(
        VsdxShapeFactory.rectangle(
          id: reflectionStrokeDashPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ReflectionStrokeDash',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.08,
            pattern: 2,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.6,
            distanceInches: 0.06,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionStrokeCompoundDocument = parser.parse(blank);
    final reflectionStrokeCompoundPage =
        reflectionStrokeCompoundDocument.pages.first;
    reflectionStrokeCompoundDocument =
        reflectionStrokeCompoundDocument.replacePage(
      0,
      reflectionStrokeCompoundPage.addShape(
        VsdxShapeFactory.rectangle(
          id: reflectionStrokeCompoundPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ReflectionStrokeCompound',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.14,
            compoundType: 1,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.6,
            distanceInches: 0.06,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionStrokeLineGradDocument = parser.parse(blank);
    final reflectionStrokeLineGradPage =
        reflectionStrokeLineGradDocument.pages.first;
    reflectionStrokeLineGradDocument =
        reflectionStrokeLineGradDocument.replacePage(
      0,
      reflectionStrokeLineGradPage.addShape(
        VsdxShapeFactory.rectangle(
          id: reflectionStrokeLineGradPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'ReflectionStrokeLineGrad',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.16,
            gradient: VsdxGradient(
              stops: <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  color: VsdxColor(0xFFFF0000),
                ),
                VsdxGradientStop(
                  position: 1,
                  color: VsdxColor(0xFF0000FF),
                ),
              ],
            ),
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.6,
            distanceInches: 0.06,
            transparency: 0.15,
            blurInches: 0,
          ),
        ),
      ),
    );
    var reflectionPictureDocument = parser.parse(blank);
    final reflectionPicturePage = reflectionPictureDocument.pages.first;
    const reflectionPicturePart = '/visio/media/reflection_picture.png';
    reflectionPictureDocument = reflectionPictureDocument
        .copyWith(
          images: reflectionPictureDocument.images.withImage(
            VsdxImage(
              partName: reflectionPicturePart,
              bytes: _splitPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          reflectionPicturePage.addShape(
            VsdxShapeFactory.picture(
              id: reflectionPicturePage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: reflectionPicturePart,
              name: 'ReflectionPicturePng',
            ).copyWith(
              reflection: const VsdxReflection(
                enabled: true,
                sizeInches: 0.5,
                distanceInches: 0.08,
                transparency: 0.25,
                blurInches: 0,
              ),
            ),
          ),
        );
    var reflectionPictureFlipDocument = parser.parse(blank);
    final reflectionPictureFlipPage = reflectionPictureFlipDocument.pages.first;
    const reflectionPictureFlipPart =
        '/visio/media/reflection_picture_flipy.png';
    reflectionPictureFlipDocument = reflectionPictureFlipDocument
        .copyWith(
          images: reflectionPictureFlipDocument.images.withImage(
            VsdxImage(
              partName: reflectionPictureFlipPart,
              bytes: _splitPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          reflectionPictureFlipPage.addShape(
            VsdxShapeFactory.picture(
              id: reflectionPictureFlipPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: reflectionPictureFlipPart,
              name: 'ReflectionPictureFlipY',
            ).copyWith(
              flipY: true,
              reflection: const VsdxReflection(
                enabled: true,
                sizeInches: 0.5,
                distanceInches: 0.08,
                transparency: 0.25,
                blurInches: 0,
              ),
            ),
          ),
        );
    var cropReflectionDocument = parser.parse(blank);
    final cropReflectionPage = cropReflectionDocument.pages.first;
    const cropReflectionPart = '/visio/media/crop_reflection.png';
    cropReflectionDocument = cropReflectionDocument
        .copyWith(
          images: cropReflectionDocument.images.withImage(
            VsdxImage(
              partName: cropReflectionPart,
              bytes: _leftRightPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          cropReflectionPage.addShape(
            VsdxShapeFactory.picture(
              id: cropReflectionPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: cropReflectionPart,
              name: 'CropReflectionPicture',
            ).copyWith(
              reflection: const VsdxReflection(
                enabled: true,
                sizeInches: 0.5,
                distanceInches: 0.08,
                transparency: 0.25,
                blurInches: 0,
              ),
              imgOffsetXInches: -3,
              imgOffsetYInches: 0,
              imgWidthInches: 6,
              imgHeightInches: 2,
            ),
          ),
        );
    var cropSoftDocument = parser.parse(blank);
    final cropSoftPage = cropSoftDocument.pages.first;
    const cropSoftPart = '/visio/media/crop_soft.png';
    cropSoftDocument = cropSoftDocument
        .copyWith(
          images: cropSoftDocument.images.withImage(
            VsdxImage(
              partName: cropSoftPart,
              bytes: _leftRightPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          cropSoftPage.addShape(
            VsdxShapeFactory.picture(
              id: cropSoftPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: cropSoftPart,
              name: 'CropSoftPicture',
            ).copyWith(
              line: const VsdxLine(pattern: 0, softEdgesInches: 0.18),
              imgOffsetXInches: -3,
              imgOffsetYInches: 0,
              imgWidthInches: 6,
              imgHeightInches: 2,
            ),
          ),
        );
    var cropPictureDocument = parser.parse(blank);
    final cropPicturePage = cropPictureDocument.pages.first;
    const cropPicturePart = '/visio/media/crop.png';
    cropPictureDocument = cropPictureDocument
        .copyWith(
          images: cropPictureDocument.images.withImage(
            VsdxImage(
              partName: cropPicturePart,
              bytes: _leftRightPng(),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          cropPicturePage.addShape(
            VsdxShapeFactory.picture(
              id: cropPicturePage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 3,
              height: 2,
              imagePartName: cropPicturePart,
              name: 'CropPicture',
            ).copyWith(
              imgOffsetXInches: -3,
              imgOffsetYInches: 0,
              imgWidthInches: 6,
              imgHeightInches: 2,
            ),
          ),
        );
    var obliqueShadowDocument = parser.parse(blank);
    final obliqueShadowPage = obliqueShadowDocument.pages.first;
    obliqueShadowDocument = obliqueShadowDocument.replacePage(
      0,
      obliqueShadowPage
          .copyWith(
            pageSheet: obliqueShadowPage.pageSheet.copyWith(
              shadowType: 1,
              shadowObliqueAngle: 0.6,
              shadowScaleFactor: 1.0,
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: obliqueShadowPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 2,
              height: 2,
              name: 'ObliqueShadowBox',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFEEEEEE),
                pattern: 1,
              ),
              line: const VsdxLine(pattern: 0),
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: true,
                color: VsdxColor(0xFF000000),
                offsetXInches: 0.3,
                offsetYInches: -0.3,
                blurInches: 0,
                transparency: 0,
              ),
            ),
          ),
    );
    var obliqueShadowThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final obliqueShadowThemePage = obliqueShadowThemeDocument.pages.first;
    obliqueShadowThemeDocument = obliqueShadowThemeDocument.replacePage(
      0,
      obliqueShadowThemePage
          .copyWith(
            pageSheet: obliqueShadowThemePage.pageSheet.copyWith(
              shadowType: 1,
              shadowObliqueAngle: 0.6,
              shadowScaleFactor: 1.0,
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: obliqueShadowThemePage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 2,
              height: 2,
              name: 'ObliqueShadowTheme',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFEEEEEE),
                pattern: 1,
              ),
              line: const VsdxLine(pattern: 0),
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: true,
                themeColorIndex: ThemeSlot.accent6,
                offsetXInches: 0.3,
                offsetYInches: -0.3,
                blurInches: 0,
                transparency: 0,
              ),
            ),
          ),
    );
    var obliqueShadowBlurDocument = parser.parse(blank);
    final obliqueShadowBlurPage = obliqueShadowBlurDocument.pages.first;
    obliqueShadowBlurDocument = obliqueShadowBlurDocument.replacePage(
      0,
      obliqueShadowBlurPage
          .copyWith(
            pageSheet: obliqueShadowBlurPage.pageSheet.copyWith(
              shadowType: 1,
              shadowObliqueAngle: 0.6,
              shadowScaleFactor: 1.0,
            ),
          )
          .addShape(
            VsdxShapeFactory.rectangle(
              id: obliqueShadowBlurPage.nextFreeShapeId(),
              pinX: 4.25,
              pinY: 5.5,
              width: 2,
              height: 2,
              name: 'ObliqueShadowBlur',
              fill: const VsdxFill(
                foreground: VsdxColor(0xFFEEEEEE),
                pattern: 1,
              ),
              line: const VsdxLine(pattern: 0),
            ).copyWith(
              shadow: const VsdxShadow(
                enabled: true,
                color: VsdxColor(0xFF000000),
                offsetXInches: 0.3,
                offsetYInches: -0.3,
                blurInches: 0.12,
                transparency: 0,
              ),
            ),
          ),
    );
    var curvedTextDocument = parser.parse(blank);
    final curvedTextPage = curvedTextDocument.pages.first;
    curvedTextDocument = curvedTextDocument.replacePage(
      0,
      curvedTextPage.addShape(
        VsdxShapeFactory.rectangle(
          id: curvedTextPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.0,
          height: 3.0,
          name: 'CurvedText',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ARC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var curvedTextFlipDocument = parser.parse(blank);
    curvedTextFlipDocument = curvedTextFlipDocument.replacePage(
      0,
      curvedTextFlipDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: curvedTextFlipDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.0,
          height: 3.0,
          name: 'CurvedTextFlipY',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).copyWith(flipY: true).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ARC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var curvedTextTabDocument = parser.parse(blank);
    curvedTextTabDocument = curvedTextTabDocument.replacePage(
      0,
      curvedTextTabDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: curvedTextTabDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.0,
          height: 3.0,
          name: 'CurvedTextTab',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                tabSets: <VsdxTabSet>[
                  VsdxTabSet(
                    ix: 0,
                    stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
                  ),
                ],
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'A\tC',
                    tabIndices: <int>[0],
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var curvedTextOverlineDocument = parser.parse(blank);
    curvedTextOverlineDocument = curvedTextOverlineDocument.replacePage(
      0,
      curvedTextOverlineDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: curvedTextOverlineDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.0,
          height: 3.0,
          name: 'CurvedTextOverline',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ARC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      overline: true,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var curvedTextHighlightDocument = parser.parse(blank);
    curvedTextHighlightDocument = curvedTextHighlightDocument.replacePage(
      0,
      curvedTextHighlightDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: curvedTextHighlightDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.0,
          height: 3.0,
          name: 'CurvedTextHighlight',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'A',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                      highlight: VsdxColor(0xFFFF00FF),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                  VsdxTextRun(
                    text: 'RC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                      highlight: VsdxColor(0xFF00FF00),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var curvedTextBulletDocument = parser.parse(blank);
    curvedTextBulletDocument = curvedTextBulletDocument.replacePage(
      0,
      curvedTextBulletDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: curvedTextBulletDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 1.0,
          height: 3.0,
          name: 'CurvedTextBullet',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ARC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFFFF00FF),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                      bullet: 3,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var shapeInsideDocument = parser.parse(blank);
    final shapeInsidePage = shapeInsideDocument.pages.first;
    shapeInsideDocument = shapeInsideDocument.replacePage(
      0,
      shapeInsidePage.addShape(
        VsdxShapeFactory.ellipse(
          id: shapeInsidePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 4,
          name: 'ShapeInside',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withShapeInside(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            ),
      ),
    );
    var shapeInsideFlipDocument = parser.parse(blank);
    shapeInsideFlipDocument = shapeInsideFlipDocument.replacePage(
      0,
      shapeInsideFlipDocument.pages.first.addShape(
        VsdxShapeFactory.ellipse(
          id: shapeInsideFlipDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 4,
          name: 'ShapeInsideFlipY',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).copyWith(flipY: true).withShapeInside(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            ),
      ),
    );
    var shapeInsideHighlightDocument = parser.parse(blank);
    shapeInsideHighlightDocument = shapeInsideHighlightDocument.replacePage(
      0,
      shapeInsideHighlightDocument.pages.first.addShape(
        VsdxShapeFactory.ellipse(
          id: shapeInsideHighlightDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 4,
          name: 'ShapeInsideHighlight',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withShapeInside(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'HI ',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFF000000),
                      highlight: VsdxColor(0xFFFF00FF),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                  VsdxTextRun(
                    text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFF000000),
                      highlight: VsdxColor(0xFF00FF00),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            ),
      ),
    );
    var shapeInsideFieldDocument = parser.parse(blank);
    shapeInsideFieldDocument = shapeInsideFieldDocument.replacePage(
      0,
      shapeInsideFieldDocument.pages.first.addShape(
        VsdxShapeFactory.ellipse(
          id: shapeInsideFieldDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 4,
          name: 'ShapeInsideField',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withShapeInside(true).copyWith(
              text: '42 SHAPE INSIDE FLOW ALONG THE ELLIPSE',
              fields: const <VsdxFieldRow>[
                VsdxFieldRow(
                  ix: 0,
                  value: '42',
                  valueFormula: 'PAGENUMBER()',
                ),
              ],
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: '42 SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFFFF00FF),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                    fieldSpans: <VsdxFieldSpan>[
                      VsdxFieldSpan(start: 0, length: 2, ix: 0),
                    ],
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            ),
      ),
    );
    var shapeInsideBulletDocument = parser.parse(blank);
    shapeInsideBulletDocument = shapeInsideBulletDocument.replacePage(
      0,
      shapeInsideBulletDocument.pages.first.addShape(
        VsdxShapeFactory.ellipse(
          id: shapeInsideBulletDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 4,
          name: 'ShapeInsideBullet',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).withShapeInside(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFFFF00FF),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                      bullet: 3,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            ),
      ),
    );
    var bulletFieldDocument = parser.parse(blank);
    bulletFieldDocument = bulletFieldDocument.replacePage(
      0,
      bulletFieldDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: bulletFieldDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 1.6,
          name: 'BulletField',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: '42',
          fields: const <VsdxFieldRow>[
            VsdxFieldRow(
              ix: 0,
              value: '42',
              valueFormula: 'PAGENUMBER()',
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '42',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.45,
                  color: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  bullet: 3,
                  textPosAfterBulletInches: 0.55,
                ),
                fieldSpans: <VsdxFieldSpan>[
                  VsdxFieldSpan(start: 0, length: 2, ix: 0),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    var bulletFontSizeDocument = parser.parse(blank);
    bulletFontSizeDocument = bulletFontSizeDocument.replacePage(
      0,
      bulletFontSizeDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: bulletFontSizeDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 2.0,
          name: 'BulletFontSize',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'A',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.22,
                  color: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  bullet: 3,
                  bulletFontSizeInches: 0.7,
                  textPosAfterBulletInches: 0.4,
                ),
              ),
            ],
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
            ),
          ),
        ),
      ),
    );
    var horzAlignFullDocument = parser.parse(blank);
    horzAlignFullDocument = horzAlignFullDocument.replacePage(
      0,
      horzAlignFullDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: horzAlignFullDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 2.6,
          height: 2.4,
          name: 'HorzAlignFull',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'AA BB CC DD EE FF GG HH',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'AA BB CC DD EE FF GG HH',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.55,
                  color: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.full,
                ),
              ),
            ],
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
            ),
          ),
        ),
      ),
    );
    var defaultTabStopDocument = parser.parse(blank);
    defaultTabStopDocument = defaultTabStopDocument.replacePage(
      0,
      defaultTabStopDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: defaultTabStopDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 6.0,
          height: 1.4,
          name: 'DefaultTabStop',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'A\tB',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\tB',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFFFF00FF),
                ),
              ),
            ],
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
              defaultTabStopInches: 2.0,
            ),
          ),
        ),
      ),
    );
    var mixedScriptDocument = parser.parse(blank);
    mixedScriptDocument = mixedScriptDocument.replacePage(
      0,
      mixedScriptDocument.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: mixedScriptDocument.pages.first.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 4.0,
          height: 1.4,
          name: 'MixedScript',
          fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'Hi世界',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Hi世界',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  asianFont: 'Microsoft YaHei',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFFFF00FF),
                ),
              ),
            ],
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
            ),
          ),
        ),
      ),
    );
    var autoRotateDocument = parser.parse(blank);
    final autoRotatePage = autoRotateDocument.pages.first;
    autoRotateDocument = autoRotateDocument.replacePage(
      0,
      autoRotatePage.addShape(
        VsdxShapeFactory.line(
          id: autoRotatePage.nextFreeShapeId(),
          ax: 2,
          ay: 3,
          bx: 6.5,
          by: 7.5,
          name: 'AutoRotate',
          line: const VsdxLine(pattern: 0),
        ).withAutoRotateLabel(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ROTATE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.35,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var textDirectionAutoRotateDocument = parser.parse(blank);
    final textDirectionAutoRotatePage =
        textDirectionAutoRotateDocument.pages.first;
    textDirectionAutoRotateDocument =
        textDirectionAutoRotateDocument.replacePage(
      0,
      textDirectionAutoRotatePage.addShape(
        VsdxShapeFactory.line(
          id: textDirectionAutoRotatePage.nextFreeShapeId(),
          ax: 2,
          ay: 3,
          bx: 6.5,
          by: 7.5,
          name: 'TextDirectionAutoRotate',
          line: const VsdxLine(pattern: 0),
        ).withAutoRotateLabel(true).copyWith(
              richText: const VsdxRichText(
                textBlock: VsdxTextBlock(
                  marginLeftInches: 0,
                  marginRightInches: 0,
                  marginTopInches: 0,
                  marginBottomInches: 0,
                  verticalAlign: VsdxVertAlign.middle,
                  textDirection: 1,
                  backgroundColor: VsdxColor(0xFFFF00FF),
                ),
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'MMMM',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.35,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
    var edgeLabelDocument = parser.parse(blank);
    final edgeLabelPage = edgeLabelDocument.pages.first;
    edgeLabelDocument = edgeLabelDocument.replacePage(
      0,
      edgeLabelPage.addShape(
        VsdxShapeFactory.line(
          id: edgeLabelPage.nextFreeShapeId(),
          ax: 1,
          ay: 7,
          bx: 7,
          by: 1,
          name: 'EdgeLabel',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.02,
          ),
        ).copyWith(
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(6, 0),
                LineTo(6, -6),
              ],
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'MMM',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFF000000),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var edgeLabelWideDocument = parser.parse(blank);
    final edgeLabelWidePage = edgeLabelWideDocument.pages.first;
    edgeLabelWideDocument = edgeLabelWideDocument.replacePage(
      0,
      edgeLabelWidePage.addShape(
        VsdxShapeFactory.line(
          id: edgeLabelWidePage.nextFreeShapeId(),
          ax: 1,
          ay: 7,
          bx: 7,
          by: 1,
          name: 'EdgeLabelWide',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.02,
          ),
        ).copyWith(
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(6, 0),
                LineTo(6, -6),
              ],
            ),
          ],
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              widthInches: 6,
              heightInches: 1.2,
            ),
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'MMM',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var highlightMixedEdgeDocument = parser.parse(blank);
    final highlightMixedEdgePage = highlightMixedEdgeDocument.pages.first;
    highlightMixedEdgeDocument = highlightMixedEdgeDocument.replacePage(
      0,
      highlightMixedEdgePage.addShape(
        VsdxShapeFactory.line(
          id: highlightMixedEdgePage.nextFreeShapeId(),
          ax: 1,
          ay: 7,
          bx: 7,
          by: 1,
          name: 'HighlightMixedEdge',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.02,
          ),
        ).copyWith(
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(6, 0),
                LineTo(6, -6),
              ],
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var customDashDocument = parser.parse(blank);
    final customDashPage = customDashDocument.pages.first;
    customDashDocument = customDashDocument.replacePage(
      0,
      customDashPage.addShape(
        VsdxShapeFactory.line(
          id: customDashPage.nextFreeShapeId(),
          ax: 1,
          ay: 5.5,
          bx: 7,
          by: 5.5,
          name: 'CustomDash',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.15,
            pattern: 2,
          ),
        ).withDrawioDashPattern(const <double>[8, 4]),
      ),
    );
    var flowDashDocument = parser.parse(blank);
    final flowDashPage = flowDashDocument.pages.first;
    flowDashDocument = flowDashDocument.replacePage(
      0,
      flowDashPage.addShape(
        VsdxShapeFactory.line(
          id: flowDashPage.nextFreeShapeId(),
          ax: 1,
          ay: 5.5,
          bx: 7,
          by: 5.5,
          name: 'FlowDash',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.04,
            pattern: 1,
          ),
        ).withFlowAnimation(true),
      ),
    );
    var dashArrowDocument = parser.parse(blank);
    final dashArrowPage = dashArrowDocument.pages.first;
    final flowArrowId = dashArrowPage.nextFreeShapeId();
    dashArrowDocument = dashArrowDocument.replacePage(
      0,
      dashArrowPage
          .addShape(
            VsdxShapeFactory.line(
              id: flowArrowId,
              ax: 1,
              ay: 5.5,
              bx: 7,
              by: 5.5,
              name: 'FlowDashArrow',
              line: const VsdxLine(
                color: VsdxColor(0xFF000000),
                weightInches: 0.04,
                pattern: 1,
                endArrow: 4,
                endArrowSizeInches: 0.25,
              ),
            ).withFlowAnimation(true),
          )
          .addShape(
            VsdxShapeFactory.line(
              id: flowArrowId + 1,
              ax: 1,
              ay: 3.5,
              bx: 7,
              by: 3.5,
              name: 'CustomDashArrow',
              line: const VsdxLine(
                color: VsdxColor(0xFF000000),
                weightInches: 0.04,
                pattern: 1,
                endArrow: 4,
                endArrowSizeInches: 0.25,
              ),
            ).withDrawioDashPattern(const <double>[8, 8]),
          ),
    );
    var collapsedDocument = parser.parse(blank);
    var collapsedPage = collapsedDocument.pages.first;
    final foldedId = collapsedPage.nextFreeShapeId();
    final hiddenId = foldedId + 1;
    collapsedPage = collapsedPage
        .addShape(
          VsdxShapeFactory.container(
            id: foldedId,
            pinX: 4.25,
            pinY: 8,
            width: 4,
            height: 3,
            name: 'FoldedBox',
            fill: const VsdxFill(
              foreground: VsdxColor(0xFF1565C0),
              pattern: 1,
            ),
          ),
        )
        .addShape(
          VsdxShapeFactory.rectangle(
            id: hiddenId,
            pinX: 4.25,
            pinY: 7,
            width: 2,
            height: 1,
            name: 'HiddenChild',
            fill: const VsdxFill(
              foreground: VsdxColor(0xFFFF00FF),
              pattern: 1,
            ),
          ),
        );
    collapsedPage = collapsedPage
        .reparentShape(hiddenId, foldedId)
        .updateShapeById(foldedId, (s) => s.fold());
    collapsedDocument = collapsedDocument.replacePage(0, collapsedPage);
    var mergedDocument = parser.parse(blank);
    var mergedPage = mergedDocument.pages.first;
    final tableId = mergedPage.nextFreeShapeId();
    var mergeTable = TableOps.assembleTable(
      tableId: tableId,
      pinX: 4.25,
      pinY: 8,
      width: 4,
      height: 3,
      rows: 2,
      cols: 2,
      name: 'MergeTable',
    );
    mergeTable = mergeTable.copyWith(
      children: <VsdxShape>[
        for (final cell in mergeTable.children)
          TableOps.cellRow(cell) == 0 && TableOps.cellCol(cell) == 1
              ? cell.copyWith(
                  fill: const VsdxFill(
                    foreground: VsdxColor(0xFFFF00FF),
                    pattern: 1,
                  ),
                )
              : cell,
      ],
    );
    mergeTable = TableOps.mergeCells(
      mergeTable,
      row: 0,
      col: 0,
      rowSpan: 1,
      colSpan: 2,
    );
    mergedPage = mergedPage.addShape(mergeTable);
    mergedDocument = mergedDocument.replacePage(0, mergedPage);
    var patternDashTransDocument = parser.parse(blank);
    final patternDashTransPage = patternDashTransDocument.pages.first;
    patternDashTransDocument = patternDashTransDocument.replacePage(
      0,
      patternDashTransPage.addShape(
        VsdxShapeFactory.line(
          id: patternDashTransPage.nextFreeShapeId(),
          ax: 1,
          ay: 5.5,
          bx: 7,
          by: 5.5,
          name: 'PatternDashTrans',
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.15,
            pattern: 2,
            transparency: 0.5,
          ),
        ),
      ),
    );
    var tightMiterDocument = parser.parse(blank);
    final tightMiterPage = tightMiterDocument.pages.first;
    tightMiterDocument = tightMiterDocument.replacePage(
      0,
      tightMiterPage.addShape(
        VsdxShape(
          id: tightMiterPage.nextFreeShapeId(),
          name: 'TightMiter',
          pinX: 4.25,
          pinY: 5.5,
          width: 2,
          height: 2,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(2, 0),
                LineTo(2, 2),
              ],
            ),
          ],
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.2,
            cap: LineCap.square,
            miterLimit: 1,
          ),
        ).withDrawioMiterLimit(1),
      ),
    );
    var longMiterDocument = parser.parse(blank);
    final longMiterPage = longMiterDocument.pages.first;
    longMiterDocument = longMiterDocument.replacePage(
      0,
      longMiterPage.addShape(
        VsdxShape(
          id: longMiterPage.nextFreeShapeId(),
          name: 'LongMiter',
          pinX: 4.25,
          pinY: 5.5,
          width: 4.5,
          height: 2,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0.2, 1.0),
                LineTo(2.5, 1.0),
                LineTo(0.2, 1.45),
              ],
            ),
          ],
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.24,
            cap: LineCap.square,
            miterLimit: 12,
          ),
        ).withDrawioMiterLimit(12),
      ),
    );
    var filledLineTransDocument = parser.parse(blank);
    final filledLineTransPage = filledLineTransDocument.pages.first;
    filledLineTransDocument = filledLineTransDocument.replacePage(
      0,
      filledLineTransPage.addShape(
        VsdxShapeFactory.rectangle(
          id: filledLineTransPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 2,
          height: 1.2,
          name: 'FilledLineTrans',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.2,
            transparency: 0.5,
          ),
        ),
      ),
    );
    var filledLineTransThemeDocument =
        parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final filledLineTransThemePage = filledLineTransThemeDocument.pages.first;
    filledLineTransThemeDocument = filledLineTransThemeDocument.replacePage(
      0,
      filledLineTransThemePage.addShape(
        VsdxShapeFactory.rectangle(
          id: filledLineTransThemePage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'LineTransTheme',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            themeColorIndex: ThemeSlot.accent6,
            weightInches: 0.28,
            transparency: 0.7,
          ),
        ),
      ),
    );
    var filledLineTransCompoundDocument = parser.parse(blank);
    final filledLineTransCompoundPage =
        filledLineTransCompoundDocument.pages.first;
    filledLineTransCompoundDocument =
        filledLineTransCompoundDocument.replacePage(
      0,
      filledLineTransCompoundPage.addShape(
        VsdxShapeFactory.rectangle(
          id: filledLineTransCompoundPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'FilledCompoundTrans',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.28,
            transparency: 0.5,
            compoundType: 1,
          ),
        ),
      ),
    );
    var filledLineTransDashDocument = parser.parse(blank);
    final filledLineTransDashPage = filledLineTransDashDocument.pages.first;
    filledLineTransDashDocument = filledLineTransDashDocument.replacePage(
      0,
      filledLineTransDashPage.addShape(
        VsdxShapeFactory.rectangle(
          id: filledLineTransDashPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'FilledDashTrans',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.22,
            transparency: 0.5,
            pattern: 2,
          ),
        ),
      ),
    );
    var filledLineTransArrowsDocument = parser.parse(blank);
    final filledLineTransArrowsPage = filledLineTransArrowsDocument.pages.first;
    filledLineTransArrowsDocument = filledLineTransArrowsDocument.replacePage(
      0,
      filledLineTransArrowsPage.addShape(
        VsdxShape(
          id: filledLineTransArrowsPage.nextFreeShapeId(),
          name: 'FilledOpenArrows',
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 1.5,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                MoveTo(0.15, 0.3),
                LineTo(2.85, 0.3),
                LineTo(2.85, 1.2),
              ],
            ),
          ],
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.16,
            transparency: 0.5,
            beginArrow: 4,
            endArrow: 13,
            beginArrowSizeInches: 0.28,
            endArrowSizeInches: 0.28,
          ),
        ),
      ),
    );
    var roundCapMiterDocument = parser.parse(blank);
    final roundCapMiterPage = roundCapMiterDocument.pages.first;
    roundCapMiterDocument = roundCapMiterDocument.replacePage(
      0,
      roundCapMiterPage.addShape(
        VsdxShapeFactory.rectangle(
          id: roundCapMiterPage.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 2,
          height: 1.2,
          name: 'RoundCapMiter',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.24,
            cap: LineCap.round,
            join: VsdxLineJoin.miter,
          ),
        ).withDrawioLineJoin(VsdxLineJoin.miter),
      ),
    );
    var fillGradientPattern0Document = parser.parse(blank);
    final fillGradientPattern0Page = fillGradientPattern0Document.pages.first;
    fillGradientPattern0Document = fillGradientPattern0Document.replacePage(
      0,
      fillGradientPattern0Page.addShape(
        VsdxShapeFactory.rectangle(
          id: fillGradientPattern0Page.nextFreeShapeId(),
          pinX: 4.25,
          pinY: 5.5,
          width: 2,
          height: 1.2,
          name: 'GradientNoPattern',
          fill: const VsdxFill(
            pattern: 0,
            gradient: VsdxGradient(
              angleRad: 3.92699,
              stops: [
                VsdxGradientStop(
                  position: 0,
                  color: VsdxColor(0xFF8DC0FF),
                  transparency: 1,
                ),
                VsdxGradientStop(position: 0.2, color: VsdxColor(0xFFACCFFF)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF467DFE)),
              ],
            ),
          ),
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    final inputs = <String, Uint8List>{
      'generated': generated,
      'tiff_foreign_data': writer.write(
        originalBytes: blank,
        edited: tiffDocument,
      ),
      'gif_foreign_data': writer.write(
        originalBytes: blank,
        edited: gifDocument,
      ),
      'webp_foreign_data': writer.write(
        originalBytes: blank,
        edited: webpDocument,
      ),
      'dib_foreign_data': writer.write(
        originalBytes: blank,
        edited: dibDocument,
      ),
      'ico_foreign_data': writer.write(
        originalBytes: blank,
        edited: icoDocument,
      ),
      'emf_foreign_data': writer.write(
        originalBytes: blank,
        edited: emfDocument,
      ),
      'vector_emf_foreign_data': writer.write(
        originalBytes: blank,
        edited: vectorEmfDocument,
      ),
      'text_emf_foreign_data': writer.write(
        originalBytes: blank,
        edited: textEmfDocument,
      ),
      'hatch_emf_foreign_data': writer.write(
        originalBytes: blank,
        edited: hatchEmfDocument,
      ),
      'ole_foreign_data': writer.write(
        originalBytes: blank,
        edited: oleDocument,
      ),
      'flipy_foreign_data': writer.write(
        originalBytes: blank,
        edited: flipDocument,
      ),
      'geometry_foreign_data': writer.write(
        originalBytes: blank,
        edited: geometryImageDocument,
      ),
      'text_flip': writer.write(
        originalBytes: blank,
        edited: textFlipDocument,
      ),
      'glass': writer.write(
        originalBytes: blank,
        edited: glassDocument,
      ),
      'grad3_fill_gradient': writer.write(
        originalBytes: blank,
        edited: grad3Document,
      ),
      'opacity': writer.write(
        originalBytes: blank,
        edited: opacityDocument,
      ),
      'label_border': writer.write(
        originalBytes: blank,
        edited: labelBorderDocument,
      ),
      'label_border_edge': writer.write(
        originalBytes: blank,
        edited: labelBorderEdgeDocument,
      ),
      'label_padding': writer.write(
        originalBytes: blank,
        edited: labelPaddingDocument,
      ),
      'label_padding_edge': writer.write(
        originalBytes: blank,
        edited: labelPaddingEdgeDocument,
      ),
      'word_wrap': writer.write(
        originalBytes: blank,
        edited: wordWrapDocument,
      ),
      'word_wrap_edge': writer.write(
        originalBytes: blank,
        edited: wordWrapEdgeDocument,
      ),
      'word_wrap_tab': writer.write(
        originalBytes: blank,
        edited: wordWrapTabDocument,
      ),
      'overline_tab': writer.write(
        originalBytes: blank,
        edited: overlineTabDocument,
      ),
      'overline_field': writer.write(
        originalBytes: blank,
        edited: overlineFieldDocument,
      ),
      'double_strike': writer.write(
        originalBytes: blank,
        edited: doubleStrikeDocument,
      ),
      'double_strike_field': writer.write(
        originalBytes: blank,
        edited: doubleStrikeFieldDocument,
      ),
      'lang_id_rtl_field': writer.write(
        originalBytes: blank,
        edited: langIdRtlFieldDocument,
      ),
      'solid_spline': writer.write(
        originalBytes: blank,
        edited: solidSpLineDocument,
      ),
      'geometry_soft': writer.write(
        originalBytes: blank,
        edited: geometrySoftDocument,
      ),
      'geometry_soft_theme': writer.write(
        originalBytes: blank,
        edited: geometrySoftThemeDocument,
      ),
      'gradient_soft': writer.write(
        originalBytes: blank,
        edited: gradientSoftDocument,
      ),
      'gradient_soft_theme': writer.write(
        originalBytes: blank,
        edited: gradientSoftThemeDocument,
      ),
      'hatch_soft': writer.write(
        originalBytes: blank,
        edited: hatchSoftDocument,
      ),
      'hatch_soft_theme_bg': writer.write(
        originalBytes: blank,
        edited: hatchSoftThemeBgDocument,
      ),
      'hatch_soft_theme_fg': writer.write(
        originalBytes: blank,
        edited: hatchSoftThemeFgDocument,
      ),
      'stroke_soft': writer.write(
        originalBytes: blank,
        edited: strokeSoftDocument,
      ),
      'stroke_soft_theme': writer.write(
        originalBytes: blank,
        edited: strokeSoftThemeDocument,
      ),
      'dash_soft': writer.write(
        originalBytes: blank,
        edited: dashSoftDocument,
      ),
      'fill_stroke_soft': writer.write(
        originalBytes: blank,
        edited: fillStrokeSoftDocument,
      ),
      'fill_stroke_soft_arrows': writer.write(
        originalBytes: blank,
        edited: fillStrokeSoftArrowDocument,
      ),
      'fill_dash_soft': writer.write(
        originalBytes: blank,
        edited: fillDashSoftDocument,
      ),
      'grad_stroke_soft': writer.write(
        originalBytes: blank,
        edited: gradStrokeSoftDocument,
      ),
      'compound_soft': writer.write(
        originalBytes: blank,
        edited: compoundSoftDocument,
      ),
      'line_grad_soft': writer.write(
        originalBytes: blank,
        edited: lineGradSoftDocument,
      ),
      'line_grad_theme': writer.write(
        originalBytes: blank,
        edited: lineGradThemeDocument,
      ),
      'round_soft': writer.write(
        originalBytes: blank,
        edited: roundSoftDocument,
      ),
      'shadow_blur': writer.write(
        originalBytes: blank,
        edited: shadowBlurDocument,
      ),
      'shadow_theme': writer.write(
        originalBytes: blank,
        edited: shadowThemeDocument,
      ),
      'shadow_trans_theme': writer.write(
        originalBytes: blank,
        edited: shadowTransThemeDocument,
      ),
      'glow_png': writer.write(
        originalBytes: blank,
        edited: glowPngDocument,
      ),
      'glow_noline': writer.write(
        originalBytes: blank,
        edited: glowNolineDocument,
      ),
      'glow_theme': writer.write(
        originalBytes: blank,
        edited: glowThemeDocument,
      ),
      'glow_spline_theme': writer.write(
        originalBytes: blank,
        edited: glowSplineThemeDocument,
      ),
      'char_trans_theme': writer.write(
        originalBytes: blank,
        edited: charTransThemeDocument,
      ),
      'fill_trans_theme': writer.write(
        originalBytes: blank,
        edited: fillTransThemeDocument,
      ),
      'fill_theme_opaque': writer.write(
        originalBytes: blank,
        edited: fillThemeOpaqueDocument,
      ),
      'highlight_mixed': writer.write(
        originalBytes: blank,
        edited: highlightMixedDocument,
      ),
      'highlight_mixed_nl': writer.write(
        originalBytes: blank,
        edited: highlightMixedNlDocument,
      ),
      'highlight_mixed_wrap': writer.write(
        originalBytes: blank,
        edited: highlightMixedWrapDocument,
      ),
      'highlight_mixed_tab': writer.write(
        originalBytes: blank,
        edited: highlightMixedTabDocument,
      ),
      'text_direction': writer.write(
        originalBytes: blank,
        edited: textDirectionDocument,
      ),
      'text_direction_edge': writer.write(
        originalBytes: blank,
        edited: textDirectionEdgeDocument,
      ),
      'highlight_mixed_vert': writer.write(
        originalBytes: blank,
        edited: highlightMixedVertDocument,
      ),
      'glow_stroke': writer.write(
        originalBytes: blank,
        edited: glowStrokeDocument,
      ),
      'glow_stroke_1d': writer.write(
        originalBytes: blank,
        edited: glowStroke1dDocument,
      ),
      'glow_stroke_compound': writer.write(
        originalBytes: blank,
        edited: glowStrokeCompoundDocument,
      ),
      'glow_picture': writer.write(
        originalBytes: blank,
        edited: glowPictureDocument,
      ),
      'shadow_picture': writer.write(
        originalBytes: blank,
        edited: shadowPictureDocument,
      ),
      'reflection_picture': writer.write(
        originalBytes: blank,
        edited: reflectionPictureDocument,
      ),
      'reflection_picture_flipy': writer.write(
        originalBytes: blank,
        edited: reflectionPictureFlipDocument,
      ),
      'crop_reflection': writer.write(
        originalBytes: blank,
        edited: cropReflectionDocument,
      ),
      'crop_soft': writer.write(
        originalBytes: blank,
        edited: cropSoftDocument,
      ),
      'crop_picture': writer.write(
        originalBytes: blank,
        edited: cropPictureDocument,
      ),
      'reflection_stroke': writer.write(
        originalBytes: blank,
        edited: reflectionStrokeDocument,
      ),
      'reflection_theme': writer.write(
        originalBytes: blank,
        edited: reflectionThemeDocument,
      ),
      'reflection_stroke_1d': writer.write(
        originalBytes: blank,
        edited: reflectionStroke1dDocument,
      ),
      'reflection_stroke_flipy': writer.write(
        originalBytes: blank,
        edited: reflectionStrokeFlipDocument,
      ),
      'reflection_stroke_dash': writer.write(
        originalBytes: blank,
        edited: reflectionStrokeDashDocument,
      ),
      'reflection_stroke_compound': writer.write(
        originalBytes: blank,
        edited: reflectionStrokeCompoundDocument,
      ),
      'reflection_stroke_linegrad': writer.write(
        originalBytes: blank,
        edited: reflectionStrokeLineGradDocument,
      ),
      'oblique_shadow': writer.write(
        originalBytes: blank,
        edited: obliqueShadowDocument,
      ),
      'oblique_shadow_theme': writer.write(
        originalBytes: blank,
        edited: obliqueShadowThemeDocument,
      ),
      'oblique_shadow_blur': writer.write(
        originalBytes: blank,
        edited: obliqueShadowBlurDocument,
      ),
      'curved_text': writer.write(
        originalBytes: blank,
        edited: curvedTextDocument,
      ),
      'curved_text_flipy': writer.write(
        originalBytes: blank,
        edited: curvedTextFlipDocument,
      ),
      'curved_text_tab': writer.write(
        originalBytes: blank,
        edited: curvedTextTabDocument,
      ),
      'curved_text_overline': writer.write(
        originalBytes: blank,
        edited: curvedTextOverlineDocument,
      ),
      'curved_text_highlight': writer.write(
        originalBytes: blank,
        edited: curvedTextHighlightDocument,
      ),
      'curved_text_bullet': writer.write(
        originalBytes: blank,
        edited: curvedTextBulletDocument,
      ),
      'shape_inside': writer.write(
        originalBytes: blank,
        edited: shapeInsideDocument,
      ),
      'shape_inside_flipy': writer.write(
        originalBytes: blank,
        edited: shapeInsideFlipDocument,
      ),
      'shape_inside_highlight': writer.write(
        originalBytes: blank,
        edited: shapeInsideHighlightDocument,
      ),
      'shape_inside_field': writer.write(
        originalBytes: blank,
        edited: shapeInsideFieldDocument,
      ),
      'shape_inside_bullet': writer.write(
        originalBytes: blank,
        edited: shapeInsideBulletDocument,
      ),
      'bullet_field': writer.write(
        originalBytes: blank,
        edited: bulletFieldDocument,
      ),
      'bullet_font_size': writer.write(
        originalBytes: blank,
        edited: bulletFontSizeDocument,
      ),
      'mixed_script': writer.write(
        originalBytes: blank,
        edited: mixedScriptDocument,
      ),
      'horz_align_full': writer.write(
        originalBytes: blank,
        edited: horzAlignFullDocument,
      ),
      'default_tab_stop': writer.write(
        originalBytes: blank,
        edited: defaultTabStopDocument,
      ),
      'auto_rotate': writer.write(
        originalBytes: blank,
        edited: autoRotateDocument,
      ),
      'text_direction_auto_rotate': writer.write(
        originalBytes: blank,
        edited: textDirectionAutoRotateDocument,
      ),
      'edge_label': writer.write(
        originalBytes: blank,
        edited: edgeLabelDocument,
      ),
      'edge_label_wide': writer.write(
        originalBytes: blank,
        edited: edgeLabelWideDocument,
      ),
      'highlight_mixed_edge': writer.write(
        originalBytes: blank,
        edited: highlightMixedEdgeDocument,
      ),
      'custom_dash': writer.write(
        originalBytes: blank,
        edited: customDashDocument,
      ),
      'flow_dash': writer.write(
        originalBytes: blank,
        edited: flowDashDocument,
      ),
      'dash_arrows': writer.write(
        originalBytes: blank,
        edited: dashArrowDocument,
      ),
      'collapsed': writer.write(
        originalBytes: blank,
        edited: collapsedDocument,
      ),
      'merged': writer.write(
        originalBytes: blank,
        edited: mergedDocument,
      ),
      'pattern_dash_trans': writer.write(
        originalBytes: blank,
        edited: patternDashTransDocument,
      ),
      'tight_miter': writer.write(
        originalBytes: blank,
        edited: tightMiterDocument,
      ),
      'long_miter': writer.write(
        originalBytes: blank,
        edited: longMiterDocument,
      ),
      'filled_line_trans': writer.write(
        originalBytes: blank,
        edited: filledLineTransDocument,
      ),
      'filled_line_trans_theme': writer.write(
        originalBytes: blank,
        edited: filledLineTransThemeDocument,
      ),
      'filled_line_trans_compound': writer.write(
        originalBytes: blank,
        edited: filledLineTransCompoundDocument,
      ),
      'filled_line_trans_dash': writer.write(
        originalBytes: blank,
        edited: filledLineTransDashDocument,
      ),
      'filled_line_trans_arrows': writer.write(
        originalBytes: blank,
        edited: filledLineTransArrowsDocument,
      ),
      'round_cap_miter': writer.write(
        originalBytes: blank,
        edited: roundCapMiterDocument,
      ),
      'fill_gradient_pattern0': writer.write(
        originalBytes: blank,
        edited: fillGradientPattern0Document,
      ),
    };
    for (final entry in const <(String, String)>[
      ('connectors', 'test/fixtures/test4_connectors.vsdx'),
      ('zh_data', 'test/fixtures/数据治理.vsdx'),
      ('zh_iceberg', 'test/fixtures/人才招聘冰山模型.vsdx'),
    ]) {
      final raw = await File(entry.$2).readAsBytes();
      inputs[entry.$1] =
          writer.write(originalBytes: raw, edited: parser.parse(raw));
    }

    final dir = await Directory.systemTemp.createTemp('vsdx_lo_');
    final profile = Directory('${dir.path}/lo_profile')..createSync();
    try {
      final paths = <String>[];
      for (final entry in inputs.entries) {
        final input = File('${dir.path}/${entry.key}.vsdx');
        await input.writeAsBytes(entry.value);
        paths.add(input.path);
      }
      final result = await Process.run(
        soffice,
        <String>[
          '--headless',
          '--norestore',
          '--nofirststartwizard',
          '-env:UserInstallation=file://${profile.path}',
          '--convert-to',
          'pdf',
          '--outdir',
          dir.path,
          ...paths,
        ],
        workingDirectory: dir.path,
        environment: <String, String>{
          ...Platform.environment,
          // Prefer headless VCL on Linux CI runners.
          'SAL_USE_VCLPLUGIN': 'svp',
        },
      );
      expect(result.exitCode, 0,
          reason: 'soffice stderr: ${result.stderr}\nstdout: ${result.stdout}');

      for (final entry in inputs.entries) {
        final pdf = File('${dir.path}/${entry.key}.pdf');
        expect(pdf.existsSync(), isTrue,
            reason: 'expected ${entry.key}.pdf from soffice; '
                'dir=${dir.listSync().map((e) => e.path).toList()}');
        expect(pdf.lengthSync(), greaterThan(100));
        if (entry.key == 'tiff_foreign_data' ||
            entry.key == 'gif_foreign_data' ||
            entry.key == 'emf_foreign_data' ||
            entry.key == 'ole_foreign_data' ||
            entry.key == 'flipy_foreign_data' ||
            entry.key == 'geometry_foreign_data') {
          if (pdftoppm == null) {
            if (require) {
              fail('pdftoppm is required for raster render checking');
            }
          } else {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '72',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            );
            expect(rendered, isNotNull);
            var redPixels = 0;
            var bluePixels = 0;
            for (final pixel in rendered!) {
              if (pixel.r > 180 && pixel.g < 80 && pixel.b < 80) redPixels++;
              if (pixel.b > 180 && pixel.r < 80 && pixel.g < 80) bluePixels++;
            }
            expect(redPixels, greaterThan(100),
                reason: 'red=$redPixels blue=$bluePixels');
            expect(bluePixels, greaterThan(100),
                reason: 'red=$redPixels blue=$bluePixels');
            if (entry.key == 'flipy_foreign_data') {
              final reopened = parser.parse(entry.value);
              final page = reopened.pages.first;
              final x = (2 / page.widthInches * rendered.width).round();
              final topY = ((page.heightInches - 2.5) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final bottomY = ((page.heightInches - 1.5) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final top = rendered.getPixel(x, topY);
              final bottom = rendered.getPixel(x, bottomY);
              expect(top.b, greaterThan(180),
                  reason: 'LibreOffice FlipY top must be source bottom');
              expect(top.r, lessThan(80));
              expect(bottom.r, greaterThan(180),
                  reason: 'LibreOffice FlipY bottom must be source top');
              expect(bottom.b, lessThan(80));
            }
            if (entry.key == 'geometry_foreign_data') {
              final reopened = parser.parse(entry.value);
              final page = reopened.pages.first;
              // This point is inside the ForeignData rectangle but outside
              // the triangular Geometry. libvisio emits the two as sibling
              // objects, so LibreOffice must still show the bitmap here.
              final x = (1.2 / page.widthInches * rendered.width).round();
              final y = ((page.heightInches - 2.7) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final corner = rendered.getPixel(x, y);
              expect(corner.r, greaterThan(180),
                  reason: 'ForeignData must not be clipped by Geometry');
              expect(corner.g, lessThan(80));
              expect(corner.b, lessThan(80));
            }
          }
        }
        if (entry.key == 'generated' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          );
          expect(rendered, isNotNull);
          var magentaPixels = 0;
          for (final pixel in rendered!) {
            if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(50),
            reason: 'LibreOffice must paint Character Highlight via baked '
                'TextBkgnd; magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'text_flip' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          int darkPixels(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                if (pixel.r < 120 && pixel.g < 120 && pixel.b < 120) count++;
              }
            }
            return count;
          }

          final flipXLeft = darkPixels(0.55, 5.35, 2.0, 6.65);
          final flipXRight = darkPixels(2.0, 5.35, 3.45, 6.65);
          expect(flipXLeft, greaterThan(50));
          expect(flipXLeft, greaterThan(flipXRight * 2),
              reason: 'LibreOffice keeps FlipX text left-aligned and upright');
          final flipYTop = darkPixels(0.55, 3.0, 3.45, 3.7);
          final flipYBottom = darkPixels(0.55, 2.3, 3.45, 3.0);
          expect(flipYTop, greaterThan(50));
          expect(flipYTop, greaterThan(flipYBottom * 2),
              reason: 'LibreOffice keeps FlipY text top-aligned and upright');
          final nestedLeft = darkPixels(4.55, 5.35, 6.0, 6.65);
          final nestedRight = darkPixels(6.0, 5.35, 7.45, 6.65);
          expect(nestedLeft, greaterThan(50));
          expect(nestedLeft, greaterThan(nestedRight * 2),
              reason: 'LibreOffice cancels ancestor-group FlipX for text');
        }
        if (entry.key == 'glass' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          final top = meanLuma(3.25, 6.05, 5.25, 6.4);
          final bottom = meanLuma(3.25, 4.6, 5.25, 4.95);
          expect(
            top,
            greaterThan(bottom + 12),
            reason:
                'LibreOffice must paint the Glass highlight above the fill; '
                'top=$top bottom=$bottom',
          );
        }
        if (entry.key == 'opacity' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var pinkPixels = 0;
          var redPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 200 && pixel.g < 40 && pixel.b < 40) redPixels++;
            if (pixel.r > 180 &&
                pixel.g > 70 &&
                pixel.g < 200 &&
                pixel.b > 70 &&
                pixel.b < 200) {
              pinkPixels++;
            }
          }
          expect(
            pinkPixels,
            greaterThan(redPixels),
            reason: 'LibreOffice must paint FillForegndTrans as see-through '
                'red, not opaque; pink=$pinkPixels red=$redPixels',
          );
        }
        if (entry.key == 'label_border' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          bool isBlueStroke(raster.Pixel pixel) =>
              pixel.b > pixel.r + 30 && pixel.b > pixel.g + 10 && pixel.r < 200;
          int countBlue(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (isBlueStroke(rendered.getPixel(x, y))) count++;
              }
            }
            return count;
          }

          final edge = countBlue(2.68, 4.5, 2.82, 6.5);
          final interior = countBlue(3.4, 5.1, 5.1, 5.9);
          expect(
            edge,
            greaterThan(20),
            reason: 'LibreOffice must paint the Label Border stroke; '
                'edge=$edge interior=$interior',
          );
          expect(
            edge,
            greaterThan(interior * 2),
            reason: 'Label Border must be a frame, not a fill; '
                'edge=$edge interior=$interior',
          );
        }
        if (entry.key == 'label_border_edge') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final source =
              page.shapes.firstWhere((s) => s.name == 'LabelBorderEdge');
          expect(source.labelBorderColor, isNull);
          final plate = page.shapes.firstWhere(isLibvisioLabelBorderPlate);
          expect(plate.line.color?.value, 0xFF1565C0);
          expect(plate.pinX, closeTo(7, 0.35));
          expect(plate.pinY, closeTo(7, 0.35));
          expect(plate.width, lessThan(3));
        }
        if (entry.key == 'label_border_edge' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          bool isBlueStroke(raster.Pixel pixel) =>
              pixel.b > pixel.r + 30 && pixel.b > pixel.g + 10 && pixel.r < 200;
          int countBlue(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                if (isBlueStroke(rendered.getPixel(x, y))) count++;
              }
            }
            return count;
          }

          final elbow = countBlue(6.35, 6.55, 7.65, 7.45);
          final box = countBlue(3.55, 3.55, 4.45, 4.45);
          expect(
            elbow,
            greaterThan(8),
            reason: 'LibreOffice must stroke the Label Border on the route '
                'plate; elbow=$elbow box=$box',
          );
          expect(
            box,
            lessThan(3),
            reason: 'LibreOffice must not stroke the Begin–End box; '
                'elbow=$elbow box=$box',
          );
        }
        if (entry.key == 'label_padding' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          int darkPixels(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                if (pixel.r < 80 && pixel.g < 80 && pixel.b < 80) count++;
              }
            }
            return count;
          }

          final inset = darkPixels(2.80, 5.2, 3.10, 5.8);
          final glyph = darkPixels(3.30, 5.2, 4.40, 5.8);
          expect(
            glyph,
            greaterThan(20),
            reason: 'LibreOffice must paint the padded label; '
                'inset=$inset glyph=$glyph',
          );
          expect(
            glyph,
            greaterThan(inset * 2),
            reason: 'LibreOffice must honour baked LeftMargin as fo:padding; '
                'inset=$inset glyph=$glyph',
          );
        }
        if (entry.key == 'label_padding_edge') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'LabelPaddingEdge');
          expect(source.labelPadding.isZero, isTrue);
          expect(
            source.richText.textBlock.marginLeftInches,
            closeTo(0.5, 1e-6),
          );
          expect(source.richText.textBlock.widthInches, greaterThan(1.0));
          expect(source.richText.textBlock.heightInches, greaterThan(1.0));
          final pin = reopened.pages.first.localToPageDeep(
            source.id,
            Offset2D(
              source.richText.textBlock.pinXInches!,
              source.richText.textBlock.pinYInches!,
            ),
          );
          expect(pin.x, closeTo(7, 0.2));
          expect(pin.y, closeTo(7, 0.2));
          final plate = reopened.pages.first.shapes
              .firstWhere(isLibvisioLabelBorderPlate);
          expect(plate.width, greaterThan(1.0));
          expect(plate.pinX, closeTo(7, 0.35));
        }
        if (entry.key == 'label_padding_edge' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          bool isBlueStroke(raster.Pixel pixel) =>
              pixel.b > pixel.r + 30 && pixel.b > pixel.g + 10 && pixel.r < 200;
          int countBlue(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                if (isBlueStroke(rendered.getPixel(x, y))) count++;
              }
            }
            return count;
          }

          final pad = countBlue(6.20, 6.70, 6.45, 7.30);
          final box = countBlue(3.55, 3.55, 4.45, 4.45);
          expect(
            pad,
            greaterThan(8),
            reason: 'LibreOffice must stroke the padded Label Border away '
                'from the glyphs; pad=$pad box=$box',
          );
          expect(
            box,
            lessThan(3),
            reason: 'LibreOffice must not stroke the Begin–End box; '
                'pad=$pad box=$box',
          );
        }
        if (entry.key == 'word_wrap' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final box = page.shapes.firstWhere((s) => s.name == 'WordWrapBox');
          expect(
            box.richText.textBlock.widthInches,
            greaterThan(0.8),
          );
          int darkPixels(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                if (pixel.r < 80 && pixel.g < 80 && pixel.b < 80) count++;
              }
            }
            return count;
          }

          final overflow = darkPixels(4.2, 5.35, 6.5, 5.65);
          final wrapped = darkPixels(2.7, 4.7, 3.3, 5.1);
          expect(
            overflow,
            greaterThan(20),
            reason: 'LibreOffice must paint the unwrapped line past TxtWidth; '
                'overflow=$overflow wrapped=$wrapped',
          );
          expect(
            overflow,
            greaterThan(wrapped * 2),
            reason: 'Draw must not wrap the baked TxtWidth back into the box; '
                'overflow=$overflow wrapped=$wrapped',
          );
        }
        if (entry.key == 'word_wrap_edge') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'WordWrapEdge');
          expect(source.wordWrap, isTrue);
          expect(source.richText.textBlock.widthInches, greaterThan(1.4));
          final pin = reopened.pages.first.localToPageDeep(
            source.id,
            Offset2D(
              source.richText.textBlock.pinXInches!,
              source.richText.textBlock.pinYInches!,
            ),
          );
          expect(pin.x, closeTo(7, 0.2));
          expect(pin.y, closeTo(7, 0.2));
        }
        if (entry.key == 'word_wrap_edge' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int red, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var red = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40) red++;
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (red: red, lime: lime);
          }

          final first = countWindow(6.45, 6.70, 7.15, 7.30);
          final second = countWindow(7.55, 6.70, 8.40, 7.30);
          final below = countWindow(6.45, 6.10, 8.20, 6.45);
          expect(
            first.red,
            greaterThan(8),
            reason: 'LibreOffice must paint the red run on the route; '
                'firstR=${first.red} firstL=${first.lime}',
          );
          expect(
            second.lime,
            greaterThan(8),
            reason: 'LibreOffice must keep the lime run on the same line; '
                'secondL=${second.lime} belowL=${below.lime}',
          );
          expect(
            second.lime,
            greaterThan(below.lime),
            reason: 'LibreOffice must not wrap the connector label under '
                'the first run; secondL=${second.lime} belowL=${below.lime}',
          );
        }
        if (entry.key == 'word_wrap_tab') {
          final reopened = parser.parse(entry.value);
          final box = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'WordWrapTab');
          expect(box.wordWrap, isTrue);
          expect(box.richText.textBlock.widthInches, greaterThan(2));
        }
        if (entry.key == 'word_wrap_tab' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int red, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var red = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b < 40) red++;
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (red: red, lime: lime);
          }

          // Draw collects Tabs (`style:tab-stops`) but may still use
          // DefaultTabStop for the jump. The bake's job is the unwrapped
          // line: B must stay on the same band, not wrap under A.
          final left = countWindow(3.65, 5.15, 4.15, 5.85);
          final sameLine = countWindow(3.9, 5.15, 6.3, 5.85);
          final wrapped = countWindow(3.65, 4.5, 4.6, 5.05);
          expect(
            left.red,
            greaterThan(10),
            reason: 'LibreOffice must paint red A on the unwrapped line; '
                'leftR=${left.red} leftL=${left.lime} '
                'lineR=${sameLine.red} lineL=${sameLine.lime} '
                'wrapR=${wrapped.red} wrapL=${wrapped.lime}',
          );
          expect(
            sameLine.lime,
            greaterThan(10),
            reason: 'LibreOffice must keep lime B on the same line; '
                'leftR=${left.red} leftL=${left.lime} '
                'lineR=${sameLine.red} lineL=${sameLine.lime} '
                'wrapR=${wrapped.red} wrapL=${wrapped.lime}',
          );
          expect(
            sameLine.lime,
            greaterThan(wrapped.lime),
            reason: 'Draw must not wrap the tab field under A; '
                'lineL=${sameLine.lime} wrapL=${wrapped.lime}',
          );
        }
        if (entry.key == 'overline_tab') {
          final reopened = parser.parse(entry.value);
          final box = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'OverlineTab');
          expect(
            box.richText.runs.every((run) => !run.charStyle.overline),
            isTrue,
          );
          expect(box.richText.plainText, contains('\t'));
          expect(
            box.richText.plainText
                .split('\t')
                .where((part) => part.isNotEmpty)
                .every((part) => part.contains(kLibvisioCombiningOverline)),
            isTrue,
          );
        }
        if (entry.key == 'overline_tab' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int red, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var red = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b < 40) red++;
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (red: red, lime: lime);
          }

          // The 3.2" box is left-aligned from pin 4.25, so A sits near
          // 2.65". Draw may still use DefaultTabStop for the jump.
          // Keep red A and lime B on one band so the combining marks
          // stay on the same line.
          final left = countWindow(2.55, 5.15, 4.3, 5.85);
          final sameLine = countWindow(3.2, 5.15, 6.5, 5.85);
          final wrapped = countWindow(2.55, 4.5, 4.6, 5.05);
          expect(
            left.red,
            greaterThan(8),
            reason: 'LibreOffice must paint overlined red A; '
                'leftR=${left.red} leftL=${left.lime} '
                'lineR=${sameLine.red} lineL=${sameLine.lime} '
                'wrapR=${wrapped.red} wrapL=${wrapped.lime}',
          );
          expect(
            sameLine.lime,
            greaterThan(8),
            reason: 'LibreOffice must keep overlined lime B on the line; '
                'leftR=${left.red} leftL=${left.lime} '
                'lineR=${sameLine.red} lineL=${sameLine.lime} '
                'wrapR=${wrapped.red} wrapL=${wrapped.lime}',
          );
          expect(
            sameLine.lime,
            greaterThan(wrapped.lime),
            reason: 'Draw must not wrap the overlined tab field under A; '
                'lineL=${sameLine.lime} wrapL=${wrapped.lime}',
          );
        }
        if (entry.key == 'overline_field') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'OverlineField');
          expect(shape.richText.runs.single.charStyle.overline, isFalse);
          expect(
            shape.richText.plainText,
            contains(kLibvisioCombiningOverline),
          );
          expect(
            shape.richText.runs.single.fieldSpans.single,
            const VsdxFieldSpan(start: 0, length: 4, ix: 0),
          );
        }
        if (entry.key == 'overline_field' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(12),
            reason: 'LibreOffice must paint the overlined field Value; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'double_strike') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'DoubleStrike');
          expect(shape.richText.runs.single.charStyle.doubleStrikethrough,
              isFalse);
          expect(shape.richText.runs.single.charStyle.strikethrough, isTrue);
          expect(
            shape.richText.plainText,
            contains(kLibvisioCombiningLongStroke),
          );
        }
        if (entry.key == 'double_strike' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(20),
            reason: 'LibreOffice must paint the double-strikethrough overlay; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'double_strike_field') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'DoubleStrikeField');
          expect(shape.richText.runs.single.charStyle.doubleStrikethrough,
              isFalse);
          expect(shape.richText.runs.single.charStyle.strikethrough, isTrue);
          expect(
            shape.richText.plainText,
            contains(kLibvisioCombiningLongStroke),
          );
          expect(
            shape.richText.runs.single.fieldSpans.single,
            const VsdxFieldSpan(start: 0, length: 4, ix: 0),
          );
        }
        if (entry.key == 'double_strike_field' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(12),
            reason: 'LibreOffice must paint the double-strikethrough field; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'lang_id_rtl_field') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'LangIdRtlField');
          expect(
            shape.richText.runs.single.text,
            startsWith(kLibvisioRtlMark),
          );
          expect(
            shape.richText.runs.single.fieldSpans.single,
            const VsdxFieldSpan(start: 1, length: 2, ix: 0),
          );
          expect(shape.fields, isNotEmpty);
        }
        if (entry.key == 'lang_id_rtl_field' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(12),
            reason: 'LibreOffice must paint the LangID RTL field Value; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'solid_spline') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'SolidSpLine');
          expect(
              shape.richText.runs.single.paraStyle.lineSpacingSolid, isFalse);
          expect(
            shape.richText.runs.single.paraStyle.lineSpacingAbsoluteInches,
            closeTo(0.4, 1e-9),
          );
        }
        if (entry.key == 'solid_spline' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var minY = rendered.height;
          var maxY = 0;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
              if (pixel.y < minY) minY = pixel.y;
              if (pixel.y > maxY) maxY = pixel.y;
            }
          }
          expect(
            magentaPixels,
            greaterThan(40),
            reason: 'LibreOffice must paint solid-spaced lines; '
                'magentaPixels=$magentaPixels',
          );
          expect(
            maxY - minY,
            greaterThan(55),
            reason: 'LibreOffice must keep 1× Size leading for SpLine=0; '
                'bboxH=${maxY - minY} magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'geometry_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          double meanRed(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                sum += rendered.getPixel(x, y).r;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          final centre = meanRed(3.9, 5.2, 4.6, 5.8);
          final edge = meanRed(2.75, 5.2, 2.95, 5.8);
          expect(
            centre,
            greaterThan(180),
            reason: 'LibreOffice must paint the SoftEdges fill; '
                'centre=$centre edge=$edge',
          );
          expect(
            edge,
            lessThan(centre - 25),
            reason: 'LibreOffice must paint the feathered PNG edge, not a '
                'hard fill; centre=$centre edge=$edge',
          );
        }
        if (entry.key == 'geometry_soft_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GeometrySoftTheme');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'geometry_soft_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final centre = mean(3.9, 5.2, 4.6, 5.8);
          expect(
            centre.g,
            greaterThan(centre.r + 15),
            reason: 'LibreOffice must paint the Office accent6 SoftEdges PNG, '
                'not an empty hole after FillPattern 0; centreG=${centre.g} '
                'centreR=${centre.r}',
          );
        }
        if (entry.key == 'gradient_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GradientSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
          if (pdftoppm != null) {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '96',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            )!;
            final page = reopened.pages.first;
            ({double r, double b}) meanRb(
              double x0,
              double y0,
              double x1,
              double y1,
            ) {
              final left = (x0 / page.widthInches * rendered.width).round();
              final right = (x1 / page.widthInches * rendered.width).round();
              final top = ((page.heightInches - y1) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final bottom = ((page.heightInches - y0) /
                      page.heightInches *
                      rendered.height)
                  .round();
              var sumR = 0.0;
              var sumB = 0.0;
              var count = 0;
              for (var y = top; y < bottom; y++) {
                for (var x = left; x < right; x++) {
                  final p = rendered.getPixel(x, y);
                  sumR += p.r;
                  sumB += p.b;
                  count++;
                }
              }
              if (count == 0) return (r: 0, b: 0);
              return (r: sumR / count, b: sumB / count);
            }

            final left = meanRb(3.15, 5.3, 3.55, 5.7);
            final right = meanRb(4.95, 5.3, 5.35, 5.7);
            expect(
              left.r,
              greaterThan(right.r + 40),
              reason: 'LibreOffice must paint the baked red-to-blue wash; '
                  'left=$left right=$right',
            );
            expect(
              right.b,
              greaterThan(left.b + 40),
              reason: 'LibreOffice must paint the baked red-to-blue wash; '
                  'left=$left right=$right',
            );
          }
        }
        if (entry.key == 'gradient_soft_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GradientSoftTheme');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
          if (pdftoppm != null) {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '96',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            )!;
            final page = reopened.pages.first;
            ({double r, double g, double b}) meanRgb(
              double x0,
              double y0,
              double x1,
              double y1,
            ) {
              final left = (x0 / page.widthInches * rendered.width).round();
              final right = (x1 / page.widthInches * rendered.width).round();
              final top = ((page.heightInches - y1) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final bottom = ((page.heightInches - y0) /
                      page.heightInches *
                      rendered.height)
                  .round();
              var sumR = 0.0;
              var sumG = 0.0;
              var sumB = 0.0;
              var count = 0;
              for (var y = top; y < bottom; y++) {
                for (var x = left; x < right; x++) {
                  if (x < 0 ||
                      y < 0 ||
                      x >= rendered.width ||
                      y >= rendered.height) {
                    continue;
                  }
                  final p = rendered.getPixel(x, y);
                  sumR += p.r;
                  sumG += p.g;
                  sumB += p.b;
                  count++;
                }
              }
              if (count == 0) return (r: 0, g: 0, b: 0);
              return (r: sumR / count, g: sumG / count, b: sumB / count);
            }

            final left = meanRgb(3.15, 5.3, 3.55, 5.7);
            final right = meanRgb(4.95, 5.3, 5.35, 5.7);
            expect(
              left.g,
              greaterThan(left.r + 8),
              reason: 'LibreOffice must paint the baked accent6-to-accent1 '
                  'FillGradient SoftEdges PNG, not a hard THEMEVAL fill; '
                  'left=$left right=$right',
            );
            expect(
              right.b,
              greaterThan(right.r + 8),
              reason: 'LibreOffice must keep the blue end of the theme wash; '
                  'left=$left right=$right',
            );
          }
        }
        if (entry.key == 'hatch_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'HatchSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
          if (pdftoppm != null) {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '96',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            )!;
            final page = reopened.pages.first;
            final x = (4.25 / page.widthInches * rendered.width).round();
            final y0 = ((page.heightInches - 6.2) /
                    page.heightInches *
                    rendered.height)
                .round();
            final y1 = ((page.heightInches - 4.8) /
                    page.heightInches *
                    rendered.height)
                .round();
            var redInk = 0;
            var blueInk = 0;
            for (var y = y0; y < y1; y++) {
              final p = rendered.getPixel(x, y);
              if (p.r > p.b + 40) redInk++;
              if (p.b > p.r + 40) blueInk++;
            }
            expect(
              redInk,
              greaterThan(2),
              reason: 'LibreOffice must paint baked hatch strokes; '
                  'redInk=$redInk blueInk=$blueInk',
            );
            expect(
              blueInk,
              greaterThan(redInk),
              reason: 'LibreOffice must paint baked hatch background; '
                  'redInk=$redInk blueInk=$blueInk',
            );
          }
        }
        if (entry.key == 'hatch_soft_theme_bg') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'HatchSoftThemeBg');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
          if (pdftoppm != null) {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '96',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            )!;
            final page = reopened.pages.first;
            final x = (4.25 / page.widthInches * rendered.width).round();
            final y0 = ((page.heightInches - 6.2) /
                    page.heightInches *
                    rendered.height)
                .round();
            final y1 = ((page.heightInches - 4.8) /
                    page.heightInches *
                    rendered.height)
                .round();
            var redInk = 0;
            var greenInk = 0;
            for (var y = y0; y < y1; y++) {
              final p = rendered.getPixel(x, y);
              if (p.r > p.g + 40) redInk++;
              if (p.g > p.r + 8 && p.g > p.b) greenInk++;
            }
            expect(
              redInk,
              greaterThan(2),
              reason: 'LibreOffice must paint baked hatch strokes; '
                  'redInk=$redInk greenInk=$greenInk',
            );
            expect(
              greenInk,
              greaterThan(redInk),
              reason: 'LibreOffice must paint the frozen Office accent6 '
                  'hatch background, not a hollow THEMEVAL plate; '
                  'redInk=$redInk greenInk=$greenInk',
            );
          }
        }
        if (entry.key == 'hatch_soft_theme_fg') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'HatchSoftThemeFg');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
          if (pdftoppm != null) {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '96',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            )!;
            final page = reopened.pages.first;
            final x = (4.25 / page.widthInches * rendered.width).round();
            final y0 = ((page.heightInches - 6.2) /
                    page.heightInches *
                    rendered.height)
                .round();
            final y1 = ((page.heightInches - 4.8) /
                    page.heightInches *
                    rendered.height)
                .round();
            var orangeInk = 0;
            var blueInk = 0;
            for (var y = y0; y < y1; y++) {
              final p = rendered.getPixel(x, y);
              if (p.b > p.r + 40) blueInk++;
              if (p.r > p.b + 20 && p.r > p.g) orangeInk++;
            }
            expect(
              orangeInk,
              greaterThan(2),
              reason: 'LibreOffice must paint frozen Office accent2 hatch '
                  'strokes, not a hollow THEMEVAL plate; '
                  'orangeInk=$orangeInk blueInk=$blueInk',
            );
            expect(
              blueInk,
              greaterThan(orangeInk),
              reason: 'LibreOffice must paint baked hatch background; '
                  'orangeInk=$orangeInk blueInk=$blueInk',
            );
          }
        }
        if (entry.key == 'stroke_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'StrokeSoft');
          expect(source.line.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'stroke_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          final interior = meanLuma(3.9, 5.2, 4.6, 5.8);
          final onStroke = meanLuma(2.68, 5.2, 2.82, 5.8);
          expect(
            interior,
            greaterThan(220),
            reason: 'LibreOffice must keep the unfilled interior empty; '
                'interior=$interior onStroke=$onStroke',
          );
          expect(
            onStroke,
            lessThan(200),
            reason: 'LibreOffice must paint the soft stroke ring; '
                'interior=$interior onStroke=$onStroke',
          );
        }
        if (entry.key == 'stroke_soft_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'StrokeSoftTheme');
          expect(source.line.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'stroke_soft_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double luma}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumLuma = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            if (count == 0) {
              return (r: 0.0, g: 0.0, luma: 255.0);
            }
            return (r: sumR / count, g: sumG / count, luma: sumLuma / count);
          }

          final interior = mean(3.9, 5.2, 4.6, 5.8);
          final onStroke = mean(2.68, 5.2, 2.82, 5.8);
          expect(
            interior.luma,
            greaterThan(220),
            reason: 'LibreOffice must keep the unfilled interior empty; '
                'interior=${interior.luma} onStrokeG=${onStroke.g}',
          );
          expect(
            onStroke.g,
            greaterThan(onStroke.r + 8),
            reason: 'LibreOffice must paint the Office accent6 soft stroke; '
                'interior=${interior.luma} onStrokeG=${onStroke.g} '
                'onStrokeR=${onStroke.r}',
          );
        }
        if (entry.key == 'dash_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'DashSoft');
          expect(source.line.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'dash_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // Left edge at x=3.25. Pattern 2 is 0.96" ink / 0.48" gap. The
          // vertical midpoint sits on a dash *end*; 0.48" lower is mid-dash.
          // Bottom-edge local 1.20 sits in the first gap (a solid ring would
          // be ink there).
          final ink = meanLuma(3.22, 4.98, 3.28, 5.06);
          final gap = meanLuma(4.43, 4.88, 4.47, 4.92);
          expect(
            ink,
            lessThan(180),
            reason: 'LibreOffice must paint dash ink; ink=$ink gap=$gap',
          );
          expect(
            gap,
            greaterThan(200),
            reason: 'LibreOffice must keep dash gaps empty, not a solid ring; '
                'ink=$ink gap=$gap',
          );
        }
        if (entry.key == 'fill_stroke_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FillStrokeSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
          expect(
            reopened.pages.first.shapes
                .where(isLibvisioSoftEdgesPlate)
                .single
                .width,
            greaterThan(source.width + 0.05),
          );
        }
        if (entry.key == 'fill_stroke_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 255.0);
            return (r: sumR / count, g: sumG / count);
          }

          final centre = mean(3.9, 5.2, 4.6, 5.8);
          double minLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var darkest = 255.0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < darkest) darkest = luma;
              }
            }
            return darkest;
          }

          final ring = minLuma(2.52, 5.2, 2.78, 5.8);
          expect(
            centre.r,
            greaterThan(180),
            reason: 'LibreOffice must paint the SoftEdges fill; '
                'centre=${centre.r} ring=$ring',
          );
          expect(
            centre.g,
            lessThan(80),
            reason: 'LibreOffice fill must stay red, not a washed plate; '
                'centreG=${centre.g} ring=$ring',
          );
          expect(
            ring,
            lessThan(50),
            reason: 'LibreOffice must paint the feathered black stroke; '
                'centre=${centre.r} ring=$ring',
          );
        }
        if (entry.key == 'fill_stroke_soft_arrows') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FillStrokeSoftArrows');
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 0,
              reason: 'closed arrow cells must not leave a hard native stroke');
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'fill_stroke_soft_arrows' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 255.0);
            return (r: sumR / count, g: sumG / count);
          }

          double minLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var darkest = 255.0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < darkest) darkest = luma;
              }
            }
            return darkest;
          }

          final centre = mean(3.9, 5.2, 4.6, 5.8);
          final ring = minLuma(2.52, 5.2, 2.78, 5.8);
          expect(
            centre.r,
            greaterThan(180),
            reason: 'LibreOffice must paint the SoftEdges fill; '
                'centre=${centre.r} ring=$ring',
          );
          expect(
            ring,
            lessThan(50),
            reason: 'LibreOffice must paint the feathered black stroke; '
                'centre=${centre.r} ring=$ring',
          );
        }
        if (entry.key == 'fill_dash_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FillDashSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'fill_dash_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double luma}) mean(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumLuma = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            if (count == 0) {
              return (r: 0.0, g: 255.0, luma: 255.0);
            }
            return (r: sumR / count, g: sumG / count, luma: sumLuma / count);
          }

          final centre = mean(4.15, 5.40, 4.35, 5.60);
          // Bottom-edge local 1.20 is in a Pattern 2 gap; 0.05" inside the
          // box is still in the inner half of the 0.16" stroke.
          final gap = mean(4.43, 4.93, 4.47, 4.97);
          expect(
            centre.r,
            greaterThan(180),
            reason: 'LibreOffice must keep the red fill; '
                'centreR=${centre.r} gapLuma=${gap.luma}',
          );
          expect(
            gap.r,
            greaterThan(120),
            reason: 'LibreOffice must show the red fill in dash gaps, not a '
                'solid black ring; centreR=${centre.r} gapR=${gap.r} '
                'gapLuma=${gap.luma}',
          );
          expect(
            gap.g,
            lessThan(110),
            reason: 'dash gaps must stay red, not paper; gapG=${gap.g}',
          );
        }
        if (entry.key == 'grad_stroke_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GradStrokeSoft');
          expect(source.fill.pattern, 0);
          expect(source.fill.hasGradient, isFalse);
          expect(source.line.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'grad_stroke_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) meanRb(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          double minLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var darkest = 255.0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < darkest) darkest = luma;
              }
            }
            return darkest;
          }

          final left = meanRb(3.15, 5.3, 3.55, 5.7);
          final right = meanRb(4.95, 5.3, 5.35, 5.7);
          final ring = minLuma(2.52, 5.2, 2.78, 5.8);
          expect(
            left.r,
            greaterThan(right.r + 40),
            reason: 'LibreOffice must keep the baked red-to-blue wash; '
                'left=$left right=$right ring=$ring',
          );
          expect(
            right.b,
            greaterThan(left.b + 40),
            reason: 'LibreOffice must keep the baked red-to-blue wash; '
                'left=$left right=$right',
          );
          expect(
            ring,
            lessThan(50),
            reason: 'LibreOffice must paint the feathered black stroke; '
                'leftR=${left.r} ring=$ring',
          );
        }
        if (entry.key == 'compound_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CompoundSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 0);
          expect(source.line.compoundType, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'compound_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double luma}) mean(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumLuma = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            if (count == 0) {
              return (r: 0.0, g: 255.0, luma: 255.0);
            }
            return (r: sumR / count, g: sumG / count, luma: sumLuma / count);
          }

          double minLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var darkest = 255.0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < darkest) darkest = luma;
              }
            }
            return darkest;
          }

          final centre = mean(3.9, 5.2, 4.6, 5.8);
          final ring = minLuma(2.45, 5.2, 2.85, 5.8);
          expect(
            centre.r,
            greaterThan(180),
            reason: 'LibreOffice must keep the red fill; '
                'centreR=${centre.r} ring=$ring',
          );
          expect(
            centre.g,
            lessThan(80),
            reason: 'LibreOffice fill must stay red; centreG=${centre.g}',
          );
          expect(
            ring,
            lessThan(50),
            reason: 'LibreOffice must paint the feathered compound rails; '
                'centreR=${centre.r} ring=$ring',
          );
        }
        if (entry.key == 'line_grad_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'LineGradSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 0);
          expect(source.line.hasGradient, isFalse);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'line_grad_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) meanRb(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          final left = meanRb(2.62, 5.35, 2.88, 5.65);
          final right = meanRb(5.62, 5.35, 5.88, 5.65);
          final centre = meanLuma(4.1, 5.35, 4.4, 5.65);
          expect(
            left.r,
            greaterThan(right.r + 30),
            reason: 'LibreOffice must keep the baked LineGradient wash; '
                'left=$left right=$right centre=$centre',
          );
          expect(
            right.b,
            greaterThan(left.b + 30),
            reason: 'LibreOffice must keep the baked LineGradient wash; '
                'left=$left right=$right',
          );
          expect(
            centre,
            greaterThan(200),
            reason: 'LibreOffice must keep the hollow interior empty; '
                'centre=$centre left=$left',
          );
        }
        if (entry.key == 'line_grad_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'LineGradTheme');
          expect(source.line.hasGradient, isFalse);
          expect(source.line.pattern, 0);
          expect(
            source.fill.themeForegroundIndex == ThemeSlot.accent6 ||
                source.fill.foreground?.value ==
                    VsdxTheme.office.resolve(ThemeSlot.accent6)!.value,
            isTrue,
            reason: 'theme-only LineGradient must not bake a black ribbon; '
                'fill=${source.fill.foreground} '
                'theme=${source.fill.themeForegroundIndex}',
          );
          expect(source.geometries.any((g) => !g.noFill), isTrue);
        }
        if (entry.key == 'line_grad_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double b}) meanRgb(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0, b: 0.0);
            return (r: sumR / count, g: sumG / count, b: sumB / count);
          }

          final left = meanRgb(2.85, 5.38, 3.25, 5.62);
          final right = meanRgb(5.25, 5.38, 5.65, 5.62);
          expect(
            left.b,
            greaterThan(right.b + 20),
            reason: 'LibreOffice classic 25–40 paints FillBkgnd (last stop) '
                'on the left of a 1-D ribbon; left=$left right=$right',
          );
          expect(
            right.g,
            greaterThan(right.r + 8),
            reason: 'LibreOffice must keep the green FillForegnd end of the '
                'theme wash; left=$left right=$right',
          );
          expect(
            left.b,
            greaterThan(left.r + 8),
            reason: 'LibreOffice must keep the blue FillBkgnd end of the '
                'theme wash, not a black ribbon; left=$left right=$right',
          );
        }
        if (entry.key == 'round_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'RoundSoft');
          expect(source.fill.pattern, 0);
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'round_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double luma}) mean(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumLuma = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 255.0, luma: 255.0);
            return (r: sumR / count, g: sumG / count, luma: sumLuma / count);
          }

          final centre = mean(3.9, 5.2, 4.6, 5.8);
          final corner = mean(2.78, 6.42, 2.88, 6.50);
          expect(
            centre.r,
            greaterThan(180),
            reason: 'LibreOffice must keep the red body; '
                'centreR=${centre.r} corner=$corner',
          );
          expect(
            centre.g,
            lessThan(80),
            reason: 'LibreOffice fill must stay red; centreG=${centre.g}',
          );
          expect(
            corner.r,
            lessThan(160),
            reason: 'LibreOffice must keep the filleted corner empty; '
                'corner=$corner centreR=${centre.r}',
          );
        }
        if (entry.key == 'shadow_blur' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          double meanRed(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                sum += rendered.getPixel(x, y).r;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          final body = meanRed(3.9, 5.2, 4.6, 5.8);
          final halo = meanLuma(6.22, 5.3, 6.38, 5.7);
          expect(
            body,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'body=$body halo=$halo',
          );
          expect(
            halo,
            lessThan(220),
            reason: 'LibreOffice must paint the Gaussian shadow halo past '
                'the hard-offset box; body=$body halo=$halo',
          );
        }
        if (entry.key == 'shadow_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ShadowThemePng');
          expect(source.shadow.enabled, isFalse);
          expect(source.shadow.blurInches, closeTo(0, 1e-9));
          expect(source.fill.pattern, 1);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioShadowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width));
        }
        if (entry.key == 'shadow_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(6.22, 5.3, 6.38, 5.7);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 8),
            reason: 'LibreOffice must paint the Gaussian Office accent6 '
                'shadow past the hard-offset box; bodyR=${body.r} '
                'haloG=${halo.g} haloR=${halo.r}',
          );
        }
        if (entry.key == 'shadow_trans_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ShadowTransTheme');
          final expected = colourForLibvisioAlpha(
            VsdxTheme.office.resolve(ThemeSlot.accent6)!,
            0.7,
          );
          expect(source.shadow.enabled, isTrue);
          expect(source.shadow.color?.value, expected.value);
          expect(source.shadow.themeColorIndex, isNull);
          expect(source.shadow.transparency, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioShadowPlate),
            isEmpty,
          );
        }
        if (entry.key == 'shadow_trans_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(5.85, 5.2, 6.10, 5.8);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'bodyR=${body.r} haloR=${halo.r} haloG=${halo.g}',
          );
          expect(
            halo.r,
            greaterThan(160),
            reason: 'LibreOffice must paint the faded Office accent6 shadow, '
                'not opaque THEMEVAL green; '
                'haloR=${halo.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r),
            reason: 'the faded accent6 blend must stay green-tinted; '
                'haloR=${halo.r} haloG=${halo.g}',
          );
          expect(
            halo.r,
            lessThan(245),
            reason: 'the hard offset copy must not be missing (page white); '
                'haloR=${halo.r} haloG=${halo.g}',
          );
        }
        if (entry.key == 'glow_png') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowPng');
          expect(source.glow.enabled, isFalse);
          expect(source.line.pattern, 1);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioGlowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width + 0.1));
        }
        if (entry.key == 'glow_png' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(2.28, 5.2, 2.52, 5.8);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 15),
            reason: 'LibreOffice must paint the Gaussian green glow, not a '
                'hard LineWeight halo; bodyR=${body.r} haloG=${halo.g} '
                'haloR=${halo.r}',
          );
        }
        if (entry.key == 'glow_noline') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowNoLinePng');
          expect(source.glow.enabled, isFalse);
          expect(source.line.pattern, 0);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioGlowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width + 0.1));
        }
        if (entry.key == 'glow_noline' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(2.28, 5.2, 2.52, 5.8);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 15),
            reason: 'LibreOffice must paint the Gaussian green glow on a '
                'NoLine fill, not a hard LineWeight halo; bodyR=${body.r} '
                'haloG=${halo.g} haloR=${halo.r}',
          );
        }
        if (entry.key == 'glow_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowThemePng');
          expect(source.glow.enabled, isFalse);
          expect(source.line.pattern, 0);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioGlowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width + 0.1));
        }
        if (entry.key == 'glow_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(2.28, 5.2, 2.52, 5.8);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 15),
            reason: 'LibreOffice must paint the Gaussian Office accent6 glow, '
                'not a hard LineWeight halo; bodyR=${body.r} haloG=${halo.g} '
                'haloR=${halo.r}',
          );
        }
        if (entry.key == 'glow_spline_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowSplineTheme');
          final expected = colourForLibvisioAlpha(
            VsdxTheme.office.resolve(ThemeSlot.accent6)!,
            0.4 + 0.6 * 0.15,
          );
          expect(source.glow.enabled, isFalse);
          expect(
            source.line.color?.value,
            expected.value,
            reason: 'the LineWeight halo must carry the faded slot as RGB',
          );
          expect(source.line.themeColorIndex, isNull);
          expect(source.line.transparency, closeTo(0, 1e-9));
          expect(
            reopened.pages.first.shapes.where(isLibvisioGlowPlate),
            isEmpty,
          );
        }
        if (entry.key == 'glow_spline_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final halo = mean(3.9, 4.28, 4.6, 4.42);
          expect(
            halo.r,
            greaterThan(150),
            reason: 'LibreOffice must paint the faded Office accent6 halo, not '
                'the opaque black THEMEVAL() fallback getThemeColour drops; '
                'haloR=${halo.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r),
            reason: 'the faded accent6 halo must stay green-tinted; '
                'haloR=${halo.r} haloG=${halo.g}',
          );
        }
        if (entry.key == 'char_trans_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CharTransTheme');
          final expected = colourForLibvisioAlpha(
            VsdxTheme.office.resolve(ThemeSlot.accent6)!,
            0.7,
          );
          expect(
            source.richText.runs.single.charStyle.color?.value,
            expected.value,
            reason: 'theme ColorTrans must freeze into Color',
          );
          expect(source.richText.runs.single.charStyle.themeColorIndex, isNull);
          expect(
            source.richText.runs.single.charStyle.transparency,
            closeTo(0, 1e-9),
          );
        }
        if (entry.key == 'char_trans_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          // H holes stay the red fill, so a window mean is red-dominated.
          // Keep only green-tinted stroke pixels (faded mint ≈ 212,228).
          ({double r, double g, int n}) glyphMean() {
            final left = (3.85 / page.widthInches * rendered.width).round();
            final right = (4.65 / page.widthInches * rendered.width).round();
            final top = ((page.heightInches - 5.85) /
                    page.heightInches *
                    rendered.height)
                .round();
            final bottom = ((page.heightInches - 5.15) /
                    page.heightInches *
                    rendered.height)
                .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.g > 80 && pixel.g > pixel.r * 0.6) {
                  sumR += pixel.r;
                  sumG += pixel.g;
                  count++;
                }
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0, n: 0);
            return (r: sumR / count, g: sumG / count, n: count);
          }

          final glyph = glyphMean();
          expect(
            glyph.n,
            greaterThan(400),
            reason: 'LibreOffice must paint the H, not only the red fill; '
                'glyphN=${glyph.n} glyphR=${glyph.r} glyphG=${glyph.g}',
          );
          expect(
            glyph.r,
            greaterThan(160),
            reason: 'LibreOffice must paint the faded Office accent6 glyph, '
                'not opaque THEMEVAL green; '
                'glyphR=${glyph.r} glyphG=${glyph.g}',
          );
          expect(
            glyph.g,
            greaterThan(glyph.r),
            reason: 'the faded accent6 blend must stay green-tinted; '
                'glyphR=${glyph.r} glyphG=${glyph.g}',
          );
        }
        if (entry.key == 'fill_trans_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FillTransTheme');
          expect(
            source.fill.foreground?.value,
            VsdxTheme.office.resolve(ThemeSlot.accent6)!.value,
            reason: 'theme FillForegndTrans must freeze into FillForegnd',
          );
          expect(source.fill.themeForegroundIndex, isNull);
          expect(
            source.fill.foregroundTransparency,
            closeTo(0.7, 1e-9),
            reason: 'FillForegndTrans is a token; keep it so Draw composites',
          );
        }
        if (entry.key == 'fill_trans_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double b, int n}) bodyMean() {
            final left = (3.4 / page.widthInches * rendered.width).round();
            final right = (5.1 / page.widthInches * rendered.width).round();
            final top = ((page.heightInches - 6.2) /
                    page.heightInches *
                    rendered.height)
                .round();
            final bottom = ((page.heightInches - 4.8) /
                    page.heightInches *
                    rendered.height)
                .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0, b: 0.0, n: 0);
            return (
              r: sumR / count,
              g: sumG / count,
              b: sumB / count,
              n: count
            );
          }

          final body = bodyMean();
          expect(
            body.n,
            greaterThan(200),
            reason: 'LibreOffice must paint the faded theme fill; '
                'bodyN=${body.n} bodyR=${body.r} bodyG=${body.g}',
          );
          expect(
            body.r,
            greaterThan(160),
            reason: 'LibreOffice must paint faded Office accent6, not opaque '
                'THEMEVAL green; bodyR=${body.r} bodyG=${body.g}',
          );
          expect(
            body.g,
            greaterThan(body.r + 8),
            reason: 'the faded accent6 fill must stay green-tinted, not the '
                'grey getThemeColour(9) fallback; '
                'bodyR=${body.r} bodyG=${body.g} bodyB=${body.b}',
          );
          expect(
            body.g,
            greaterThan(body.b),
            reason: 'the faded accent6 fill must stay green-tinted; '
                'bodyG=${body.g} bodyB=${body.b}',
          );
        }
        if (entry.key == 'fill_theme_opaque') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FillThemeOpaque');
          expect(
            source.fill.themeForegroundIndex,
            ThemeSlot.accent6,
            reason: 'opaque theme fill must keep THEMEVAL for round-trip',
          );
          expect(source.fill.foreground, isNull);
        }
        if (entry.key == 'fill_theme_opaque' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double b, int n}) bodyMean() {
            final left = (3.4 / page.widthInches * rendered.width).round();
            final right = (5.1 / page.widthInches * rendered.width).round();
            final top = ((page.heightInches - 6.2) /
                    page.heightInches *
                    rendered.height)
                .round();
            final bottom = ((page.heightInches - 4.8) /
                    page.heightInches *
                    rendered.height)
                .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0, b: 0.0, n: 0);
            return (
              r: sumR / count,
              g: sumG / count,
              b: sumB / count,
              n: count
            );
          }

          final body = bodyMean();
          expect(
            body.n,
            greaterThan(200),
            reason: 'LibreOffice must paint the opaque theme fill; '
                'bodyN=${body.n} bodyR=${body.r} bodyG=${body.g}',
          );
          expect(
            body.r,
            greaterThan(40),
            reason: 'LibreOffice must not paint palette-0 black; '
                'bodyR=${body.r} bodyG=${body.g}',
          );
          expect(
            body.r,
            lessThan(180),
            reason: 'LibreOffice must paint opaque Office accent6, not white; '
                'bodyR=${body.r} bodyG=${body.g}',
          );
          expect(
            body.g,
            greaterThan(body.r + 15),
            reason: 'LibreOffice must paint Office accent6 green, not black; '
                'bodyR=${body.r} bodyG=${body.g}',
          );
        }
        if (entry.key == 'highlight_mixed') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          expect(
            page.shapes.where(isLibvisioHighlightPlate),
            hasLength(2),
          );
          final source =
              page.shapes.firstWhere((s) => s.name == 'HighlightMixed');
          expect(source.richText.textBlock.hideText, isTrue);
          expect(
            source.richText.runs[0].charStyle.highlight?.value,
            0xFFFF00FF,
          );
          expect(
            source.richText.runs[1].charStyle.highlight?.value,
            0xFF00FF00,
          );
          expect(source.richText.textBlock.backgroundColor, isNull);
        }
        if (entry.key == 'highlight_mixed' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          var limePixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
              magentaPixels++;
            }
            if (pixel.g > 200 && pixel.r < 40) {
              limePixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(50),
            reason: 'LibreOffice must paint the magenta Highlight plate; '
                'magentaPixels=$magentaPixels limePixels=$limePixels',
          );
          expect(
            limePixels,
            greaterThan(50),
            reason: 'LibreOffice must paint the lime Highlight plate; '
                'magentaPixels=$magentaPixels limePixels=$limePixels',
          );
        }
        if (entry.key == 'highlight_mixed_nl') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes.where(isLibvisioHighlightPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(2));
          expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
          expect(plates[1].fill.foreground?.value, 0xFF00FF00);
          expect(plates[0].pinY, greaterThan(plates[1].pinY + 0.4));
          expect(
            page.shapes
                .firstWhere((s) => s.name == 'HighlightMixedNl')
                .richText
                .textBlock
                .hideText,
            isTrue,
          );
        }
        if (entry.key == 'highlight_mixed_nl' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;

          ({int magenta, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
                  magenta++;
                }
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (magenta: magenta, lime: lime);
          }

          final upper = countWindow(3.7, 5.55, 4.8, 6.45);
          final lower = countWindow(3.7, 4.55, 4.8, 5.45);
          expect(
            upper.magenta,
            greaterThan(20),
            reason: 'LibreOffice must paint magenta on the first line; '
                'upperM=${upper.magenta} upperL=${upper.lime} '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
          expect(
            lower.lime,
            greaterThan(20),
            reason: 'LibreOffice must paint lime on the second line; '
                'upperM=${upper.magenta} upperL=${upper.lime} '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
          expect(
            upper.magenta,
            greaterThan(upper.lime),
            reason: 'first line must stay magenta, not lime; '
                'upperM=${upper.magenta} upperL=${upper.lime}',
          );
          expect(
            lower.lime,
            greaterThan(lower.magenta),
            reason: 'second line must stay lime, not magenta; '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
        }
        if (entry.key == 'highlight_mixed_wrap') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes.where(isLibvisioHighlightPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(2));
          expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
          expect(plates[1].fill.foreground?.value, 0xFF00FF00);
          expect(plates[0].pinY, greaterThan(plates[1].pinY + 0.15));
          expect(
            page.shapes
                .firstWhere((s) => s.name == 'HighlightMixedWrap')
                .richText
                .textBlock
                .hideText,
            isTrue,
          );
        }
        if (entry.key == 'highlight_mixed_wrap' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;

          ({int magenta, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
                  magenta++;
                }
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (magenta: magenta, lime: lime);
          }

          final upper = countWindow(3.5, 5.45, 5.0, 6.2);
          final lower = countWindow(3.5, 4.7, 5.0, 5.4);
          expect(
            upper.magenta,
            greaterThan(20),
            reason: 'LibreOffice must wrap magenta onto the first line; '
                'upperM=${upper.magenta} upperL=${upper.lime} '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
          expect(
            lower.lime,
            greaterThan(20),
            reason: 'LibreOffice must wrap lime onto the second line; '
                'upperM=${upper.magenta} upperL=${upper.lime} '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
          expect(
            lower.lime,
            greaterThan(lower.magenta),
            reason: 'wrapped second word must stay lime, not magenta; '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
        }
        if (entry.key == 'highlight_mixed_tab') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes.where(isLibvisioHighlightPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(2));
          expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
          expect(plates[1].fill.foreground?.value, 0xFF00FF00);
          expect(plates[1].pinX - plates[0].pinX, greaterThan(1.2));
        }
        if (entry.key == 'highlight_mixed_tab' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;

          ({int magenta, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
                  magenta++;
                }
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (magenta: magenta, lime: lime);
          }

          final leftField = countWindow(2.2, 5.05, 3.2, 5.95);
          final tabField = countWindow(4.1, 5.05, 5.2, 5.95);
          expect(
            leftField.magenta,
            greaterThan(20),
            reason: 'LibreOffice must paint magenta before the tab; '
                'leftM=${leftField.magenta} leftL=${leftField.lime} '
                'tabM=${tabField.magenta} tabL=${tabField.lime}',
          );
          expect(
            tabField.lime,
            greaterThan(20),
            reason: 'LibreOffice must paint lime at the 2" tab stop; '
                'leftM=${leftField.magenta} leftL=${leftField.lime} '
                'tabM=${tabField.magenta} tabL=${tabField.lime}',
          );
          expect(
            leftField.magenta,
            greaterThan(leftField.lime),
            reason: 'the first field must stay magenta; '
                'leftM=${leftField.magenta} leftL=${leftField.lime}',
          );
          expect(
            tabField.lime,
            greaterThan(tabField.magenta),
            reason: 'the tab field must stay lime; '
                'tabM=${tabField.magenta} tabL=${tabField.lime}',
          );
        }
        if (entry.key == 'text_direction') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'TextDirection');
          expect(source.richText.textBlock.textDirection, 0);
          expect(
            source.richText.textBlock.angleRad,
            closeTo(-math.pi / 2, 1e-6),
          );
          expect(source.richText.textBlock.widthInches, greaterThan(0.7));
          expect(
            source.richText.textBlock.heightInches,
            closeTo(3, 1e-6),
          );
        }
        if (entry.key == 'text_direction' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          int countMagenta(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var n = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) n++;
              }
            }
            return n;
          }

          final north = countMagenta(4.05, 5.95, 4.45, 6.35);
          final west = countMagenta(3.2, 5.25, 3.65, 5.75);
          expect(
            north,
            greaterThan(15),
            reason: 'LibreOffice must rotate TextDirection=1 into a tall '
                'column; north=$north west=$west',
          );
          expect(
            north,
            greaterThan(west),
            reason: 'rotated TextBkgnd must sit on the vertical axis, not '
                'the original wide box; north=$north west=$west',
          );
        }
        if (entry.key == 'text_direction_edge') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'TextDirectionEdge');
          expect(source.richText.textBlock.textDirection, 0);
          expect(source.richText.textBlock.angleRad, closeTo(0, 1e-6));
          final pin = reopened.pages.first.localToPageDeep(
            source.id,
            Offset2D(
              source.richText.textBlock.pinXInches!,
              source.richText.textBlock.pinYInches!,
            ),
          );
          expect(pin.x, closeTo(7, 0.2));
          expect(pin.y, closeTo(7, 0.2));
          expect(
            source.richText.textBlock.heightInches,
            greaterThan(source.richText.textBlock.widthInches! + 0.3),
          );
        }
        if (entry.key == 'text_direction_edge' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          int countMagenta(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var n = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) n++;
              }
            }
            return n;
          }

          final north = countMagenta(6.8, 7.35, 7.2, 7.75);
          final east = countMagenta(7.35, 6.8, 7.75, 7.2);
          final box = countMagenta(3.6, 3.6, 4.4, 4.4);
          expect(
            north,
            greaterThan(8),
            reason: 'LibreOffice must rotate the connector TextDirection=1 '
                'plate at the elbow; north=$north east=$east box=$box',
          );
          expect(
            north,
            greaterThan(east),
            reason: 'rotated TextBkgnd must stand on the vertical axis at '
                'the elbow, not stay a wide run; north=$north east=$east',
          );
          expect(
            box,
            lessThan(3),
            reason: 'LibreOffice must not park the vertical label at the '
                '1-D box centre; north=$north box=$box',
          );
        }
        if (entry.key == 'highlight_mixed_vert') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes.where(isLibvisioHighlightPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(2));
          expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
          expect(plates[1].fill.foreground?.value, 0xFF00FF00);
          expect(plates[0].pinY, greaterThan(plates[1].pinY + 0.2));
          expect(plates[0].pinX, closeTo(plates[1].pinX, 0.35));
          expect(
            page.shapes
                .firstWhere((s) => s.name == 'HighlightMixedVert')
                .richText
                .textBlock
                .textDirection,
            0,
          );
        }
        if (entry.key == 'highlight_mixed_vert' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int magenta, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
                  magenta++;
                }
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (magenta: magenta, lime: lime);
          }

          final upper = countWindow(4.0, 5.7, 4.5, 6.25);
          final lower = countWindow(4.0, 4.75, 4.5, 5.3);
          expect(
            upper.magenta,
            greaterThan(20),
            reason: 'LibreOffice must paint magenta above after TextDirection '
                'bake; upperM=${upper.magenta} upperL=${upper.lime} '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
          expect(
            lower.lime,
            greaterThan(20),
            reason: 'LibreOffice must paint lime below after TextDirection '
                'bake; upperM=${upper.magenta} upperL=${upper.lime} '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
          expect(
            upper.magenta,
            greaterThan(upper.lime),
            reason: 'upper plate must stay magenta; '
                'upperM=${upper.magenta} upperL=${upper.lime}',
          );
          expect(
            lower.lime,
            greaterThan(lower.magenta),
            reason: 'lower plate must stay lime; '
                'lowerM=${lower.magenta} lowerL=${lower.lime}',
          );
        }
        if (entry.key == 'glow_stroke') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowStrokePng');
          expect(source.glow.enabled, isFalse);
          expect(source.fill.hasFill, isFalse);
          expect(source.line.pattern, 1);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioGlowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width + 0.1));
        }
        if (entry.key == 'glow_stroke' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(2.28, 5.2, 2.52, 5.8);
          expect(
            body.r,
            greaterThan(200),
            reason: 'LibreOffice must keep the unfilled interior empty; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 10),
            reason:
                'LibreOffice must paint the Gaussian green glow ring, not a '
                'hard FillForegndTrans ribbon; bodyR=${body.r} haloG=${halo.g} '
                'haloR=${halo.r}',
          );
        }
        if (entry.key == 'glow_stroke_1d') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowStroke1d');
          expect(source.glow.enabled, isFalse);
          expect(source.is1D, isTrue);
          expect(source.fill.hasFill, isFalse);
          expect(source.line.pattern, 1);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioGlowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.is1D, isFalse);
          expect(plate.height, greaterThan(0.2));
        }
        if (entry.key == 'glow_stroke_1d' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0, b: 0.0);
            return (r: sumR / count, g: sumG / count, b: sumB / count);
          }

          final empty = mean(1.0, 2.0, 1.6, 2.6);
          final sourceRail = mean(3.5, 5.47, 5.0, 5.53);
          final halo = mean(3.5, 5.68, 5.0, 5.90);
          expect(
            sourceRail.r + sourceRail.g + sourceRail.b,
            lessThan(empty.r + empty.g + empty.b - 30),
            reason: 'LibreOffice must still stroke the 1-D source; '
                'sourceRGB=${sourceRail.r},${sourceRail.g},${sourceRail.b}',
          );
          expect(
            halo.g,
            lessThan(empty.g - 8),
            reason: 'LibreOffice must paint the 1-D magenta glow halo, not '
                'drop it; haloG=${halo.g} emptyG=${empty.g} haloR=${halo.r}',
          );
        }
        if (entry.key == 'glow_stroke_compound') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowStrokeCompound');
          expect(source.glow.enabled, isFalse);
          expect(source.fill.hasFill, isFalse);
          expect(
            reopened.pages.first.shapes.where(isLibvisioGlowPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'glow_stroke_compound' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(2.28, 5.2, 2.52, 5.8);
          expect(
            body.r,
            greaterThan(200),
            reason: 'LibreOffice must keep the unfilled interior empty; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 10),
            reason: 'LibreOffice must paint the CompoundType Glow ring, not '
                'drop it; bodyR=${body.r} haloG=${halo.g} haloR=${halo.r}',
          );
        }
        if (entry.key == 'glow_picture') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GlowPicturePng');
          expect(source.glow.enabled, isFalse);
          expect(source.hasImage, isTrue);
          expect(source.line.pattern, 0);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioGlowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width + 0.1));
        }
        if (entry.key == 'glow_picture' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(2.28, 5.2, 2.52, 5.8);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source picture; '
                'bodyR=${body.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 10),
            reason:
                'LibreOffice must paint the Gaussian green glow ring around '
                'the picture, not a hard LineWeight halo; bodyR=${body.r} '
                'haloG=${halo.g} haloR=${halo.r}',
          );
        }
        if (entry.key == 'shadow_picture') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ShadowPicturePng');
          expect(source.shadow.enabled, isFalse);
          expect(source.hasImage, isTrue);
          final plate =
              reopened.pages.first.shapes.where(isLibvisioShadowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(plate.width, greaterThan(source.width));
        }
        if (entry.key == 'shadow_picture' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          double meanRed(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                sum += rendered.getPixel(x, y).r;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          final body = meanRed(3.9, 5.2, 4.6, 5.8);
          final halo = meanLuma(6.22, 5.3, 6.38, 5.7);
          expect(
            body,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source picture; '
                'body=$body halo=$halo',
          );
          expect(
            halo,
            lessThan(220),
            reason: 'LibreOffice must paint the Gaussian picture shadow halo; '
                'body=$body halo=$halo',
          );
        }
        if (entry.key == 'reflection_picture') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionPicturePng');
          expect(source.reflection.enabled, isFalse);
          expect(source.hasImage, isTrue);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue);
          expect(
            plate.pinY - plate.effectiveLocPinY,
            lessThan(source.pinY - source.effectiveLocPinY),
          );
        }
        if (entry.key == 'reflection_picture' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final bodyTop = mean(3.9, 6.0, 4.6, 6.3);
          final mirror = mean(3.9, 4.15, 4.6, 4.35);
          expect(
            bodyTop.r,
            greaterThan(bodyTop.b + 20),
            reason: 'LibreOffice must still paint the source picture top red; '
                'bodyR=${bodyTop.r} bodyB=${bodyTop.b} mirrorB=${mirror.b}',
          );
          expect(
            mirror.b,
            greaterThan(mirror.r + 10),
            reason: 'LibreOffice must paint the blue (original bottom) '
                'picture reflection below the source; '
                'bodyR=${bodyTop.r} mirrorB=${mirror.b} mirrorR=${mirror.r}',
          );
        }
        if (entry.key == 'reflection_picture_flipy') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionPictureFlipY');
          expect(source.flipY, isTrue);
          expect(source.reflection.enabled, isFalse);
          expect(source.hasImage, isTrue);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue);
          expect(plate.flipY, isFalse,
              reason: 'copying FlipY onto the PNG would mirror the band twice');
        }
        if (entry.key == 'reflection_picture_flipy' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final bodyTop = mean(3.9, 6.0, 4.6, 6.3);
          final mirror = mean(3.9, 6.55, 4.6, 6.75);
          final below = mean(3.9, 4.15, 4.6, 4.35);
          expect(
            bodyTop.b,
            greaterThan(bodyTop.r + 20),
            reason: 'LibreOffice FlipY source top must be original bottom '
                '(blue); bodyR=${bodyTop.r} bodyB=${bodyTop.b}',
          );
          expect(
            mirror.r,
            greaterThan(mirror.b + 10),
            reason: 'FlipY must keep the original top (red) nearest the '
                'visual bottom (above in local Y); '
                'mirrorR=${mirror.r} mirrorB=${mirror.b}',
          );
          expect(
            below.r,
            greaterThan(200),
            reason: 'FlipY must not leave the unflipped blue band below; '
                'belowR=${below.r} belowB=${below.b}',
          );
        }
        if (entry.key == 'crop_reflection') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CropReflectionPicture');
          expect(source.reflection.enabled, isFalse);
          expect(source.hasImage, isTrue);
          expect(source.imgOffsetXInches, closeTo(0, 1e-9));
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue);
          expect(plate.imgOffsetXInches, closeTo(0, 1e-9));
        }
        if (entry.key == 'crop_reflection' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          // Crop shows the right (blue) half. The left of the frame is still
          // blue; a raw-bitmap sibling would put the hidden red half there.
          final body = mean(3.0, 5.2, 3.5, 5.8);
          final mirror = mean(3.0, 4.15, 3.5, 4.35);
          expect(
            body.b,
            greaterThan(body.r + 20),
            reason: 'LibreOffice must still paint the cropped source blue; '
                'bodyB=${body.b} bodyR=${body.r} mirrorB=${mirror.b}',
          );
          expect(
            mirror.b,
            greaterThan(mirror.r + 10),
            reason: 'LibreOffice must reflect the visible (blue) crop, not '
                'the hidden left (red) half; '
                'bodyB=${body.b} mirrorB=${mirror.b} mirrorR=${mirror.r}',
          );
        }
        if (entry.key == 'crop_picture') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CropPicture');
          expect(source.imgOffsetXInches, closeTo(0, 1e-9));
          expect(source.effectiveImgWidth, closeTo(source.width, 1e-6));
          expect(source.hasImage, isTrue);
        }
        if (entry.key == 'crop_picture' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final overflow = mean(0.2, 5.2, 1.0, 5.8);
          expect(
            body.b,
            greaterThan(body.r + 20),
            reason: 'LibreOffice must paint the cropped right (blue) half; '
                'bodyB=${body.b} bodyR=${body.r}',
          );
          expect(
            overflow.r - overflow.b,
            lessThan(40),
            reason: 'LibreOffice must not paint the hidden left (red) half '
                'outside the Foreign frame; overflowR=${overflow.r} '
                'overflowB=${overflow.b}',
          );
        }
        if (entry.key == 'crop_soft') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CropSoftPicture');
          expect(source.line.softEdgesInches, closeTo(0, 1e-9));
          expect(source.imgOffsetXInches, closeTo(0, 1e-9));
          expect(source.effectiveImgWidth, closeTo(source.width, 1e-6));
          expect(source.hasImage, isTrue);
        }
        if (entry.key == 'crop_soft' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b, double luma}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var sumLuma = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0, luma: 0.0);
            return (r: sumR / count, b: sumB / count, luma: sumLuma / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final edge = mean(2.78, 5.4, 2.92, 5.6);
          expect(
            body.b,
            greaterThan(body.r + 20),
            reason: 'LibreOffice must paint the cropped right (blue) half; '
                'bodyB=${body.b} bodyR=${body.r} edgeLuma=${edge.luma}',
          );
          expect(
            edge.luma,
            greaterThan(body.luma + 15),
            reason: 'LibreOffice must feather the cropped SoftEdges window, '
                'not keep a hard ImgOffset crop; bodyLuma=${body.luma} '
                'edgeLuma=${edge.luma}',
          );
        }
        if (entry.key == 'reflection_stroke') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionStrokePng');
          expect(source.reflection.enabled, isFalse);
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 1);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue,
              reason: 'an unfilled stroke must not bake a filled mirror');
        }
        if (entry.key == 'reflection_stroke' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final sourceRail = mean(2.71, 5.0, 2.81, 6.0);
          final bandRail = mean(2.71, 4.2, 2.81, 4.4);
          final bandInterior = mean(4.0, 4.2, 4.5, 4.4);
          expect(
            sourceRail.b,
            greaterThan(sourceRail.r + 20),
            reason: 'LibreOffice must still stroke the source rail; '
                'sourceB=${sourceRail.b} sourceR=${sourceRail.r}',
          );
          expect(
            bandRail.b,
            greaterThan(bandRail.r + 10),
            reason: 'LibreOffice must paint the mirrored stroke band, not '
                'drop it; bandB=${bandRail.b} bandR=${bandRail.r}',
          );
          expect(
            bandInterior.r,
            greaterThan(200),
            reason: 'the band interior must stay hollow, not a filled mirror; '
                '            interiorR=${bandInterior.r} interiorB=${bandInterior.b}',
          );
        }
        if (entry.key == 'reflection_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionThemePng');
          expect(source.reflection.enabled, isFalse);
          expect(source.fill.pattern, 0);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue,
              reason: 'theme-only LineColor must freeze into a PNG band');
        }
        if (entry.key == 'reflection_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final bandRail = mean(2.71, 4.2, 2.81, 4.4);
          final bandInterior = mean(4.0, 4.2, 4.5, 4.4);
          expect(
            bandRail.g,
            greaterThan(bandRail.r + 8),
            reason:
                'LibreOffice must paint the theme-coloured mirrored stroke, '
                'not drop it; bandG=${bandRail.g} bandR=${bandRail.r}',
          );
          expect(
            bandInterior.r,
            greaterThan(200),
            reason: 'the band interior must stay hollow, not a filled mirror; '
                'interiorR=${bandInterior.r} interiorG=${bandInterior.g}',
          );
        }
        if (entry.key == 'reflection_stroke_1d') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionStroke1d');
          expect(source.reflection.enabled, isFalse);
          expect(source.is1D, isTrue);
          expect(source.line.pattern, 1);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue);
          expect(plate.is1D, isFalse);
        }
        if (entry.key == 'reflection_stroke_1d' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final sourceRail = mean(3.5, 5.42, 5.0, 5.58);
          final bandRail = mean(3.5, 5.18, 5.0, 5.34);
          expect(
            sourceRail.b,
            greaterThan(sourceRail.r + 20),
            reason: 'LibreOffice must still stroke the 1-D source; '
                'sourceB=${sourceRail.b} sourceR=${sourceRail.r}',
          );
          expect(
            bandRail.b,
            greaterThan(bandRail.r + 8),
            reason: 'LibreOffice must paint the 1-D mirrored stroke, not '
                'drop it; bandB=${bandRail.b} bandR=${bandRail.r}',
          );
        }
        if (entry.key == 'reflection_stroke_flipy') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionStrokeFlipY');
          expect(source.flipY, isTrue);
          expect(source.reflection.enabled, isFalse);
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 1);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioReflectionPlate)
              .single;
          expect(plate.hasImage, isTrue);
          expect(plate.flipY, isFalse,
              reason: 'copying FlipY onto the PNG would mirror the band twice');
        }
        if (entry.key == 'reflection_stroke_flipy' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final sourceRail = mean(2.71, 5.0, 2.81, 6.0);
          final bandRail = mean(2.71, 6.6, 2.81, 6.8);
          final bandInterior = mean(4.0, 6.6, 4.5, 6.8);
          final below = mean(2.71, 4.2, 2.81, 4.4);
          expect(
            sourceRail.b,
            greaterThan(sourceRail.r + 20),
            reason: 'LibreOffice must still stroke the FlipY source rail; '
                'sourceB=${sourceRail.b} sourceR=${sourceRail.r}',
          );
          expect(
            bandRail.b,
            greaterThan(bandRail.r + 10),
            reason: 'FlipY must keep the mirrored stroke on the visual-bottom '
                'side (above in local Y); bandB=${bandRail.b} bandR=${bandRail.r}',
          );
          expect(
            bandInterior.r,
            greaterThan(200),
            reason: 'the FlipY band interior must stay hollow; '
                'interiorR=${bandInterior.r} interiorB=${bandInterior.b}',
          );
          expect(
            below.r,
            greaterThan(200),
            reason: 'FlipY must not leave the unflipped band below the shape; '
                'belowR=${below.r} belowB=${below.b}',
          );
        }
        if (entry.key == 'reflection_stroke_dash') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionStrokeDash');
          expect(source.reflection.enabled, isFalse);
          expect(source.fill.pattern, 0);
          expect(source.line.pattern, 2);
          expect(
            reopened.pages.first.shapes.where(isLibvisioReflectionPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'reflection_stroke_dash' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // Pattern 2 is 6×weight ink / 3×weight gap (0.48" / 0.24"). The
          // bottom edge starts at x=2.75; the first gap is 0.48" along.
          final ink = meanLuma(2.90, 4.40, 3.05, 4.48);
          final gap = meanLuma(3.30, 4.40, 3.42, 4.48);
          expect(
            ink,
            lessThan(180),
            reason: 'LibreOffice must paint mirrored dash ink; '
                'ink=$ink gap=$gap',
          );
          expect(
            gap,
            greaterThan(200),
            reason: 'LibreOffice must keep mirrored dash gaps, not a solid '
                'ring; ink=$ink gap=$gap',
          );
        }
        if (entry.key == 'reflection_stroke_compound') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionStrokeCompound');
          expect(source.reflection.enabled, isFalse);
          expect(source.fill.pattern, 0);
          expect(source.line.compoundType, 0,
              reason: 'libvisioShapeWrite flattens CompoundType to rails');
          expect(
            reopened.pages.first.shapes.where(isLibvisioReflectionPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'reflection_stroke_compound' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final cx = (4.25 / page.widthInches * rendered.width).round();
          final y0 =
              ((page.heightInches - 4.50) / page.heightInches * rendered.height)
                  .round();
          final y1 =
              ((page.heightInches - 4.28) / page.heightInches * rendered.height)
                  .round();
          var rails = 0;
          var inRail = false;
          for (var y = y0; y < y1; y++) {
            if (cx < 0 ||
                y < 0 ||
                cx >= rendered.width ||
                y >= rendered.height) {
              continue;
            }
            final pixel = rendered.getPixel(cx, y);
            final on = pixel.b > pixel.r + 10;
            if (on && !inRail) {
              rails++;
              inRail = true;
            } else if (!on) {
              inRail = false;
            }
          }
          final interior = mean(4.0, 4.55, 4.5, 4.75);
          expect(
            rails,
            greaterThanOrEqualTo(2),
            reason: 'LibreOffice must paint two mirrored CompoundType rails; '
                'rails=$rails',
          );
          expect(
            interior.r,
            greaterThan(200),
            reason: 'the compound mirror interior must stay hollow; '
                'interiorR=${interior.r} interiorB=${interior.b}',
          );
        }
        if (entry.key == 'reflection_stroke_linegrad') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ReflectionStrokeLineGrad');
          expect(source.reflection.enabled, isFalse);
          expect(source.line.hasGradient, isFalse,
              reason: 'libvisioShapeWrite flattens LineGradient to a ribbon');
          expect(
            reopened.pages.first.shapes.where(isLibvisioReflectionPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'reflection_stroke_linegrad' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double b}) meanInk(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma > 230) continue;
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          ({double r, double b}) meanRb(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, b: 0.0);
            return (r: sumR / count, b: sumB / count);
          }

          final left = meanInk(2.82, 4.28, 3.12, 4.44);
          final right = meanInk(5.38, 4.28, 5.68, 4.44);
          final interior = meanRb(4.0, 4.0, 4.5, 4.2);
          expect(
            left.r,
            greaterThan(right.r + 30),
            reason: 'LibreOffice must keep the baked LineGradient mirror wash; '
                'left=$left right=$right',
          );
          expect(
            right.b,
            greaterThan(left.b + 30),
            reason: 'LibreOffice must keep the baked LineGradient mirror wash; '
                'left=$left right=$right',
          );
          expect(
            interior.r,
            greaterThan(200),
            reason: 'the LineGradient mirror interior must stay hollow; '
                'interior=$interior',
          );
        }
        if (entry.key == 'oblique_shadow') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          expect(page.pageSheet.shadowType, 1);
          expect(page.pageSheet.shadowObliqueAngle, closeTo(0.6, 1e-9));
          final source =
              page.shapes.firstWhere((s) => s.name == 'ObliqueShadowBox');
          expect(source.shadow.enabled, isFalse,
              reason: 'ShdwPattern 0 so Draw adds no unsheared copy');
          final plate = page.shapes.where(isLibvisioPageShadowPlate).single;
          expect(plate.fill.foreground?.value, 0xFF000000);
          expect(plate.line.pattern, 0);
          expect(
              page.shapes.indexOf(plate),
              lessThan(
                page.shapes.indexOf(source),
              ));
        }
        if (entry.key == 'oblique_shadow' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          // Positive ShdwObliqueAngle leans the shadow's top edge right, so
          // the band past the shape's right edge is dark while the mirrored
          // upper-left band still shows the light shape body.
          final leanRight = meanLuma(5.45, 5.90, 6.00, 6.10);
          final bodyUpperLeft = meanLuma(3.35, 5.90, 3.90, 6.10);
          final below = meanLuma(3.20, 4.25, 4.40, 4.45);
          expect(
            leanRight,
            lessThan(120),
            reason: 'LibreOffice must paint the sheared shadow leaning right; '
                'leanRight=$leanRight bodyUpperLeft=$bodyUpperLeft',
          );
          expect(
            bodyUpperLeft,
            greaterThan(200),
            reason: 'the mirrored side must stay the light shape body, '
                'proving the shear direction; leanRight=$leanRight '
                'bodyUpperLeft=$bodyUpperLeft',
          );
          expect(
            below,
            lessThan(120),
            reason: 'the offset shadow must still sit below the shape; '
                'below=$below',
          );
        }
        if (entry.key == 'oblique_shadow_theme') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          expect(page.pageSheet.shadowType, 1);
          final source =
              page.shapes.firstWhere((s) => s.name == 'ObliqueShadowTheme');
          expect(source.shadow.enabled, isFalse,
              reason: 'ShdwPattern 0 so Draw adds no unsheared copy');
          final plate = page.shapes.where(isLibvisioPageShadowPlate).single;
          expect(
            plate.fill.foreground?.value,
            VsdxTheme.office.resolve(ThemeSlot.accent6)!.value,
            reason: 'theme-only ShdwForegnd must freeze into FillForegnd',
          );
          expect(plate.line.pattern, 0);
        }
        if (entry.key == 'oblique_shadow_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final leanRight = mean(5.45, 5.90, 6.00, 6.10);
          final body = mean(3.9, 5.2, 4.6, 5.8);
          expect(
            body.r,
            greaterThan(180),
            reason: 'LibreOffice must still paint the source fill; '
                'bodyR=${body.r} leanG=${leanRight.g}',
          );
          expect(
            leanRight.g,
            greaterThan(leanRight.r + 8),
            reason: 'LibreOffice must paint the sheared Office accent6 shadow; '
                'leanG=${leanRight.g} leanR=${leanRight.r} bodyR=${body.r}',
          );
        }
        if (entry.key == 'oblique_shadow_blur') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          expect(page.pageSheet.shadowType, 1);
          expect(page.pageSheet.shadowObliqueAngle, closeTo(0.6, 1e-9));
          final source =
              page.shapes.firstWhere((s) => s.name == 'ObliqueShadowBlur');
          expect(source.shadow.enabled, isFalse,
              reason: 'ShdwPattern 0 so Draw adds no unsheared copy');
          expect(source.shadow.blurInches, 0);
          expect(page.shapes.where(isLibvisioPageShadowPlate), isEmpty);
          final plate = page.shapes.where(isLibvisioShadowPlate).single;
          expect(plate.hasImage, isTrue);
          expect(
            plate.width,
            greaterThan(source.width + 0.1),
            reason: 'the sheared Gaussian plate must be wider than the box',
          );
          expect(
              page.shapes.indexOf(plate),
              lessThan(
                page.shapes.indexOf(source),
              ));
        }
        if (entry.key == 'oblique_shadow_blur' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 0 : sum / count;
          }

          // Same lean as the hard-edged sibling; blur just spreads the halo.
          final leanRight = meanLuma(5.45, 5.90, 6.00, 6.10);
          final bodyUpperLeft = meanLuma(3.35, 5.90, 3.90, 6.10);
          expect(
            leanRight,
            lessThan(160),
            reason: 'LibreOffice must paint the sheared Gaussian shadow '
                'leaning right; leanRight=$leanRight '
                'bodyUpperLeft=$bodyUpperLeft',
          );
          expect(
            bodyUpperLeft,
            greaterThan(180),
            reason: 'the mirrored side must stay the light shape body; '
                'leanRight=$leanRight bodyUpperLeft=$bodyUpperLeft',
          );
        }
        if ((entry.key == 'curved_text' || entry.key == 'curved_text_flipy') &&
            pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes
              .where(isLibvisioCurvedTextPlate)
              .toList(growable: false)
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(3));
          expect(plates[1].pinY, greaterThan(plates[0].pinY + 0.08));

          int darkCount(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          int inkAt(VsdxShape plate) {
            const r = 0.2;
            return darkCount(
              plate.pinX - r,
              plate.pinY - r,
              plate.pinX + r,
              plate.pinY + r,
            );
          }

          final midInk = inkAt(plates[1]);
          final leftInk = inkAt(plates[0]);
          final rightInk = inkAt(plates[2]);
          final belowMid = darkCount(
            plates[1].pinX - 0.05,
            plates[0].pinY - 0.05,
            plates[1].pinX + 0.05,
            plates[0].pinY + 0.05,
          );
          expect(
            midInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the raised middle glyph; '
                'mid=$midInk left=$leftInk right=$rightInk below=$belowMid',
          );
          expect(
            leftInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the left glyph; '
                'mid=$midInk left=$leftInk right=$rightInk below=$belowMid',
          );
          expect(
            rightInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the right glyph; '
                'mid=$midInk left=$leftInk right=$rightInk below=$belowMid',
          );
          expect(
            belowMid,
            lessThan(3),
            reason: 'The middle glyph must sit on the upward arc, not on the '
                'straight baseline of the side letters; '
                'mid=$midInk left=$leftInk right=$rightInk below=$belowMid',
          );
        }
        if (entry.key == 'curved_text_tab') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioCurvedTextPlate)
              .toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(2));
          expect(plates.map((p) => p.richText.plainText).join(), 'AC');
          expect(
            reopened.pages.first.shapes
                .firstWhere((s) => s.name == 'CurvedTextTab')
                .curvedText,
            isFalse,
          );
        }
        if (entry.key == 'curved_text_tab' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          final plates = page.shapes.where(isLibvisioCurvedTextPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          int darkCount(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final luma = 0.299 * rendered.getPixel(x, y).r +
                    0.587 * rendered.getPixel(x, y).g +
                    0.114 * rendered.getPixel(x, y).b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          int inkAt(VsdxShape plate) {
            const r = 0.2;
            return darkCount(
              plate.pinX - r,
              plate.pinY - r,
              plate.pinX + r,
              plate.pinY + r,
            );
          }

          expect(plates, hasLength(2));
          expect(
            inkAt(plates[0]),
            greaterThan(8),
            reason: 'LibreOffice must paint tabbed curved A; '
                'a=${inkAt(plates[0])} c=${inkAt(plates[1])}',
          );
          expect(
            inkAt(plates[1]),
            greaterThan(8),
            reason: 'LibreOffice must paint tabbed curved C; '
                'a=${inkAt(plates[0])} c=${inkAt(plates[1])}',
          );
          expect(
            (plates[0].pinX - plates[1].pinX).abs(),
            greaterThan(0.15),
            reason: 'tab becomes a space on the arc, so A and C stay apart',
          );
        }
        if (entry.key == 'curved_text_overline') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioCurvedTextPlate)
              .toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(3));
          expect(
            plates.every(
              (p) => p.richText.plainText.contains(kLibvisioCombiningOverline),
            ),
            isTrue,
          );
        }
        if (entry.key == 'curved_text_overline' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          final plates = page.shapes.where(isLibvisioCurvedTextPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          int darkCount(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final luma = 0.299 * rendered.getPixel(x, y).r +
                    0.587 * rendered.getPixel(x, y).g +
                    0.114 * rendered.getPixel(x, y).b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          int inkAt(VsdxShape plate) {
            const r = 0.2;
            return darkCount(
              plate.pinX - r,
              plate.pinY - r,
              plate.pinX + r,
              plate.pinY + r,
            );
          }

          expect(plates, hasLength(3));
          expect(plates[1].pinY, greaterThan(plates[0].pinY + 0.08));
          expect(
            inkAt(plates[0]),
            greaterThan(8),
            reason: 'LibreOffice must paint overlined A on the arc; '
                'a=${inkAt(plates[0])} r=${inkAt(plates[1])} '
                'c=${inkAt(plates[2])}',
          );
          expect(
            inkAt(plates[1]),
            greaterThan(8),
            reason: 'LibreOffice must paint overlined R on the arc; '
                'a=${inkAt(plates[0])} r=${inkAt(plates[1])} '
                'c=${inkAt(plates[2])}',
          );
          expect(
            inkAt(plates[2]),
            greaterThan(8),
            reason: 'LibreOffice must paint overlined C on the arc; '
                'a=${inkAt(plates[0])} r=${inkAt(plates[1])} '
                'c=${inkAt(plates[2])}',
          );
        }
        if (entry.key == 'curved_text_highlight') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioCurvedTextPlate)
              .toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(3));
          expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
          expect(plates[1].fill.foreground?.value, 0xFF00FF00);
          expect(plates[2].fill.foreground?.value, 0xFF00FF00);
          expect(
            reopened.pages.first.shapes.where(isLibvisioHighlightPlate),
            isEmpty,
          );
        }
        if (entry.key == 'curved_text_highlight' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          var limePixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
              magentaPixels++;
            }
            if (pixel.g > 200 && pixel.r < 40) {
              limePixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(10),
            reason: 'LibreOffice must paint magenta Highlight on arc A; '
                'magentaPixels=$magentaPixels limePixels=$limePixels',
          );
          expect(
            limePixels,
            greaterThan(10),
            reason: 'LibreOffice must paint lime Highlight on arc R/C; '
                'magentaPixels=$magentaPixels limePixels=$limePixels',
          );
        }
        if (entry.key == 'curved_text_bullet') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioCurvedTextPlate)
              .toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(
            plates.map((p) => p.richText.plainText).join(),
            '\u25a0ARC',
            reason:
                'Draw never paints text:bullet-char; the glyph rides the arc',
          );
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CurvedTextBullet');
          expect(source.richText.runs.single.paraStyle.bullet, 0);
          expect(source.richText.runs.single.paraStyle.indentFirstInches, 0);
        }
        if (entry.key == 'curved_text_bullet' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(10),
            reason: 'LibreOffice must paint the Curved Text bullet glyph; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'shape_inside_highlight') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioShapeInsidePlate)
              .toList();
          expect(plates, isNotEmpty);
          expect(
            plates.any((p) => p.fill.foreground?.value == 0xFFFF00FF),
            isTrue,
          );
          expect(
            plates.any((p) => p.fill.foreground?.value == 0xFF00FF00),
            isTrue,
          );
          expect(
            reopened.pages.first.shapes.where(isLibvisioHighlightPlate),
            isEmpty,
          );
        }
        if (entry.key == 'shape_inside_highlight' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          var limePixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
              magentaPixels++;
            }
            if (pixel.g > 200 && pixel.r < 40) {
              limePixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(10),
            reason: 'LibreOffice must paint magenta Highlight on outline HI; '
                'magentaPixels=$magentaPixels limePixels=$limePixels',
          );
          expect(
            limePixels,
            greaterThan(10),
            reason: 'LibreOffice must paint lime Highlight on outline flow; '
                'magentaPixels=$magentaPixels limePixels=$limePixels',
          );
        }
        if (entry.key == 'shape_inside_field') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioShapeInsidePlate)
              .toList();
          expect(plates, isNotEmpty);
          expect(
            plates.map((p) => p.richText.plainText).join(),
            contains('42'),
            reason:
                'Draw never paints a rectangular <fld>; the Value is on the plate',
          );
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ShapeInsideField');
          expect(source.shapeInside, isFalse);
          expect(source.richText.textBlock.hideText, isTrue);
        }
        if (entry.key == 'shape_inside_field' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(10),
            reason: 'LibreOffice must paint the Shape Inside field Value; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'shape_inside_bullet') {
          final reopened = parser.parse(entry.value);
          final plates = reopened.pages.first.shapes
              .where(isLibvisioShapeInsidePlate)
              .toList();
          expect(plates, isNotEmpty);
          expect(
            plates.map((p) => p.richText.plainText).join(),
            contains('\u25a0'),
            reason:
                'Draw never paints text:bullet-char; the glyph is on the plate',
          );
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'ShapeInsideBullet');
          expect(source.shapeInside, isFalse);
          expect(source.richText.textBlock.hideText, isTrue);
          expect(source.richText.runs.single.paraStyle.bullet, 0);
        }
        if (entry.key == 'shape_inside_bullet' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
            }
          }
          expect(
            magentaPixels,
            greaterThan(10),
            reason: 'LibreOffice must paint the Shape Inside bullet glyph; '
                'magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'bullet_field') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'BulletField');
          expect(shape.richText.runs.single.paraStyle.bullet, 0);
          expect(
            shape.richText.plainText,
            startsWith('\u25a0 42'),
            reason:
                'Draw never paints text:bullet-char; the glyph is in the text',
          );
          expect(
            shape.richText.runs.single.fieldSpans.single,
            const VsdxFieldSpan(start: 2, length: 2, ix: 0),
          );
          expect(shape.fields, isNotEmpty);
          expect(shape.fields.first.valueFormula, 'PAGENUMBER()');
        }
        if (entry.key == 'bullet_field' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          int magentaCount(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
                  count++;
                }
              }
            }
            return count;
          }

          // Hanging indent holds the baked ■; the field "42" sits to its right.
          final glyphInk = magentaCount(2.30, 5.05, 2.85, 5.95);
          final fieldInk = magentaCount(3.05, 5.05, 5.40, 5.95);
          expect(
            glyphInk,
            greaterThan(12),
            reason: 'LibreOffice must paint the baked bullet beside the field; '
                'glyphInk=$glyphInk fieldInk=$fieldInk',
          );
          expect(
            fieldInk,
            greaterThan(12),
            reason: 'LibreOffice must still paint the field Value; '
                'glyphInk=$glyphInk fieldInk=$fieldInk',
          );
        }
        if (entry.key == 'bullet_font_size') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'BulletFontSize');
          expect(shape.richText.runs.length, greaterThanOrEqualTo(2));
          expect(shape.richText.runs.first.text, startsWith('\u25a0'));
          expect(
            shape.richText.runs.first.charStyle.fontSizeInches,
            closeTo(0.7, 1e-6),
          );
          expect(
            shape.richText.runs.any(
              (run) =>
                  run.text.contains('A') &&
                  (run.charStyle.fontSizeInches - 0.22).abs() < 1e-6,
            ),
            isTrue,
          );
          expect(shape.richText.runs.first.paraStyle.bullet, 0);
        }
        if (entry.key == 'bullet_font_size' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          var minY = rendered.height;
          var maxY = 0;
          for (var y = 0; y < rendered.height; y++) {
            for (var x = 0; x < rendered.width; x++) {
              final pixel = rendered.getPixel(x, y);
              if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
                magentaPixels++;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
              }
            }
          }
          expect(
            magentaPixels,
            greaterThan(20),
            reason: 'LibreOffice must paint the oversized bullet marker; '
                'magentaPixels=$magentaPixels',
          );
          expect(
            maxY - minY,
            greaterThan(40),
            reason: 'Draw must collect BulletFontSize on the baked glyph run; '
                'magentaHeight=${maxY - minY} magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'mixed_script') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'MixedScript');
          expect(shape.richText.runs, hasLength(2));
          expect(shape.richText.runs[0].text, 'Hi');
          expect(shape.richText.runs[0].charStyle.fontFamily, 'Arial');
          expect(shape.richText.runs[1].text, '世界');
          expect(
            shape.richText.runs[1].charStyle.fontFamily,
            'Microsoft YaHei',
          );
        }
        if (entry.key == 'mixed_script' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magentaPixels = 0;
          var minX = rendered.width;
          var maxX = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
              magentaPixels++;
              if (pixel.x < minX) minX = pixel.x;
              if (pixel.x > maxX) maxX = pixel.x;
            }
          }
          expect(
            magentaPixels,
            greaterThan(40),
            reason: 'LibreOffice must paint mixed Latin+CJK after the Font split; '
                'magentaPixels=$magentaPixels',
          );
          expect(
            maxX - minX,
            greaterThan(70),
            reason: 'Draw must paint 世界 beside Hi, not drop the CJK run; '
                'magentaWidth=${maxX - minX} magentaPixels=$magentaPixels',
          );
        }
        if (entry.key == 'horz_align_full') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'HorzAlignFull');
          expect(
            shape.richText.runs.single.paraStyle.horizontalAlign,
            VsdxHorzAlign.justify,
          );
        }
        if (entry.key == 'horz_align_full' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int magenta}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
                  magenta++;
                }
              }
            }
            return (magenta: magenta);
          }

          // Draw used to treat HorzAlign=full as left. Two short words on a
          // 2.6" band leave a wide gap; justify parks the second word on the
          // right edge of the first line.
          final left = countWindow(2.95, 6.1, 3.7, 6.7);
          final right = countWindow(5.05, 6.1, 5.55, 6.7);
          expect(
            left.magenta,
            greaterThan(10),
            reason: 'LibreOffice must paint AA on the first wrapped line; '
                'left=${left.magenta} right=${right.magenta}',
          );
          expect(
            right.magenta,
            greaterThan(8),
            reason: 'Draw must collect HorzAlign=3 (justify), not fall back '
                'to left from fo:text-align=full; '
                'left=${left.magenta} right=${right.magenta}',
          );
        }
        if (entry.key == 'default_tab_stop') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'DefaultTabStop');
          expect(shape.richText.runs.single.text, contains('\t'));
          expect(
            shape.richText.textBlock.defaultTabStopInches,
            closeTo(2.0, 1e-9),
          );
          expect(shape.richText.tabSets, isNotEmpty);
          expect(
            shape.richText.tabSets.single.stops
                .any((s) => (s.positionInches - 2.0).abs() < 1e-6),
            isTrue,
          );
        }
        if (entry.key == 'default_tab_stop' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int magenta}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) {
                  magenta++;
                }
              }
            }
            return (magenta: magenta);
          }

          // Draw ignores style:tab-stop-distance and jumps 0.5". Explicit
          // Tabs stops park B at +2" from the text-band origin.
          final glyph = countWindow(1.22, 5.55, 1.72, 6.18);
          final half = countWindow(1.78, 5.55, 2.35, 6.18);
          final two = countWindow(3.15, 5.55, 3.85, 6.18);
          expect(
            glyph.magenta,
            greaterThan(8),
            reason: 'LibreOffice must paint A before the tab; '
                'A=${glyph.magenta} half=${half.magenta} two=${two.magenta}',
          );
          expect(
            two.magenta,
            greaterThan(8),
            reason: 'Draw must collect baked 2" Tabs stops, not jump 0.5"; '
                'A=${glyph.magenta} half=${half.magenta} two=${two.magenta}',
          );
          expect(
            half.magenta,
            lessThan(glyph.magenta),
            reason: 'B must not land on Draw\'s 0.5" default tab; '
                'A=${glyph.magenta} half=${half.magenta} two=${two.magenta}',
          );
        }
        if (entry.key == 'vector_emf_foreign_data' ||
            entry.key == 'text_emf_foreign_data' ||
            entry.key == 'hatch_emf_foreign_data' ||
            entry.key == 'webp_foreign_data' ||
            entry.key == 'dib_foreign_data' ||
            entry.key == 'ico_foreign_data') {
          final reopened = parser.parse(entry.value);
          final shape = reopened.pages.first.shapes.single;
          expect(shape.foreignType, 'Bitmap');
          expect(shape.foreignCompressionType, 'PNG');
        }
        if ((entry.key == 'vector_emf_foreign_data' ||
                entry.key == 'text_emf_foreign_data') &&
            pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magenta = 0;
          var blue2 = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
            if ((pixel.r - 114).abs() < 12 &&
                (pixel.g - 159).abs() < 12 &&
                (pixel.b - 207).abs() < 12) {
              blue2++;
            }
          }
          expect(
            magenta,
            greaterThan(80),
            reason: 'Draw must paint the baked ${entry.key}, not Blue 2; '
                'magenta=$magenta blue2=$blue2',
          );
          expect(
            blue2,
            lessThan(magenta),
            reason: 'Blue 2 graphic style must not hide ${entry.key}; '
                'magenta=$magenta blue2=$blue2',
          );
          if (entry.key == 'vector_emf_foreign_data') {
            expect(
              magenta,
              greaterThan(blue2 * 4),
              reason: 'baked vector EMF must dominate the Foreign box; '
                  'magenta=$magenta blue2=$blue2',
            );
          }
        }
        if (entry.key == 'hatch_emf_foreign_data' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var green = 0;
          var blue2 = 0;
          for (final pixel in rendered) {
            if (pixel.g > pixel.r + 20 &&
                pixel.g > pixel.b + 20 &&
                pixel.g > 80) {
              green++;
            }
            if ((pixel.r - 114).abs() < 12 &&
                (pixel.g - 159).abs() < 12 &&
                (pixel.b - 207).abs() < 12) {
              blue2++;
            }
          }
          expect(
            green,
            greaterThan(40),
            reason: 'Draw must paint baked HS_CROSS hatch, not Blue 2; '
                'green=$green blue2=$blue2',
          );
          expect(
            blue2,
            lessThan(green),
            reason: 'Blue 2 graphic style must not hide hatch EMF; '
                'green=$green blue2=$blue2',
          );
        }
        if ((entry.key == 'webp_foreign_data' ||
                entry.key == 'dib_foreign_data' ||
                entry.key == 'ico_foreign_data') &&
            pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magenta = 0;
          var blue2 = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
            if ((pixel.r - 114).abs() < 12 &&
                (pixel.g - 159).abs() < 12 &&
                (pixel.b - 207).abs() < 12) {
              blue2++;
            }
          }
          expect(
            magenta,
            greaterThan(80),
            reason: 'Draw must paint baked ${entry.key} PNG, not Blue 2; '
                'magenta=$magenta blue2=$blue2',
          );
          expect(
            blue2,
            lessThan(magenta),
            reason: 'Blue 2 graphic style must not hide ${entry.key}; '
                'magenta=$magenta blue2=$blue2',
          );
        }
        if (entry.key == 'grad3_fill_gradient') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'Grad3');
          expect(source.fill.pattern, 0);
          expect(source.fill.hasGradient, isFalse);
          expect(
            reopened.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'grad3_fill_gradient' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          var magenta = 0;
          var green = 0;
          var blue = 0;
          for (final pixel in rendered) {
            if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
            if (pixel.g > 160 && pixel.r < 100 && pixel.b < 100) green++;
            if (pixel.b > 160 && pixel.r < 100 && pixel.g < 100) blue++;
          }
          expect(
            magenta,
            greaterThan(40),
            reason: 'Draw must paint the magenta stop, not FillForegnd/FillBkgnd; '
                'magenta=$magenta green=$green blue=$blue',
          );
          expect(
            green,
            greaterThan(40),
            reason: 'Draw must paint the middle green stop; '
                'magenta=$magenta green=$green blue=$blue',
          );
          expect(
            blue,
            greaterThan(40),
            reason: 'Draw must paint the blue stop; '
                'magenta=$magenta green=$green blue=$blue',
          );
        }
        if ((entry.key == 'shape_inside' ||
                entry.key == 'shape_inside_flipy') &&
            pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes.where(isLibvisioShapeInsidePlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates.length, greaterThanOrEqualTo(2));
          expect(plates.first.width, lessThan(plates.last.width - 0.2));

          int darkCount(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          final lineInk = darkCount(
            plates.first.pinX - 0.35,
            plates.first.pinY - 0.12,
            plates.first.pinX + 0.35,
            plates.first.pinY + 0.12,
          );
          final cornerInk = darkCount(2.8, 7.15, 3.15, 7.45);
          expect(
            lineInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the top outline band; '
                'line=$lineInk corner=$cornerInk',
          );
          expect(
            cornerInk,
            lessThan(3),
            reason: 'LibreOffice must not wrap the label as a full rectangle '
                'into the ellipse corner; line=$lineInk corner=$cornerInk',
          );
        }
        if (entry.key == 'auto_rotate') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes.single;
          expect(source.autoRotateLabel, isFalse);
          expect(
            source.richText.textBlock.angleRad,
            closeTo(math.pi / 4, 1e-6),
          );
          expect(source.richText.textBlock.widthInches, greaterThan(0.5));
        }
        if (entry.key == 'edge_label') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes.single;
          expect(source.richText.textBlock.pinXInches, isNotNull);
          expect(source.richText.textBlock.pinYInches, isNotNull);
          final pin = reopened.pages.first.localToPageDeep(
            source.id,
            Offset2D(
              source.richText.textBlock.pinXInches!,
              source.richText.textBlock.pinYInches!,
            ),
          );
          expect(pin.x, closeTo(7, 0.2));
          expect(pin.y, closeTo(7, 0.2));
          expect(source.richText.textBlock.widthInches, greaterThan(0.5));
        }
        if (entry.key == 'auto_rotate' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;

          int darkCount(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          // Midpoint of (2,3)-(6.5,7.5) is (4.25, 5.25). Sample along the
          // +45° tangent (where rotated "ROTATE" sits) vs the horizontal
          // from the same pin (where an unrotated Draw label would sit).
          final tangentInk = darkCount(4.55, 5.55, 4.95, 5.95);
          final horizontalInk = darkCount(4.70, 5.10, 5.20, 5.40);
          expect(
            tangentInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the label along the route; '
                'tangent=$tangentInk horizontal=$horizontalInk',
          );
          expect(
            horizontalInk,
            lessThan(tangentInk),
            reason: 'LibreOffice must not leave the label axis-aligned; '
                'tangent=$tangentInk horizontal=$horizontalInk',
          );
        }
        if (entry.key == 'text_direction_auto_rotate') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'TextDirectionAutoRotate');
          expect(source.autoRotateLabel, isFalse);
          expect(source.richText.textBlock.textDirection, 0);
          expect(
            source.richText.textBlock.angleRad,
            closeTo(math.pi / 4, 1e-6),
          );
          expect(
            source.richText.textBlock.heightInches,
            greaterThan(source.richText.textBlock.widthInches! + 0.15),
          );
        }
        if (entry.key == 'text_direction_auto_rotate' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          int countMagenta(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var n = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) n++;
              }
            }
            return n;
          }

          // Midpoint of (2,3)-(6.5,7.5) is (4.25, 5.25). A tall plate
          // rotated +45° (Y-up CCW) has its long axis along 135°.
          final tangent = countMagenta(3.85, 5.35, 4.15, 5.65);
          final vertical = countMagenta(4.10, 5.70, 4.40, 6.10);
          expect(
            tangent,
            greaterThan(12),
            reason: 'LibreOffice must tilt the vertical label with the route; '
                'tangent=$tangent vertical=$vertical',
          );
          expect(
            tangent,
            greaterThan(vertical),
            reason: 'Draw must not keep the swapped plate axis-aligned; '
                'tangent=$tangent vertical=$vertical',
          );
        }
        if (entry.key == 'edge_label' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;

          int darkCount(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          // Elbow (7, 7) vs Begin–End box centre (4, 4).
          final elbowInk = darkCount(6.55, 6.55, 7.45, 7.45);
          final boxInk = darkCount(3.55, 3.55, 4.45, 4.45);
          expect(
            elbowInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the label on the route elbow; '
                'elbow=$elbowInk box=$boxInk',
          );
          expect(
            boxInk,
            lessThan(3),
            reason: 'LibreOffice must not park the label at the 1-D box '
                'centre; elbow=$elbowInk box=$boxInk',
          );
        }
        if (entry.key == 'edge_label_wide') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes.single;
          expect(source.richText.textBlock.pinXInches, isNotNull);
          expect(source.richText.textBlock.widthInches, lessThan(2.5));
          final pin = reopened.pages.first.localToPageDeep(
            source.id,
            Offset2D(
              source.richText.textBlock.pinXInches!,
              source.richText.textBlock.pinYInches!,
            ),
          );
          expect(pin.x, closeTo(7, 0.2));
          expect(pin.y, closeTo(7, 0.2));
        }
        if (entry.key == 'edge_label_wide' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;

          int darkCount(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                final luma =
                    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                if (luma < 180) count++;
              }
            }
            return count;
          }

          // Tight plate on the elbow (7, 7). Missing TxtPin parks
          // m_txtxform at pin 0 or the Begin–End centre (4, 4). The
          // horizontal rail already occupies y=7, so leftover 6"
          // left-align cannot be sampled there — TxtWidth is checked
          // on the reopened model instead.
          final elbowInk = darkCount(6.55, 6.55, 7.45, 7.45);
          final boxInk = darkCount(3.55, 3.55, 4.45, 4.45);
          expect(
            elbowInk,
            greaterThan(8),
            reason: 'LibreOffice must paint the wide-TxtWidth label on the '
                'route elbow; elbow=$elbowInk box=$boxInk',
          );
          expect(
            boxInk,
            lessThan(3),
            reason: 'LibreOffice must not park the label at the 1-D box '
                'centre; elbow=$elbowInk box=$boxInk',
          );
        }
        if (entry.key == 'highlight_mixed_edge') {
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          final plates = page.shapes.where(isLibvisioHighlightPlate).toList()
            ..sort(
              (a, b) => int.parse(a.name.split('.')[1])
                  .compareTo(int.parse(b.name.split('.')[1])),
            );
          expect(plates, hasLength(2));
          expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
          expect(plates[1].fill.foreground?.value, 0xFF00FF00);
          expect(plates[0].pinX, closeTo(7, 0.6));
          expect(plates[0].pinY, closeTo(7, 0.6));
          expect(plates[1].pinX, greaterThan(plates[0].pinX + 0.15));
          expect(
            page.shapes
                .firstWhere((s) => s.name == 'HighlightMixedEdge')
                .richText
                .textBlock
                .hideText,
            isTrue,
          );
        }
        if (entry.key == 'highlight_mixed_edge' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({int magenta, int lime}) countWindow(
            double x0,
            double y0,
            double x1,
            double y1,
          ) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var magenta = 0;
            var lime = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                if (pixel.r > 200 && pixel.g < 40 && pixel.b > 200) {
                  magenta++;
                }
                if (pixel.g > 200 && pixel.r < 40) lime++;
              }
            }
            return (magenta: magenta, lime: lime);
          }

          final left = countWindow(6.35, 6.55, 6.95, 7.45);
          final right = countWindow(7.05, 6.55, 7.65, 7.45);
          final box = countWindow(3.55, 3.55, 4.45, 4.45);
          expect(
            left.magenta,
            greaterThan(10),
            reason: 'LibreOffice must paint magenta on the route elbow; '
                'leftM=${left.magenta} leftL=${left.lime} '
                'rightM=${right.magenta} rightL=${right.lime} '
                'boxM=${box.magenta} boxL=${box.lime}',
          );
          expect(
            right.lime,
            greaterThan(10),
            reason: 'LibreOffice must paint lime on the route elbow; '
                'leftM=${left.magenta} leftL=${left.lime} '
                'rightM=${right.magenta} rightL=${right.lime} '
                'boxM=${box.magenta} boxL=${box.lime}',
          );
          expect(
            left.magenta,
            greaterThan(left.lime),
            reason: 'left plate must stay magenta; '
                'leftM=${left.magenta} leftL=${left.lime}',
          );
          expect(
            right.lime,
            greaterThan(right.magenta),
            reason: 'right plate must stay lime; '
                'rightM=${right.magenta} rightL=${right.lime}',
          );
          expect(
            box.magenta + box.lime,
            lessThan(5),
            reason: 'markers must not sit on the Begin–End centre; '
                'boxM=${box.magenta} boxL=${box.lime}',
          );
        }
        if (entry.key == 'custom_dash') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'CustomDash');
          expect(source.line.pattern, 1);
          expect(source.line.customDashPattern, isNull);
          expect(
            source.userCells.any(
              (cell) => cell.name == VsdxShape.userDashPattern,
            ),
            isFalse,
          );
          final moves = source.geometries
              .expand((geometry) => geometry.commands)
              .whereType<MoveTo>()
              .length;
          expect(moves, greaterThan(1));
        }
        if (entry.key == 'custom_dash' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // [8,4] × 0.15" → 1.2" dash / 0.6" gap. A LinePattern-2 snap
          // ([6,3] × 0.15") would still be inking at x=2.5.
          final ink = meanLuma(1.50, 5.42, 1.70, 5.58);
          final gap = meanLuma(2.40, 5.42, 2.60, 5.58);
          expect(
            ink,
            lessThan(gap - 15),
            reason: 'LibreOffice must paint the custom dash, not the nearest '
                'built-in LinePattern; ink=$ink gap=$gap',
          );
        }
        if (entry.key == 'flow_dash') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FlowDash');
          expect(source.flowAnimation, isFalse);
          expect(source.line.pattern, 1);
          expect(source.line.customDashPattern, isNull);
          final moves = source.geometries
              .expand((geometry) => geometry.commands)
              .whereType<MoveTo>()
              .length;
          expect(moves, greaterThan(1));
        }
        if (entry.key == 'flow_dash' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // 8 CSS px @ 96dpi = 0.0833" dash / gap from x=1.
          final ink = meanLuma(1.02, 5.48, 1.06, 5.52);
          final gap = meanLuma(1.11, 5.48, 1.15, 5.52);
          expect(
            ink,
            lessThan(gap - 15),
            reason: 'LibreOffice must paint the Flow Animation dash, not a '
                'solid LinePattern-1 stroke; ink=$ink gap=$gap',
          );
        }
        if (entry.key == 'dash_arrows') {
          final reopened = parser.parse(entry.value);
          for (final name in <String>['FlowDashArrow', 'CustomDashArrow']) {
            final source =
                reopened.pages.first.shapes.firstWhere((s) => s.name == name);
            expect(source.line.endArrow, 0, reason: name);
            expect(source.flowAnimation, isFalse, reason: name);
            expect(
              source.geometries.where((geometry) => !geometry.noFill).length,
              1,
              reason: '$name must keep one filled arrow Geometry',
            );
            final dashMoves = source.geometries
                .where((geometry) => geometry.noFill)
                .expand((geometry) => geometry.commands)
                .whereType<MoveTo>()
                .length;
            expect(dashMoves, greaterThan(1), reason: name);
          }
        }
        if (entry.key == 'dash_arrows' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // A marker on every dash would ink above the 0.04" stroke at the
          // first segment's tip. The baked 0.25" head sits only at x=7.
          final stray = meanLuma(1.04, 5.56, 1.12, 5.68);
          final head = meanLuma(6.80, 5.42, 7.02, 5.58);
          expect(
            head,
            lessThan(stray - 15),
            reason: 'LibreOffice must keep one arrow at the route end, not a '
                'marker on every dash; head=$head stray=$stray',
          );
          // custom [8,8] × 0.04" → 0.32" dash; first tip at x=1.32.
          final customStray = meanLuma(1.26, 3.56, 1.34, 3.68);
          final customHead = meanLuma(6.80, 3.42, 7.02, 3.58);
          expect(
            customHead,
            lessThan(customStray - 15),
            reason: 'custom dash arrows must also stay a single head; '
                'head=$customHead stray=$customStray',
          );
        }
        if (entry.key == 'collapsed') {
          final reopened = parser.parse(entry.value);
          final host = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FoldedBox');
          expect(host.collapsed, isTrue);
          expect(host.children, hasLength(1));
          final child = host.children.single;
          expect(child.name, 'HiddenChild');
          expect(child.libvisioCollapsedHidden, isTrue);
          expect(child.geometries.every((g) => g.noShow), isTrue);
          expect(child.fill.pattern, 0);
          expect(child.line.pattern, 0);
          expect(child.richText.textBlock.hideText, isTrue);
        }
        if (entry.key == 'merged') {
          final reopened = parser.parse(entry.value);
          final table = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'MergeTable');
          expect(TableOps.isTable(table), isTrue);
          final covered =
              TableOps.cellsOf(table).where(TableOps.isCovered).single;
          expect(covered.libvisioCoveredHidden, isTrue);
          expect(covered.geometries.every((g) => g.noShow), isTrue);
          expect(covered.fill.pattern, 0);
          expect(covered.line.pattern, 0);
          expect(covered.richText.textBlock.hideText, isTrue);
        }
        if (entry.key == 'collapsed' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double luma, double r, double g, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumLuma = 0.0;
            var sumR = 0.0;
            var sumG = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                sumR += pixel.r;
                sumG += pixel.g;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) {
              return (luma: 255.0, r: 0.0, g: 255.0, b: 0.0);
            }
            return (
              luma: sumLuma / count,
              r: sumR / count,
              g: sumG / count,
              b: sumB / count,
            );
          }

          final host = page.shapes.firstWhere((s) => s.name == 'FoldedBox');
          final child = host.children.single;
          final hostBox = page.shapePageAabb(host.id)!;
          final childBox = page.shapePageAabb(child.id)!;
          expect(
            childBox.top,
            greaterThan(hostBox.top + 0.2),
            reason: 'folded child AABB must stick above the header so the '
                'hidden-band sample is not the blue title',
          );
          final header = mean(
            hostBox.left + 0.3,
            hostBox.top - 0.35,
            hostBox.right - 0.3,
            hostBox.top - 0.05,
          );
          expect(
            header.b,
            greaterThan(header.r + 20),
            reason: 'LibreOffice must keep the folded header; '
                'r=${header.r} b=${header.b} luma=${header.luma}',
          );
          // fold() keeps descendant local pins, so after the host shrinks
          // the child AABB overlaps the header and overshoots it. Sample
          // the overshoot — magenta if Draw still paints, paper if not.
          final hidden = mean(
            childBox.left + 0.15,
            hostBox.top + 0.08,
            childBox.right - 0.15,
            childBox.top - 0.05,
          );
          expect(
            hidden.g,
            greaterThan(180),
            reason: 'LibreOffice must not paint the magenta child of a '
                'folded container; g=${hidden.g} luma=${hidden.luma}',
          );
          expect(
            hidden.luma,
            greaterThan(200),
            reason: 'folded descendants must stay off the sheet; '
                'g=${hidden.g} luma=${hidden.luma}',
          );
        }
        if (entry.key == 'pattern_dash_trans') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'PatternDashTrans');
          expect(source.line.pattern, 0);
          expect(
            source.geometries.where((geometry) => !geometry.noFill).length,
            greaterThan(1),
          );
        }
        if (entry.key == 'pattern_dash_trans' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // LinePattern 2: [6,3] × 0.15" → 0.9" dash / 0.45" gap from x=1.
          final ink = meanLuma(1.30, 5.42, 1.50, 5.58);
          final gap = meanLuma(2.05, 5.42, 2.25, 5.58);
          expect(
            ink,
            lessThan(gap - 15),
            reason: 'LibreOffice must keep LinePattern 2 gaps in the '
                'LineColorTrans ribbon; ink=$ink gap=$gap',
          );
        }
        if (entry.key == 'tight_miter') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'TightMiter');
          expect(source.line.roundingInches, closeTo(0, 1e-12));
          expect(source.line.miterLimit, closeTo(4, 1e-12));
          expect(
            source.userCells.any(
              (cell) => cell.name == VsdxShape.userMiterLimit,
            ),
            isFalse,
          );
          expect(
            source.geometries.single.commands.whereType<RelQuadBezTo>(),
            isEmpty,
          );
          expect(
            source.geometries.single.commands.whereType<LineTo>().length,
            greaterThan(2),
          );
        }
        if (entry.key == 'tight_miter' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // Elbow at page (5.25, 4.5). Outer miter tip of a 0.2" 90° join
          // is (5.35, 4.4); Draw's default miterlimit 4 would still ink it.
          final spike = meanLuma(5.32, 4.37, 5.38, 4.43);
          final body = meanLuma(4.15, 4.42, 4.35, 4.58);
          expect(
            body,
            lessThan(80),
            reason: 'LibreOffice must still stroke the L; body=$body',
          );
          expect(
            spike,
            greaterThan(body + 40),
            reason: 'LibreOffice must not keep the clipped miter spike; '
                'spike=$spike body=$body',
          );
        }
        if (entry.key == 'long_miter') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'LongMiter');
          expect(source.line.pattern, 0);
          expect(source.fill.hasFill, isTrue);
          expect(
            source.userCells.any(
              (cell) => cell.name == VsdxShape.userMiterLimit,
            ),
            isFalse,
          );
        }
        if (entry.key == 'long_miter' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          final source = page.shapes.firstWhere((s) => s.name == 'LongMiter');
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          const pts = <Offset2D>[
            Offset2D(0.2, 1.0),
            Offset2D(2.5, 1.0),
            Offset2D(0.2, 1.45),
          ];
          const elbow = Offset2D(2.5, 1.0);
          double dist2(Offset2D p) {
            final dx = p.x - elbow.x;
            final dy = p.y - elbow.y;
            return dx * dx + dy * dy;
          }

          Offset2D farther(List<Offset2D> a, List<Offset2D> b) =>
              dist2(a[1]) >= dist2(b[1]) ? a[1] : b[1];
          final longTip = farther(
            offsetPolyline(pts, 0.12, miterLimit: 12),
            offsetPolyline(pts, -0.12, miterLimit: 12),
          );
          final clippedTip = farther(
            offsetPolyline(pts, 0.12, miterLimit: 4),
            offsetPolyline(pts, -0.12, miterLimit: 4),
          );
          // The needle tip is one pixel; sample the extra triangle Draw
          // would drop (between its miterlimit-4 face and the canvas spike).
          final probe = Offset2D(
            clippedTip.x + (longTip.x - clippedTip.x) * 0.4,
            clippedTip.y + (longTip.y - clippedTip.y) * 0.4,
          );
          double pageX(double x) => source.pinX + (x - source.effectiveLocPinX);
          double pageY(double y) => source.pinY + (y - source.effectiveLocPinY);
          final probeX = pageX(probe.x);
          final probeY = pageY(probe.y);
          final body =
              meanLuma(pageX(1.2), pageY(0.90), pageX(1.5), pageY(1.10));
          final spike = meanLuma(
            probeX - 0.05,
            probeY - 0.05,
            probeX + 0.05,
            probeY + 0.05,
          );
          expect(
            body,
            lessThan(80),
            reason: 'LibreOffice must still paint the stroke body; body=$body',
          );
          expect(
            spike,
            lessThan(80),
            reason: 'LibreOffice must keep the canvas miter spike Draw would '
                'bevel at miterlimit 4; spike=$spike at ($probeX,$probeY)',
          );
        }
        if (entry.key == 'filled_line_trans') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FilledLineTrans');
          expect(source.line.pattern, 0);
          expect(source.fill.foreground?.value, 0xFFFF0000);
          expect(
            reopened.pages.first.shapes.where(isLibvisioStrokeRibbonPlate),
            hasLength(1),
          );
        }
        if (entry.key == 'filled_line_trans' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // Left edge at x=3.25. Inner half of the 0.2" stroke sits on the
          // red fill. True alpha is dark red (~38 luma); a white-premultiplied
          // opaque gray stroke would be ~128.
          final interior = meanLuma(4.15, 5.40, 4.35, 5.60);
          final innerStroke = meanLuma(3.28, 5.40, 3.34, 5.60);
          expect(
            interior,
            lessThan(100),
            reason: 'LibreOffice must keep the red fill; interior=$interior',
          );
          expect(
            innerStroke,
            lessThan(90),
            reason: 'LibreOffice must composite the stroke over the fill, not '
                'premultiply toward white; inner=$innerStroke interior=$interior',
          );
        }
        if (entry.key == 'filled_line_trans_theme') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'LineTransTheme');
          expect(source.line.pattern, 0);
          expect(source.fill.foreground?.value, 0xFFFF0000);
          final plate = reopened.pages.first.shapes
              .where(isLibvisioStrokeRibbonPlate)
              .single;
          expect(
            plate.fill.foreground?.value,
            VsdxTheme.office.resolve(ThemeSlot.accent6)!.value,
          );
          expect(plate.fill.themeForegroundIndex, isNull);
          expect(plate.fill.foregroundTransparency, closeTo(0.7, 1e-9));
        }
        if (entry.key == 'filled_line_trans_theme' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double r, double g}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumR = 0.0;
            var sumG = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumR += pixel.r;
                sumG += pixel.g;
                count++;
              }
            }
            if (count == 0) return (r: 0.0, g: 0.0);
            return (r: sumR / count, g: sumG / count);
          }

          final body = mean(3.9, 5.2, 4.6, 5.8);
          final halo = mean(5.78, 5.2, 5.88, 5.8);
          expect(
            body.r,
            greaterThan(body.g + 40),
            reason: 'LibreOffice must still paint the red fill; '
                'bodyR=${body.r} haloR=${halo.r} haloG=${halo.g}',
          );
          expect(
            halo.g,
            greaterThan(halo.r + 8),
            reason: 'LibreOffice must paint the faded Office accent6 stroke, '
                'not the black fallback; '
                'haloR=${halo.r} haloG=${halo.g}',
          );
          expect(
            halo.r,
            greaterThan(160),
            reason: 'FillForegndTrans must fade the frozen accent6 over white; '
                'haloR=${halo.r} haloG=${halo.g}',
          );
        }
        if (entry.key == 'filled_line_trans_compound') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FilledCompoundTrans');
          expect(source.fill.foreground?.value, 0xFFFF0000);
          expect(source.line.pattern, 0);
          expect(source.line.compoundType, 0);
          expect(
            reopened.pages.first.shapes.where(isLibvisioStrokeRibbonPlate),
            hasLength(1),
          );
          expect(
            reopened.pages.first.shapes
                .where(isLibvisioStrokeRibbonPlate)
                .single
                .geometries
                .where((g) => !g.noFill)
                .length,
            greaterThanOrEqualTo(2),
          );
        }
        if (entry.key == 'filled_line_trans_compound' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          final interior = meanLuma(4.1, 5.4, 4.4, 5.6);
          final innerRail = meanLuma(2.80, 5.4, 2.88, 5.6);
          final gap = meanLuma(2.72, 5.45, 2.78, 5.55);
          final outerRail = meanLuma(2.61, 5.45, 2.68, 5.55);
          expect(
            interior,
            lessThan(100),
            reason: 'LibreOffice must keep the red fill; interior=$interior',
          );
          expect(
            innerRail,
            lessThan(90),
            reason: 'LibreOffice must composite the inner rail over the fill; '
                'inner=$innerRail interior=$interior gap=$gap outer=$outerRail',
          );
          expect(
            innerRail,
            greaterThan(20),
            reason: 'CompoundType LineColorTrans must stay translucent, not '
                'an opaque black rail; inner=$innerRail',
          );
          expect(
            gap,
            greaterThan(innerRail + 15),
            reason: 'LibreOffice must keep the CompoundType gap, not one fat '
                'stroke; gap=$gap inner=$innerRail outer=$outerRail',
          );
          expect(
            outerRail,
            lessThan(220),
            reason: 'LibreOffice must paint the outer rail on the page; '
                'outer=$outerRail gap=$gap',
          );
        }
        if (entry.key == 'filled_line_trans_dash') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FilledDashTrans');
          expect(source.fill.foreground?.value, 0xFFFF0000);
          expect(source.line.pattern, 0);
          expect(
            reopened.pages.first.shapes.where(isLibvisioStrokeRibbonPlate),
            hasLength(1),
          );
          expect(
            reopened.pages.first.shapes
                .where(isLibvisioStrokeRibbonPlate)
                .single
                .geometries
                .where((g) => !g.noFill)
                .length,
            greaterThan(1),
          );
        }
        if (entry.key == 'filled_line_trans_dash' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          final interior = meanLuma(4.1, 5.4, 4.4, 5.6);
          expect(
            interior,
            lessThan(100),
            reason: 'LibreOffice must keep the red fill; interior=$interior',
          );
        }
        if (entry.key == 'filled_line_trans_arrows') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'FilledOpenArrows');
          expect(source.fill.foreground?.value, 0xFFFF0000);
          expect(source.line.pattern, 0);
          expect(source.line.beginArrow, 0);
          expect(source.line.endArrow, 0);
          expect(
            reopened.pages.first.shapes.where(isLibvisioStrokeRibbonPlate),
            hasLength(1),
          );
          expect(
            reopened.pages.first.shapes
                .where(isLibvisioStrokeRibbonPlate)
                .single
                .geometries
                .where((g) => !g.noFill)
                .length,
            greaterThan(1),
          );
        }
        if (entry.key == 'round_cap_miter') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'RoundCapMiter');
          expect(source.line.cap, LineCap.extended);
          expect(source.line.pattern, 1);
        }
        if (entry.key == 'round_cap_miter' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          double meanLuma(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sum = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                count++;
              }
            }
            return count == 0 ? 255 : sum / count;
          }

          // Bottom-left at (3.25, 4.90). A round join (r=0.12) misses the
          // 45° sample at ~0.13"; a miter square covers it.
          final corner = meanLuma(3.15, 4.80, 3.17, 4.82);
          expect(
            corner,
            lessThan(80),
            reason: 'LibreOffice must miter the elbow Draw would round-join '
                'from LineCap.round; corner=$corner',
          );
        }
        if (entry.key == 'fill_gradient_pattern0') {
          final reopened = parser.parse(entry.value);
          final source = reopened.pages.first.shapes
              .firstWhere((s) => s.name == 'GradientNoPattern');
          expect(source.fill.hasFill, isTrue);
          expect(source.fill.pattern, inInclusiveRange(25, 40));
          expect(source.fill.paintGradient, isNotNull);
        }
        if (entry.key == 'fill_gradient_pattern0' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double luma, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumLuma = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (luma: 255.0, b: 0.0);
            return (luma: sumLuma / count, b: sumB / count);
          }

          final centre = mean(3.9, 5.2, 4.6, 5.8);
          expect(
            centre.luma,
            lessThan(200),
            reason: 'LibreOffice must fill omitted-FillPattern gradients; '
                'luma=${centre.luma}',
          );
          expect(
            centre.b,
            greaterThan(80),
            reason: 'LibreOffice must keep the blue wash, not a hollow box; '
                'b=${centre.b} luma=${centre.luma}',
          );
        }
        if (entry.key == 'zh_data') {
          final reopened = parser.parse(entry.value);
          final arrow = reopened.pages.first.findShapeById(147)!;
          expect(arrow.fill.hasFill, isTrue);
          expect(arrow.fill.pattern, isNot(0));
          expect(arrow.fill.paintGradient, isNotNull);
        }
        if (entry.key == 'zh_data' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double luma, double b}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumLuma = 0.0;
            var sumB = 0.0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                sumB += pixel.b;
                count++;
              }
            }
            if (count == 0) return (luma: 255.0, b: 0.0);
            return (luma: sumLuma / count, b: sumB / count);
          }

          // Sheet.147 pin (0.63, 3.39), rotated -90°: shaft through the pin.
          final shaft = mean(0.50, 3.20, 0.76, 3.58);
          expect(
            shaft.luma,
            lessThan(210),
            reason: 'LibreOffice must fill the 数据治理 chevron, not leave it '
                'hollow; luma=${shaft.luma}',
          );
          expect(
            shaft.b,
            greaterThan(70),
            reason: 'LibreOffice must keep the chevron wash; '
                'b=${shaft.b} luma=${shaft.luma}',
          );
        }
        if (entry.key == 'zh_iceberg') {
          final reopened = parser.parse(entry.value);
          final header = reopened.pages.first.findShapeById(925)!;
          final title = reopened.pages.first.findShapeById(926)!;
          expect(header.fill.hasFill, isTrue);
          expect(header.fill.pattern, inInclusiveRange(25, 40));
          expect(header.fill.paintGradient, isNotNull);
          expect(title.fill.pattern, 0);
          expect(title.geometries, isEmpty);
          expect(title.richText.runs.first.charStyle.color?.value, 0xFFFFFFFF);
        }
        if (entry.key == 'zh_iceberg' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '96',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final page = parser.parse(entry.value).pages.first;
          ({double luma, double b, int white}) mean(
              double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top =
                ((page.heightInches - y1) / page.heightInches * rendered.height)
                    .round();
            final bottom =
                ((page.heightInches - y0) / page.heightInches * rendered.height)
                    .round();
            var sumLuma = 0.0;
            var sumB = 0.0;
            var white = 0;
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                if (x < 0 ||
                    y < 0 ||
                    x >= rendered.width ||
                    y >= rendered.height) {
                  continue;
                }
                final pixel = rendered.getPixel(x, y);
                sumLuma += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
                sumB += pixel.b;
                if (pixel.r > 240 && pixel.g > 240 && pixel.b > 240) {
                  white++;
                }
                count++;
              }
            }
            if (count == 0) return (luma: 255.0, b: 0.0, white: 0);
            return (luma: sumLuma / count, b: sumB / count, white: white);
          }

          // Sheet.925 header bar around pin (8.27, 6.07).
          final bar = mean(7.2, 5.95, 9.2, 6.20);
          expect(
            bar.luma,
            lessThan(200),
            reason: 'LibreOffice must fill the 专业知识 header wash, not leave '
                'a white card; luma=${bar.luma}',
          );
          expect(
            bar.b,
            greaterThan(150),
            reason: 'LibreOffice must keep the purple header; '
                'b=${bar.b} luma=${bar.luma}',
          );
          final glyphs = mean(8.0, 5.98, 8.55, 6.18);
          expect(
            glyphs.white,
            greaterThan(40),
            reason: 'LibreOffice must keep white 「专业知识」 glyphs on the '
                'header; white=${glyphs.white} luma=${glyphs.luma}',
          );
        }
        // Still parseable after our write (independent of LibreOffice).
        expect(parser.parse(entry.value).pages, isNotEmpty);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  },
      // A headless soffice conversion alone takes most of the 30 second
      // default on a cold profile, and this case converts many packages.
      timeout: const Timeout(Duration(minutes: 5)),
      skip: (!require && soffice == null)
          ? 'LibreOffice soffice not installed'
          : false);
}

String? _resolveExecutable(String name) {
  final which = Process.runSync('which', <String>[name]);
  if (which.exitCode != 0) return null;
  final path = (which.stdout as String).trim();
  return path.isEmpty ? null : path;
}

Uint8List _solidPng() {
  final image = raster.Image(width: 8, height: 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgba(x, y, 255, 0, 0, 255);
    }
  }
  return raster.encodePng(image);
}

/// 16×16 magenta VP8 WebP (`package:image` 4.3's VP8L decoder throws).
Uint8List _magentaWebp() => Uint8List.fromList(const <int>[
      82, 73, 70, 70, 62, 0, 0, 0, 87, 69, 66, 80, 86, 80, 56, 32, 50, 0, 0, 0,
      208, 1, 0, 157, 1, 42, 16, 0, 16, 0, 1, 64, 38, 37, 160, 2, 116, 186, 1,
      248, 0, 3, 176, 0, 254, 235, 222, 47, 253, 227, 63, 220, 103, 251, 140,
      255, 229, 247, 255, 201, 178, 249, 1, 255, 32, 63, 254, 73, 192, 0,
    ]);

Uint8List _magentaDib() {
  final image = raster.Image(width: 16, height: 16);
  for (final pixel in image) {
    image.setPixelRgba(pixel.x, pixel.y, 255, 0, 255, 255);
  }
  final bmp = raster.encodeBmp(image);
  return Uint8List.fromList(bmp.sublist(14));
}

Uint8List _magentaIco() {
  final image = raster.Image(width: 16, height: 16);
  for (final pixel in image) {
    image.setPixelRgba(pixel.x, pixel.y, 255, 0, 255, 255);
  }
  return Uint8List.fromList(raster.encodeIco(image, singleFrame: true));
}

/// Top half red, bottom half blue — picture Reflection must show blue nearest
/// the source.
Uint8List _splitPng() {
  final image = raster.Image(width: 16, height: 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (y < 8) {
        image.setPixelRgba(x, y, 255, 0, 0, 255);
      } else {
        image.setPixelRgba(x, y, 0, 0, 255, 255);
      }
    }
  }
  return raster.encodePng(image);
}

/// Left half red, right half blue — cropped SoftEdges must show blue.
Uint8List _leftRightPng() {
  final image = raster.Image(width: 32, height: 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 32; x++) {
      if (x < 16) {
        image.setPixelRgba(x, y, 255, 0, 0, 255);
      } else {
        image.setPixelRgba(x, y, 0, 0, 255, 255);
      }
    }
  }
  return raster.encodePng(image);
}

Uint8List _uncompressedRgbTiff({required int width, required int height}) {
  final out = BytesBuilder(copy: false);
  void u16(int value) {
    out.add(<int>[value & 0xff, (value >> 8) & 0xff]);
  }

  void u32(int value) {
    out.add(<int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  void entry(int tag, int type, int count, int value, {bool short = false}) {
    u16(tag);
    u16(type);
    u32(count);
    if (short) {
      u16(value);
      u16(0);
    } else {
      u32(value);
    }
  }

  const entryCount = 10;
  const ifdOffset = 8;
  const ifdBytes = 2 + entryCount * 12 + 4;
  const bitsOffset = ifdOffset + ifdBytes;
  const pixelOffset = bitsOffset + 6;
  final pixelBytes = width * height * 3;

  u16(0x4949); // II (little endian)
  u16(42);
  u32(ifdOffset);
  u16(entryCount);
  entry(256, 4, 1, width); // ImageWidth
  entry(257, 4, 1, height); // ImageLength
  entry(258, 3, 3, bitsOffset); // BitsPerSample
  entry(259, 3, 1, 1, short: true); // Compression = none
  entry(262, 3, 1, 2, short: true); // Photometric = RGB
  entry(273, 4, 1, pixelOffset); // StripOffsets
  entry(277, 3, 1, 3, short: true); // SamplesPerPixel
  entry(278, 4, 1, height); // RowsPerStrip
  entry(279, 4, 1, pixelBytes); // StripByteCounts
  entry(284, 3, 1, 1, short: true); // PlanarConfiguration = chunky
  u32(0); // next IFD
  u16(8);
  u16(8);
  u16(8);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out.add(x < width ~/ 2 ? <int>[255, 0, 0] : <int>[0, 0, 255]);
    }
  }
  return out.takeBytes();
}

/// Minimal EMF whose STRETCHDIBITS record wraps a 24bpp DIB (left red, right blue).
Uint8List _rgbDibEmf({required int width, required int height}) {
  final row = ((width * 3 + 3) ~/ 4) * 4;
  final dib = Uint8List(40 + row * height);
  dib[0] = 40;
  dib[4] = width & 0xff;
  dib[5] = (width >> 8) & 0xff;
  dib[8] = height & 0xff;
  dib[9] = (height >> 8) & 0xff;
  dib[12] = 1;
  dib[14] = 24;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = 40 + y * row + x * 3;
      if (x < width ~/ 2) {
        dib[o] = 0x00;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0xff;
      } else {
        dib[o] = 0xff;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0x00;
      }
    }
  }
  final stretchBody = BytesBuilder()
    ..add(Uint8List(40))
    ..add(dib);
  final stretchPayload = stretchBody.toBytes();
  final stretchSize = 8 + stretchPayload.length;
  final stretchPad = (4 - (stretchSize % 4)) % 4;
  final out = BytesBuilder();
  final header = Uint8List(88);
  header[0] = 1;
  header[4] = 88;
  header[0x28] = 0x20;
  header[0x29] = 0x45;
  header[0x2A] = 0x4D;
  header[0x2B] = 0x46;
  out.add(header);
  final stretch = Uint8List(stretchSize + stretchPad);
  stretch[0] = 0x51;
  stretch[4] = stretch.length & 0xff;
  stretch[5] = (stretch.length >> 8) & 0xff;
  stretch.setRange(8, 8 + stretchPayload.length, stretchPayload);
  out.add(stretch);
  final eof = Uint8List(20);
  eof[0] = 0x0e;
  eof[4] = 20;
  out.add(eof);
  return out.toBytes();
}

/// Minimal vector EMF: solid magenta rectangle, no embedded DIB.
Uint8List _vectorMagentaEmf() {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add(const <int>[0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }
  u32(39);
  u32(24);
  u32(1);
  u32(0);
  u32(0x00FF00FF);
  u32(0);
  u32(37);
  u32(12);
  u32(1);
  u32(43);
  u32(24);
  i32(5);
  i32(5);
  i32(95);
  i32(95);
  u32(14);
  u32(20);
  u32(0);
  u32(0);
  u32(0);
  return out.toBytes();
}

/// Minimal vector EMF: green HS_CROSS hatch, no embedded DIB.
Uint8List _hatchGreenEmf() {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add(const <int>[0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }
  u32(18); // EMR_SETBKMODE
  u32(12);
  u32(2); // OPAQUE
  u32(25); // EMR_SETBKCOLOR
  u32(12);
  u32(0x00FFFFFF);
  u32(37); // EMR_SELECTOBJECT NULL_PEN
  u32(12);
  u32(0x80000008);
  u32(39); // EMR_CREATEBRUSHINDIRECT
  u32(24);
  u32(1);
  u32(2); // BS_HATCHED
  u32(0x00008000); // green COLORREF
  u32(4); // HS_CROSS
  u32(37); // EMR_SELECTOBJECT
  u32(12);
  u32(1);
  u32(43); // EMR_RECTANGLE
  u32(24);
  i32(5);
  i32(5);
  i32(95);
  i32(95);
  u32(14);
  u32(20);
  u32(0);
  u32(0);
  u32(0);
  return out.toBytes();
}

/// Minimal vector EMF: magenta ExtTextOutW "HI", no embedded DIB.
Uint8List _magentaTextEmf() {
  int aligned4(int value) => (value + 3) & ~3;
  final out = BytesBuilder();
  void addRecord(int type, Uint8List payload) {
    final size = aligned4(payload.length + 8);
    final header = ByteData(8)
      ..setUint32(0, type, Endian.little)
      ..setUint32(4, size, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(payload);
    for (var i = payload.length + 8; i < size; i++) {
      out.addByte(0);
    }
  }

  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 160, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464D4520, Endian.little);
  out.add(header.buffer.asUint8List());

  final font = ByteData(96)..setUint32(0, 1, Endian.little);
  const logFont = 4;
  font
    ..setInt32(logFont, 40, Endian.little)
    ..setInt32(logFont + 16, 700, Endian.little);
  for (var i = 0; i < 'Arial'.length; i++) {
    font.setUint16(logFont + 28 + i * 2, 'Arial'.codeUnitAt(i), Endian.little);
  }
  addRecord(82, font.buffer.asUint8List());
  addRecord(
    37,
    (ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List(),
  );
  addRecord(
    24,
    (ByteData(4)..setUint32(0, 0x00FF00FF, Endian.little)).buffer.asUint8List(),
  );

  const text = 'HI';
  final source = Uint8List(text.length * 2);
  final sourceData = ByteData.sublistView(source);
  for (var i = 0; i < text.length; i++) {
    sourceData.setUint16(i * 2, text.codeUnitAt(i), Endian.little);
  }
  const stringOffset = 76;
  final recordSize = aligned4(stringOffset + source.length);
  final payload = ByteData(recordSize - 8);
  payload
    ..setInt32(28, 20, Endian.little)
    ..setInt32(32, 30, Endian.little)
    ..setUint32(36, text.length, Endian.little)
    ..setUint32(40, stringOffset, Endian.little);
  payload.buffer.asUint8List().setRange(
        stringOffset - 8,
        stringOffset - 8 + source.length,
        source,
      );
  addRecord(84, payload.buffer.asUint8List());
  addRecord(14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

/// Placeable WMF whose STRETCHDIB record wraps a 24bpp DIB (left red, right blue).
Uint8List _rgbDibWmf({required int width, required int height}) {
  final row = ((width * 3 + 3) ~/ 4) * 4;
  final dib = Uint8List(40 + row * height);
  ByteData.sublistView(dib)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = 40 + y * row + x * 3;
      if (x < width ~/ 2) {
        dib[o] = 0x00;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0xff;
      } else {
        dib[o] = 0xff;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0x00;
      }
    }
  }

  Uint8List rec(int func, List<int> words) {
    final sizeWords = 3 + words.length;
    final out = Uint8List(sizeWords * 2);
    final data = ByteData.sublistView(out)
      ..setUint32(0, sizeWords, Endian.little)
      ..setUint16(4, func, Endian.little);
    for (var i = 0; i < words.length; i++) {
      data.setInt16(6 + i * 2, words[i], Endian.little);
    }
    return out;
  }

  final stretchBytes = 6 + 22 + dib.length;
  final stretchPadded = (stretchBytes + 1) & ~1;
  final stretch = Uint8List(stretchPadded);
  ByteData.sublistView(stretch)
    ..setUint32(0, stretchPadded ~/ 2, Endian.little)
    ..setUint16(4, 0x0F43, Endian.little)
    ..setUint32(6, 0x00CC0020, Endian.little)
    ..setUint16(10, 0, Endian.little)
    ..setInt16(12, height, Endian.little)
    ..setInt16(14, width, Endian.little)
    ..setInt16(16, 0, Endian.little)
    ..setInt16(18, 0, Endian.little)
    ..setInt16(20, height, Endian.little)
    ..setInt16(22, width, Endian.little)
    ..setInt16(24, 0, Endian.little)
    ..setInt16(26, 0, Endian.little);
  stretch.setRange(28, 28 + dib.length, dib);

  final records = <Uint8List>[
    rec(0x020B, <int>[0, 0]),
    rec(0x020C, <int>[height, width]),
    stretch,
  ];
  final size =
      18 + records.fold<int>(0, (sum, record) => sum + record.length) + 6;
  final wmf = Uint8List(size);
  ByteData.sublistView(wmf)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 9, Endian.little)
    ..setUint16(4, 0x0300, Endian.little)
    ..setUint32(6, size ~/ 2, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, stretchPadded ~/ 2, Endian.little);
  var offset = 18;
  for (final record in records) {
    wmf.setRange(offset, offset + record.length, record);
    offset += record.length;
  }
  ByteData.sublistView(wmf)
    ..setUint32(offset, 3, Endian.little)
    ..setUint16(offset + 4, 0, Endian.little);

  final out = Uint8List(22 + wmf.length);
  final placeable = ByteData.sublistView(out)
    ..setUint32(0, 0x9AC6CDD7, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setInt16(6, 0, Endian.little)
    ..setInt16(8, 0, Endian.little)
    ..setInt16(10, width, Endian.little)
    ..setInt16(12, height, Endian.little)
    ..setUint16(14, 1440, Endian.little)
    ..setUint32(16, 0, Endian.little);
  var checksum = 0;
  for (var i = 0; i < 10; i++) {
    checksum ^= placeable.getUint16(i * 2, Endian.little);
  }
  placeable.setUint16(20, checksum, Endian.little);
  out.setRange(22, out.length, wmf);
  return out;
}

String? _resolveSoffice() {
  final env = Platform.environment['SOFFICE'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  for (final name in <String>['soffice', 'libreoffice']) {
    final which = Process.runSync('which', <String>[name]);
    if (which.exitCode == 0) {
      final path = (which.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  const mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice';
  if (File(mac).existsSync()) return mac;
  return null;
}
