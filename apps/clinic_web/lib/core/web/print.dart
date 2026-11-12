import 'dart:async';
import 'dart:js_interop';

import 'package:qr/qr.dart';
import 'package:web/web.dart' as web;

/// Prints an HTML document through the browser (C-07). A hidden iframe
/// holds the page so the app itself is not printed. With Chrome's
/// `--kiosk-printing` shortcut no dialog appears (Help page).
void printHtml(String html) {
  final frame = web.HTMLIFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  late StreamSubscription<web.Event> sub;
  sub = frame.onLoad.listen((_) {
    sub.cancel();
    frame.contentWindow?.focus();
    frame.contentWindow?.print();
    Timer(const Duration(seconds: 60), () => frame.remove());
  });
  frame.srcdoc = html.toJS;
  web.document.body!.append(frame);
}

/// Escapes text for HTML.
String esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// A QR code as an inline SVG string.
String qrSvg(String data, {int size = 120, String color = '#0F172A'}) {
  final img = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
  final n = img.moduleCount;
  final b = StringBuffer();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (img.isDark(y, x)) b.write('M$x ${y}h1v1h-1z');
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" viewBox="-2 -2 ${n + 4} ${n + 4}" '
      'shape-rendering="crispEdges"><rect x="-2" y="-2" width="${n + 4}" height="${n + 4}" fill="#fff"/>'
      '<path d="$b" fill="$color"/></svg>';
}
