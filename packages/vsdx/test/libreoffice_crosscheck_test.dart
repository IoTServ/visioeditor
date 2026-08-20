import 'dart:io';
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
    final glowNoLine = reopenedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowNoLine');
    expect(glowNoLine.glow.enabled, isFalse);
    expect(glowNoLine.line.hasLine, isTrue);
    expect(glowNoLine.line.weightInches, closeTo(0.16, 1e-9));
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
          s.name ==
          '$kLibvisioReflectionShapeNamePrefix${reflectionSource.id}',
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
        // Still parseable after our write (independent of LibreOffice).
        expect(parser.parse(entry.value).pages, isNotEmpty);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  },
      // A headless soffice conversion alone takes most of the 30 second
      // default on a cold profile, and this case converts eight packages.
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
