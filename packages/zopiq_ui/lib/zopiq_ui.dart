/// zopiq_ui — the zopiqnow design system.
///
/// Single source of truth for color, spacing, radii, typography, elevation, and
/// shared components (ENGINEERING_RULES Rule 2). Feature code imports ONLY this
/// barrel and never hardcodes a hex value or magic number.
library;

// Tokens
export 'src/tokens/zopiq_palette.dart';
export 'src/tokens/zopiq_spacing.dart';
export 'src/tokens/zopiq_radii.dart';
export 'src/tokens/zopiq_typography.dart';
export 'src/tokens/zopiq_elevation.dart';
export 'src/tokens/zopiq_durations.dart';

// Theme
export 'src/theme/zopiq_colors.dart';
export 'src/theme/zopiq_theme.dart';

// Components
export 'src/components/zopiq_button.dart';
export 'src/components/zopiq_card.dart';
export 'src/components/zopiq_network_image.dart';
export 'src/components/zopiq_pressable.dart';
export 'src/components/zopiq_shimmer.dart';
export 'src/components/zopiq_veg_indicator.dart';
