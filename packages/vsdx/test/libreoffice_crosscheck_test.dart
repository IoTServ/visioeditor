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
          ),
    );
    doc = doc.copyWith(
      images: doc.images.withImage(
        VsdxImage(
          partName: '/visio/media/image_lo_tone.png',
          bytes: _solidPng(),
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
      <int>[1, 2, 3, 4, 5, 6, 7],
      reason: 'Bullet 1–7 must round-trip; Draw collects the cell',
    );
    expect(
      bullets.richText.runs.map((run) => run.paraStyle.resolvedBulletGlyph),
      <String>[
        for (var bullet = 1; bullet <= 7; bullet++) libvisioBulletGlyph(bullet),
      ],
    );
    final glowStroke = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowStroke');
    expect(glowStroke.glow.enabled, isFalse);
    expect(glowStroke.fill.hasFill, isTrue);
    expect(glowStroke.geometries.any((g) => !g.noFill), isTrue);
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
    expect(filledLineTrans.line.transparency, closeTo(0, 1e-12));
    expect(filledLineTrans.line.color?.value, 0xFF666666);
    expect(filledLineTrans.fill.foreground?.value, 0xFFFFFFFF);
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
      'opacity': writer.write(
        originalBytes: blank,
        edited: opacityDocument,
      ),
      'label_border': writer.write(
        originalBytes: blank,
        edited: labelBorderDocument,
      ),
      'label_padding': writer.write(
        originalBytes: blank,
        edited: labelPaddingDocument,
      ),
      'word_wrap': writer.write(
        originalBytes: blank,
        edited: wordWrapDocument,
      ),
      'geometry_soft': writer.write(
        originalBytes: blank,
        edited: geometrySoftDocument,
      ),
      'stroke_soft': writer.write(
        originalBytes: blank,
        edited: strokeSoftDocument,
      ),
      'fill_stroke_soft': writer.write(
        originalBytes: blank,
        edited: fillStrokeSoftDocument,
      ),
      'shadow_blur': writer.write(
        originalBytes: blank,
        edited: shadowBlurDocument,
      ),
      'glow_png': writer.write(
        originalBytes: blank,
        edited: glowPngDocument,
      ),
      'glow_noline': writer.write(
        originalBytes: blank,
        edited: glowNolineDocument,
      ),
      'glow_stroke': writer.write(
        originalBytes: blank,
        edited: glowStrokeDocument,
      ),
      'glow_picture': writer.write(
        originalBytes: blank,
        edited: glowPictureDocument,
      ),
      'shadow_picture': writer.write(
        originalBytes: blank,
        edited: shadowPictureDocument,
      ),
      'curved_text': writer.write(
        originalBytes: blank,
        edited: curvedTextDocument,
      ),
      'shape_inside': writer.write(
        originalBytes: blank,
        edited: shapeInsideDocument,
      ),
      'auto_rotate': writer.write(
        originalBytes: blank,
        edited: autoRotateDocument,
      ),
    };
    for (final entry in const <(String, String)>[
      ('connectors', 'test/fixtures/test4_connectors.vsdx'),
      ('zh_data', 'test/fixtures/数据治理.vsdx'),
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
        if (entry.key == 'curved_text' && pdftoppm != null) {
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
        if (entry.key == 'shape_inside' && pdftoppm != null) {
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
        // Still parseable after our write (independent of LibreOffice).
        expect(parser.parse(entry.value).pages, isNotEmpty);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  },
      // A headless soffice conversion alone takes most of the 30 second
      // default on a cold profile, and this case converts twenty-three packages.
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

/// Baseline little-endian, single-strip RGB TIFF understood by libtiff,
/// LibreOffice and the pure-Dart decoder. Keeping this fixture uncompressed
/// avoids coupling the interop assertion to any particular TIFF compressor.
Uint8List _solidPng() {
  final image = raster.Image(width: 8, height: 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgba(x, y, 255, 0, 0, 255);
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
