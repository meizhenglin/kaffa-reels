import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

Future<List<int>> _readAt(RandomAccessFile f, int offset, int len) async {
  await f.setPosition(offset);
  return f.read(len);
}

Future<void> main() async {
  final apk = File(r'build\app\outputs\flutter-apk\app-arm64-v8a-google-release.apk');
  final raf = await apk.open();
  final size = await raf.length();
  print('APK size: $size bytes');

  // Locate End of Central Directory record
  int eocdOffset = size - 22;
  while (true) {
    final bytes = await _readAt(raf, eocdOffset, 22);
    if (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x05 && bytes[3] == 0x06) break;
    eocdOffset--;
    if (size - eocdOffset > 65557) {
      print('EOCD not found');
      return;
    }
  }
  final eocd = await _readAt(raf, eocdOffset, 22);
  final cdEntryCount = ByteData.sublistView(Uint8List.fromList(eocd), 10, 12).getUint16(0, Endian.little);
  final cdSize = ByteData.sublistView(Uint8List.fromList(eocd), 12, 16).getUint32(0, Endian.little);
  final cdOffset = ByteData.sublistView(Uint8List.fromList(eocd), 16, 20).getUint32(0, Endian.little);
  print('Central dir: offset=$cdOffset, size=$cdSize, entries=$cdEntryCount');

  // Walk CD entries
  final libappEntrySize = await _findLibappEntry(raf, cdOffset, cdSize);
  if (libappEntrySize == null) {
    print('libapp.so not found in APK');
    return;
  }

  final dataStart = libappEntrySize['dataOffset']!;
  final compressedSize = libappEntrySize['compressedSize']!;
  final method = libappEntrySize['method']!;
  print('libapp.so: offset=$dataStart, compressed=$compressedSize, method=$method');

  final compressed = await _readAt(raf, dataStart, compressedSize);
  List<int> raw;
  if (method == 0) {
    raw = compressed;
  } else if (method == 8) {
    // Need raw inflate
    final inflater = await _inflate(compressed);
    raw = inflater;
  } else {
    print('Unknown method: $method');
    return;
  }

  print('libapp.so raw size: ${raw.length} bytes');
  await File(r'${Platform.environment['TEMP']}\libapp.so').writeAsBytes(raw);

  // Scan for printable strings >= 6 chars
  final strings = <String>[];
  final buf = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    final b = raw[i];
    if (b >= 32 && b <= 126) {
      buf.writeCharCode(b);
    } else {
      if (buf.length >= 6) strings.add(buf.toString());
      buf.clear();
    }
  }

  int googleCount = 0, platformCount = 0;
  for (final s in strings) {
    if (s == 'google') googleCount++;
    if (s == 'platform') platformCount++;
  }
  print('Literal google: $googleCount');
  print('Literal platform: $platformCount');

  print('\n--- first 10 lines with literal google:');
  print(strings.where((s) => s == 'google').take(0).toList().toString()); // count only
  print('\n--- first 20 lines containing platform:');
  print(strings.where((s) => s.contains('platform')).take(20).join('\n'));
}

Future<Map<String, int>?> _findLibappEntry(RandomAccessFile raf, int cdOffset, int cdSize) async {
  int pos = cdOffset;
  final cdEnd = cdOffset + cdSize;
  while (pos < cdEnd) {
    final hdr = await _readAt(raf, pos, 46);
    if (hdr[0] != 0x50 || hdr[1] != 0x4B || hdr[2] != 0x01 || hdr[3] != 0x02) {
      return null;
    }
    final nameLen = ByteData.sublistView(Uint8List.fromList(hdr), 28, 30).getUint16(0, Endian.little);
    final extraLen = ByteData.sublistView(Uint8List.fromList(hdr), 30, 32).getUint16(0, Endian.little);
    final commentLen = ByteData.sublistView(Uint8List.fromList(hdr), 32, 34).getUint16(0, Endian.little);
    final localHdrOffset = ByteData.sublistView(Uint8List.fromList(hdr), 42, 46).getUint32(0, Endian.little);
    final nameBytes = await _readAt(raf, pos + 46, nameLen);
    final name = String.fromCharCodes(nameBytes);
    if (name == 'lib/arm64-v8a/libapp.so') {
      final localHdr = await _readAt(raf, localHdrOffset, 30);
      final method = ByteData.sublistView(Uint8List.fromList(localHdr), 8, 10).getUint16(0, Endian.little);
      final compSize = ByteData.sublistView(Uint8List.fromList(localHdr), 18, 22).getUint32(0, Endian.little);
      final localNameLen = ByteData.sublistView(Uint8List.fromList(localHdr), 26, 28).getUint16(0, Endian.little);
      final localExtraLen = ByteData.sublistView(Uint8List.fromList(localHdr), 28, 30).getUint16(0, Endian.little);
      final dataOffset = localHdrOffset + 30 + localNameLen + localExtraLen;
      return {'dataOffset': dataOffset, 'compressedSize': compSize, 'method': method};
    }
    pos += 46 + nameLen + extraLen + commentLen;
  }
  return null;
}

Future<List<int>> _inflate(List<int> compressed) async {
  // Use dart:io zlib via process — or implement streaming inflate
  // Simplest: write compressed to a temp .gz and use zlib via Process
  final tmpGz = File(r'${Platform.environment['TEMP']}\in.gz');
  await tmpGz.writeAsBytes(compressed);
  // Use windows certutil? No. Use 7z? Not available. Fallback to writing and using dart's InputStream inflate.
  // Actually dart has no high-level zlib inflate stream in dart:io. We need dart:io `ZLibCodec` (in package:convert) or manual inflate.
  // Workaround: use Process to invoke PowerShell's Get-Gzip to inflate — won't work.
  // Simpler: use dart:io `ZLibCodec` is NOT in dart:io. It's in `package:convert`.
  // Alternative: use the underlying native gzip.exe if exists, else fall back to chunked inflate manually.
  // We'll do manual raw inflate using `dart:io` raw deflate stream? Not exposed.
  // === Easiest: spawn PowerShell with [System.IO.Compression.GZipStream] ===
  final script = File(r'${Platform.environment['TEMP']}\inflate.ps1');
  await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName "System.IO.Compression"
\$in = "${tmpGz.path}"
\$out = "\$(\$env:TEMP)\libapp.raw"
if (Test-Path \$out) { Remove-Item \$out -Force }
\$gz = [System.IO.Compression.GZipStream]::new([System.IO.File]::OpenRead(\$in), [System.IO.Compression.CompressionMode]::Decompress)
\$fs = [System.IO.File]::Create(\$out)
\$buf = New-Object byte[] 65536
while (\$true) {
  \$n = \$gz.Read(\$buf, 0, \$buf.Length)
  if (\$n -le 0) { break }
  \$fs.Write(\$buf, 0, \$n)
}
\$gz.Close(); \$fs.Close()
''');
  final r = await Process.run('powershell', ['-ExecutionPolicy', 'Bypass', '-File', script.path]);
  if (r.exitCode != 0) {
    print('inflate failed: ${r.stderr}');
    return <int>[];
  }
  return File(r'${Platform.environment['TEMP']}\libapp.raw').readAsBytes();
}
