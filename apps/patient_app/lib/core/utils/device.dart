import 'package:asani_core/asani_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _channel = MethodChannel('asani/device');

/// True on Xiaomi / Redmi / POCO phones (MIUI / HyperOS), where Autostart must
/// be on for queue alerts to arrive. Android only; false everywhere else.
final isXiaomiPhoneProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final maker = (await _channel.invokeMethod<String>('manufacturer') ?? '').toLowerCase();
    return maker.contains('xiaomi') || maker.contains('redmi') || maker.contains('poco');
  } catch (e) {
    AppLogger.warn('Could not read phone maker: $e');
    return false;
  }
});
