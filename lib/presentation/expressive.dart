import 'package:flutter/material.dart';

/// Lookout's Material 3 Expressive look: pastel rounded surfaces, pill
/// chips, big toggles, a floating dock, and springy motion.
/// Style recreated in-house; no third-party code.
class XColors {
  static const bg = Color(0xFFFAF7F2);
  static const ink = Color(0xFF201A17);
  static const inkSoft = Color(0xFF6F675F);
  static const mint = Color(0xFFD8F0DC);
  static const mintDeep = Color(0xFF1E6B3C);
  static const lavender = Color(0xFFE9E2FB);
  static const lavenderDeep = Color(0xFF5A3FA8);
  static const peach = Color(0xFFFFE4CE);
  static const peachDeep = Color(0xFF9A4A12);
  static const sky = Color(0xFFD9EAFB);
  static const skyDeep = Color(0xFF1D5A96);
  static const lemon = Color(0xFFF7F0C8);
  static const lemonDeep = Color(0xFF77680A);
  static const white = Colors.white;

  /// Pastel pairs cycled across watch cards so the list stays colorful.
  static const List<(Color, Color)> cardPastels = [
    (mint, mintDeep),
    (lavender, lavenderDeep),
    (sky, skyDeep),
    (peach, peachDeep),
  ];


  static (Color, Color) pastelFor(int seed) =>
      cardPastels[seed.abs() % cardPastels.length];
}

/// Theme-aware ink colors for text/icons sitting on the canvas or on
/// panel surfaces (panels flip dark in dark mode; pastels never flip -
/// text on pastel always uses XColors.ink / inkSoft / the deep accent).
bool xIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color xInk(BuildContext context) =>
    xIsDark(context) ? const Color(0xFFF2EDE6) : XColors.ink;

Color xInkSoft(BuildContext context) =>
    xIsDark(context) ? const Color(0xFFB4ABA0) : XColors.inkSoft;

Color xPanel(BuildContext context) =>
    xIsDark(context) ? const Color(0xFF23201C) : XColors.white;

Color xTrack(BuildContext context) =>
    xIsDark(context) ? const Color(0xFF2A2521) : const Color(0xFFEDE8E0);

Color xMintOnCanvas(BuildContext context) =>
    xIsDark(context) ? const Color(0xFF8FD6A6) : XColors.mintDeep;


/// The expressive switch style used on cards and toggle tiles.
Widget xSwitch({
  required bool value,
  required Color accent,
  required ValueChanged<bool> onChanged,
  // Dark-mode active track. A light pastel track with a white thumb reads
  // washed out on a dark panel; the deep accent keeps on/off distinct, the
  // same pairing light mode already uses.
  Color? accentDark,
}) {
  return Transform.scale(
    scale: 1.12,
    child: Builder(
      builder: (context) => Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor:
            xIsDark(context) && accentDark != null ? accentDark : accent,
        inactiveThumbColor: xInkSoft(context),
        inactiveTrackColor: xTrack(context),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
  );
}

/// Small caps section label over a group of cards.
Widget xSectionLabel(String text, Color color) => Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: color,
      ),
    );

/// Big rounded tile with an icon, label, subtitle and a large switch.
class XToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bg;
  final Color accent;
  final bool value;
  final ValueChanged<bool> onChanged;

  const XToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.accent,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: value ? bg : xPanel(context),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: value ? accent : xTrack(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon,
                size: 22, color: value ? Colors.white : xInkSoft(context)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: value ? XColors.ink : xInk(context))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: value ? XColors.inkSoft : xInkSoft(context))),
              ],
            ),
          ),
          xSwitch(value: value, accent: accent, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Floating pill dock bottom navigation - detached, rounded, shadowed,
/// with a springy selected-tab transition.
class XDock extends StatelessWidget {
  final int selected;
  final void Function(int index) onSelect;
  final VoidCallback onCreate;

  const XDock({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label, String tooltip) {
      final sel = i == selected;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => onSelect(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            padding: EdgeInsets.symmetric(
                horizontal: sel ? 16 : 10, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? xInk(context) : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: sel
                        ? (xIsDark(context)
                            ? XColors.ink
                            : Colors.white)
                        : xInkSoft(context)),
                if (sel) ...[
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          color: xIsDark(context)
                              ? XColors.ink
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Bottom-dock labels stay legible but do not grow without bound when
    // the system font scale is large.
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.3);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: xPanel(context),
          borderRadius: BorderRadius.circular(36),
          boxShadow: const [
            BoxShadow(
                color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            item(0, Icons.visibility_rounded, 'Watches', 'Your watches'),
            item(1, Icons.history_rounded, 'Activity', 'Task histories'),
            Tooltip(
              message: 'Create Agent',
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: onCreate,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: XColors.mintDeep,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
