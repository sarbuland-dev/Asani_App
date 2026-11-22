/// Shared Asani look: theme tokens (colors, type, spacing), the mobile and
/// desktop ThemeData, and common widgets used by both apps (DESIGN.md §3).
library;

export 'src/theme/app_theme.dart'; // buildAppTheme() for the patient app + tokens
export 'src/theme/desktop_theme.dart' show buildDesktopAppTheme; // clinic web
export 'src/theme/web_colors.dart'; // WebColors: old palette kept for the clinic web (D-44)
export 'src/widgets/common.dart';
export 'src/widgets/loader.dart'; // AsaniLoader (D-36)
