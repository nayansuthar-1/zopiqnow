import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Uppercase-ish section title used above each Home rail, matching the
/// "What's on your mind?" / "Top restaurant chains" headings.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
      ),
      child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}

/// Full-bleed hairline used to separate Home sections, as Swiggy does between
/// the category rail and the restaurant list.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
      child: Divider(color: context.zc.divider, thickness: 6, height: 6),
    );
  }
}
