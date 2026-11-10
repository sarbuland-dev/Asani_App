import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart';

/// Public links. `asani.app` is a placeholder until the domain is decided (PRD Q-06).
abstract final class AppLinks {
  static final privacy = Uri.parse('https://asani.app/privacy');
  static final terms = Uri.parse('https://asani.app/terms');
  static final support = Uri.parse('mailto:support@asani.app?subject=Asani%20app%20support');
}

Future<void> openUrl(BuildContext context, Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
  final ok = await launchUrl(uri, mode: mode).catchError((_) => false);
  if (!ok && context.mounted) showSnack(context, "Couldn't open this link.");
}

Future<void> callNumber(BuildContext context, String phone) =>
    openUrl(context, Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')));

Future<void> openDirections(BuildContext context, Clinic clinic) {
  final query = clinic.location != null
      ? '${clinic.location!.lat},${clinic.location!.lng}'
      : '${clinic.name}, ${clinic.address}, ${clinic.city}';
  return openUrl(context, Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query}));
}
