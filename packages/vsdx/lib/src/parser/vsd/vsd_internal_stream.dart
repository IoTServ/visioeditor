/// Visio internal stream LZ decompress (algorithm reference: libvisio
/// `VSDInternalStream`). Not zlib — sliding-window LZ with 4 KiB dictionary.
library;

import 'dart:typed_data';

/// Decompress (or copy) a Visio internal stream payload.
Uint8List vsdInflate(Uint8List input, {required bool compressed}) {
  if (!compressed) return Uint8List.fromList(input);
  if (input.length < 2) return Uint8List(0);

  final out = BytesBuilder(copy: false);
  final window = Uint8List(4096);
  var pos = 0;
  var offset = 0;

  while (offset < input.length) {
    final flag = input[offset++];
    if (offset > input.length - 1) break;
    var mask = 1;
    for (var bit = 0; bit < 8 && offset < input.length; bit++) {
      if ((flag & mask) != 0) {
        final b = input[offset++];
        window[pos & 4095] = b;
        out.addByte(b);
        pos++;
      } else {
        if (offset > input.length - 2) break;
        final addr1 = input[offset++];
        final addr2 = input[offset++];
        final length = (addr2 & 15) + 3;
        var pointer = ((addr2 & 0xF0) << 4) | addr1;
        if (pointer > 4078) {
          pointer -= 4078;
        } else {
          pointer += 18;
        }
        for (var j = 0; j < length; j++) {
          final b = window[(pointer + j) & 4095];
          window[(pos + j) & 4095] = b;
          out.addByte(b);
        }
        pos += length;
      }
      mask <<= 1;
    }
  }
  return out.takeBytes();
}
