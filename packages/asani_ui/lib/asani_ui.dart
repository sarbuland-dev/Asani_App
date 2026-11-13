/// Shared Asani look: theme tokens (colors, type, spacing), the mobile and
/// desktop ThemeData, and common widgets used by both apps (DESIGN.md §3).
library;

export 'src/theme/app_theme.dart'; // buildAppTheme() for the patient app + tokens
export 'src/theme/desktop_theme.dart' show buildDesktopAppTheme; // clinic web
export 'src/widgets/common.dart';
