/// Fixed speciality list (PRD F-13, D-31, D-33). Firestore stores [key].
enum Speciality {
  generalPhysician('General Physician', null, 'stethoscope'),
  child('Child Specialist', null, 'child_care'),
  heart('Heart', 'Cardiologist', 'cardiology'),
  teeth('Teeth', 'Dentist', 'dentistry'),
  skin('Skin', 'Dermatologist', 'dermatology'),
  womensHealth("Women's Health", 'Gynecologist', 'gynecology'),
  eye('Eye', 'Eye Specialist', 'ophthalmology'),
  ent('Ear Nose Throat', 'ENT', 'hearing'),
  bones('Bones & Joints', 'Orthopedic', 'orthopedics'),
  diabetes('Diabetes & Hormones', 'Endocrinologist', 'glucose'),
  stomach('Stomach & Liver', 'Gastro', 'gastroenterology'),
  chest('Chest & Lungs', 'Pulmonologist', 'pulmonology'),
  kidney('Kidney', 'Nephrologist', 'nephrology'),
  brain('Brain & Nerves', 'Neurologist', 'neurology'),
  mentalHealth('Mental Health', 'Psychiatrist', 'psychology'),
  physio('Physiotherapy', null, 'physical_therapy'),
  other('Other', null, 'medical_services');

  const Speciality(this.label, this.term, this.iconName);

  /// Simple patient word, e.g. "Heart".
  final String label;

  /// Medical term, e.g. "Cardiologist"; null when [label] says it already.
  final String? term;

  /// Material Symbols icon name (DESIGN §3.4).
  final String iconName;

  String get key => name;

  /// "Heart (Cardiologist)".
  String get display => term == null ? label : '$label ($term)';

  /// Exact key, else an old free-text value (before the D-33 migration), else [other].
  static Speciality resolve(String? raw) => fromKey(raw) ?? fromLegacy(raw) ?? other;

  static Speciality? fromKey(String? key) {
    for (final s in values) {
      if (s.name == key) return s;
    }
    return null;
  }

  /// Maps old free-text specialities; null when unknown (migration flags those).
  static Speciality? fromLegacy(String? text) {
    final t = (text ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').trim();
    if (t.isEmpty) return null;
    for (final s in values) {
      if (t == s.label.toLowerCase() || t == s.term?.toLowerCase() || t == s.display.toLowerCase()) return s;
    }
    const words = {
      'general physician': generalPhysician, 'gp': generalPhysician, 'family physician': generalPhysician,
      'family medicine': generalPhysician, 'physician': generalPhysician,
      'child': child, 'pediatrician': child, 'paediatrician': child, 'paediatrics': child, 'pediatrics': child,
      'cardio': heart, 'heart': heart,
      'dent': teeth, 'teeth': teeth,
      'derma': skin, 'skin': skin,
      'gyn': womensHealth, 'obstetric': womensHealth, 'women': womensHealth,
      'eye': eye, 'ophthal': eye,
      'ent': ent, 'ear': ent,
      'ortho': bones, 'bone': bones,
      'endocrin': diabetes, 'diabet': diabetes,
      'gastro': stomach, 'liver': stomach, 'hepat': stomach,
      'pulmo': chest, 'chest': chest, 'lung': chest,
      'nephro': kidney, 'kidney': kidney, 'urolog': kidney,
      'neuro': brain, 'brain': brain,
      'psychiat': mentalHealth, 'psycholog': mentalHealth, 'mental': mentalHealth,
      'physio': physio,
    };
    for (final e in words.entries) {
      final w = e.key;
      if (t == w || t.startsWith('$w ') || t.split(' ').any((part) => part.startsWith(w) && w.length > 2)) {
        return e.value;
      }
    }
    return null;
  }
}
