import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Saves text as a file in the browser's Downloads (CSV export, C-14).
void downloadText(String fileName, String content, {String mime = 'text/csv'}) {
  // BOM so Excel opens UTF-8 names correctly.
  final bytes = utf8.encode('﻿$content');
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: '$mime;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Builds one CSV line, quoting where needed.
String csvRow(List<Object?> cells) => cells.map((c) {
      final s = (c ?? '').toString();
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }).join(',');

/// Copies text to the clipboard (Copy phone / Copy patient details).
Future<void> copyText(String text) async {
  await web.window.navigator.clipboard.writeText(text).toDart;
}
