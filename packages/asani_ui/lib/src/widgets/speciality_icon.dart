import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The Material Symbols icon of each speciality ([Speciality.iconName],
/// DESIGN.md §3.4), shared by the patient app and the clinic web. The constants
/// are listed one by one so unused icons are dropped from builds.
IconData specialityIconData(Speciality s) => switch (s) {
      Speciality.generalPhysician => Symbols.stethoscope_rounded,
      Speciality.child => Symbols.child_care_rounded,
      Speciality.heart => Symbols.cardiology_rounded,
      Speciality.teeth => Symbols.dentistry_rounded,
      Speciality.skin => Symbols.dermatology_rounded,
      Speciality.womensHealth => Symbols.gynecology_rounded,
      Speciality.eye => Symbols.ophthalmology_rounded,
      Speciality.ent => Symbols.hearing_rounded,
      Speciality.bones => Symbols.orthopedics_rounded,
      Speciality.diabetes => Symbols.glucose_rounded,
      Speciality.stomach => Symbols.gastroenterology_rounded,
      Speciality.chest => Symbols.pulmonology_rounded,
      Speciality.kidney => Symbols.nephrology_rounded,
      Speciality.brain => Symbols.neurology_rounded,
      Speciality.mentalHealth => Symbols.psychology_rounded,
      Speciality.physio => Symbols.physical_therapy_rounded,
      Speciality.other => Symbols.medical_services_rounded,
    };

/// Icon for [s] in [color]. [s] null = the "More" icon.
class SpecialityIcon extends StatelessWidget {
  const SpecialityIcon(this.s, {super.key, this.size = 24, required this.color});
  final Speciality? s;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(
        s == null ? Symbols.dashboard_customize_rounded : specialityIconData(s!),
        size: size,
        color: color,
      );
}

/// Icon and name of a speciality, for pickers.
class SpecialityOption extends StatelessWidget {
  const SpecialityOption(this.s, {super.key, required this.color});
  final Speciality s;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SpecialityIcon(s, size: 18, color: color),
        const SizedBox(width: 10),
        Flexible(child: Text(s.display, overflow: TextOverflow.ellipsis)),
      ]);
}
