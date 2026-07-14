import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({required this.title, super.key});
  
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.construction_rounded,
              size: 64,
              color: context.zc.primaryDeep,
            ),
            const SizedBox(height: ZopiqSpacing.md),
            Text(
              '$title is coming soon!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              'We are working hard to bring you this feature.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.zc.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
