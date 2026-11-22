import 'package:asani_core/asani_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Speciality icons from the screens board (P3 "Search by doctor", D-46):
/// 24×24 line icons, drawn in one colour.
const _paths = <Speciality, String>{
  Speciality.generalPhysician:
      '<path d="M5 3H4a1 1 0 00-1 1v4a5 5 0 0010 0V4a1 1 0 00-1-1h-1"/><path d="M8 13v2a6 6 0 0012 0v-3"/><circle cx="20" cy="10" r="2"/>',
  Speciality.child:
      '<circle cx="12" cy="13" r="8"/><path d="M12 5c0-1.7 1.3-2.7 2.8-2.1"/><path d="M9 12h.01M15 12h.01" stroke-width="2.8"/><path d="M9.5 16c1.4 1.2 3.6 1.2 5 0"/>',
  Speciality.heart: '<path d="M12 20s-8-4.8-8-11a4.5 4.5 0 018-2.8A4.5 4.5 0 0120 9c0 6.2-8 11-8 11z"/><path d="M4.5 11.5h3.5l1.5-2.5 3 5 2-3.5h5"/>',
  Speciality.teeth:
      '<path d="M12 5.5C10.5 4 9 3.5 7.5 3.5 5 3.5 3.5 5.5 3.5 8c0 2.5 1 3.5 1.5 6 .5 3 1 6.5 3 6.5 1.8 0 1.7-4.5 4-4.5s2.2 4.5 4 4.5c2 0 2.5-3.5 3-6.5.5-2.5 1.5-3.5 1.5-6 0-2.5-1.5-4.5-4-4.5-1.5 0-3 .5-4.5 2z"/>',
  Speciality.skin: '<path d="M3 10c3-2 6 2 9 0s6-2 9 0"/><path d="M3 15h18"/><path d="M3 20h18"/><path d="M8 9.5V4M15.5 8.8V5"/>',
  Speciality.womensHealth:
      '<circle cx="11" cy="4.5" r="2.2"/><path d="M11 8.5c-2 0-3.2 1.6-3.2 3.6V15H10v6"/><path d="M11 8.5c1.8 0 3 1.3 3.2 3 2 .6 3.3 2 3.3 3.7 0 1.6-1.5 2.3-3.2 2.3H13v3.5"/>',
  Speciality.eye: '<path d="M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="3"/><path d="M12 12h.01" stroke-width="2.6"/>',
  Speciality.ent: '<path d="M6 8.5a6.5 6.5 0 1113 0c0 6-6 6-6 10a3.5 3.5 0 11-7 0"/><path d="M15 8.5a2.5 2.5 0 00-5 0v1a2 2 0 010 4"/>',
  Speciality.bones:
      '<path d="M17 10c.7-.7 1.7 0 2.5 0a2.5 2.5 0 100-5 .5.5 0 01-.5-.5 2.5 2.5 0 10-5 0c0 .8.7 1.8 0 2.5l-7 7c-.7.7-1.7 0-2.5 0a2.5 2.5 0 000 5c.3 0 .5.2.5.5a2.5 2.5 0 105 0c0-.8-.7-1.8 0-2.5z"/>',
  Speciality.diabetes: '<path d="M12 2.5s6.5 7 6.5 11.5a6.5 6.5 0 01-13 0C5.5 9.5 12 2.5 12 2.5z"/><path d="M12 11v6M9 14h6"/>',
  Speciality.stomach: '<path d="M10 3v5.5c0 1.5-4 2.5-4 7.5a6 6 0 006 6c3.5 0 7-2.5 7-6.5 0-2.5-1.5-4-3.5-4s-3 1.5-3 3"/>',
  Speciality.chest:
      '<path d="M12 3v9"/><path d="M12 10c-1.5 0-2.5-1-4-1-2.5 0-4.5 3.5-4.5 8 0 2 1 3.5 2.5 3.5 2.5 0 4-2 4-5V11"/><path d="M12 10c1.5 0 2.5-1 4-1 2.5 0 4.5 3.5 4.5 8 0 2-1 3.5-2.5 3.5-2.5 0-4-2-4-5V11"/>',
  Speciality.kidney:
      '<path d="M9.5 4C6 4 4 7 4 11s2 9 5.5 9c2.5 0 3-2 3-4.5 0-1.5-1.5-2-1.5-3.5S12.5 10 12.5 8.5C12.5 5.5 11.5 4 9.5 4z"/><path d="M12.5 12h3.5a3 3 0 013 3v5"/>',
  Speciality.brain:
      '<path d="M9 4a3 3 0 00-3 3 3 3 0 00-2 5 3 3 0 002 5 3 3 0 003 3h1V4H9z"/><path d="M15 4a3 3 0 013 3 3 3 0 012 5 3 3 0 01-2 5 3 3 0 01-3 3h-1V4h1z"/>',
  Speciality.mentalHealth:
      '<path d="M7 20v-3.5A7 7 0 1119 11c0 1.5.5 2.5 1.5 4l-2 .8V18a2 2 0 01-2 2h-1.5"/><path d="M11 8.5a2 2 0 013.5 1.5c0 1.5-2 1.5-2 3"/><path d="M12.5 15.5h.01" stroke-width="2.6"/>',
  Speciality.physio:
      '<circle cx="14" cy="4.5" r="2"/><path d="M6 11l4-2.5 3.5 1.5 3.5-2"/><path d="M10 8.5l1 5-3 6.5"/><path d="M11 13.5l4 1.5 1 5"/>',
  Speciality.other: '<rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/>',
};

/// "More" tile: four small squares, one with a plus.
const _more = '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/>'
    '<rect x="3" y="14" width="7" height="7" rx="2"/><path d="M17.5 14v7M14 17.5h7"/>';

String _svg(String inner) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" '
    'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">$inner</svg>';

/// Board icon for [s] in [color]. [s] null = the "More" icon.
class SpecialityIcon extends StatelessWidget {
  const SpecialityIcon(this.s, {super.key, this.size = 24, required this.color});
  final Speciality? s;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        _svg(s == null ? _more : _paths[s] ?? _paths[Speciality.other]!),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        excludeFromSemantics: true,
      );
}
