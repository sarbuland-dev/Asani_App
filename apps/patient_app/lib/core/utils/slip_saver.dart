import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

/// Thrown when the person did not let the app add photos.
class GalleryDenied implements Exception {
  const GalleryDenied();
}

/// Puts a PNG into the phone's photo gallery ("Save to gallery" on the token
/// slip). A provider so tests can replace the phone's gallery.
typedef SaveImage = Future<void> Function(Uint8List png, String name);

final saveImageProvider = Provider<SaveImage>((ref) => (png, name) async {
      // Android 10+ needs no permission to add a picture; older Android and
      // iOS ask once.
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) throw const GalleryDenied();
      await Gal.putImageBytes(png, name: name);
    });
