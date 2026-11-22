import 'package:asani_ui/asani_ui.dart' show WebColors;

/// D-44: the clinic web keeps the old "Monochrome green" colours until it is
/// redesigned. Clinic web code still writes AppColors; here that name means
/// the old palette, while the patient app gets Deep forest from asani_ui.
typedef AppColors = WebColors;
