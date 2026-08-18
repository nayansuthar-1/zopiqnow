import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_legal/src/legal_document.dart';
import 'package:zopiq_legal/src/registry.dart';

/// Records that this user accepted the current terms and privacy policy.
///
/// Called **after** sign-in succeeds, not before, and that ordering is forced:
/// consent is given on the sign-in screen, where there is no user id yet to
/// address a row to. The tick gates the button; this writes what the tick meant
/// once there is somebody to write it against.
///
/// Failure is swallowed deliberately. The user has agreed, signed in, and is
/// looking at a loading spinner; blocking them out of the app because an
/// analytics-shaped write failed would be a worse outcome than a missing row,
/// and the row can be reconciled — [hasAcceptedCurrentPolicies] is what asks.
/// It is not swallowed *silently*: a failure returns false, and the caller may
/// try again on the next launch.
Future<bool> recordPolicyConsent(
  SupabaseClient client, {
  required String surface,
}) async {
  try {
    await client.rpc<void>(
      'record_policy_acceptance',
      params: <String, dynamic>{
        'p_version': legalConsentVersion,
        'p_surface': surface,
        'p_documents': consentDocuments.map((LegalDocument d) => d.slug).toList(),
      },
    );
    return true;
  } on Object {
    return false;
  }
}

/// The tick box that stands between somebody and a sign-in button.
///
/// Not a link and a hope: the two documents are one tap away from the sentence
/// that names them, and nothing on the screen is pressable until the box is
/// ticked. That is the difference between telling somebody what they agreed to
/// and asking them.
///
/// Routing-agnostic on purpose — this package has no opinion about go_router,
/// and the three apps do not all navigate the same way. [onOpenDocument] gets a
/// slug; the app decides what opening one means.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.onOpenDocument,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Called with a document slug — `terms-and-conditions`, `privacy-policy`.
  final void Function(String slug) onOpenDocument;

  /// False while a sign-in is in flight, so the box cannot be un-ticked out
  /// from under a request that was made on the strength of it.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    // The whole row is the target, not just the 18dp box. A checkbox that
    // gates an entire app is not a place to make somebody aim.
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: ZopiqRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ZopiqSpacing.sm,
          horizontal: ZopiqSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Sized down from Material's 48dp default tap target: the row
            // already provides one, and the default leaves the box floating a
            // long way from the words it belongs to.
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: enabled
                    ? (bool? next) => onChanged(next ?? false)
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: zc.primary,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: t.bodySmall?.copyWith(
                    color: zc.textMuted,
                    height: 1.45,
                  ),
                  children: <InlineSpan>[
                    const TextSpan(text: 'I have read and agree to the '),
                    for (final LegalDocument doc in consentDocuments) ...<InlineSpan>[
                      _link(
                        context,
                        doc.title.replaceFirst('Zopiq ', ''),
                        () => onOpenDocument(doc.slug),
                      ),
                      if (doc != consentDocuments.last)
                        const TextSpan(text: ' and the '),
                    ],
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InlineSpan _link(BuildContext context, String label, VoidCallback onTap) {
    // A WidgetSpan rather than a TapGestureRecognizer: a recognizer inside a
    // Text.rich that is *itself* inside an InkWell loses the race for the tap
    // often enough that the link reads as broken, and a recognizer has to be
    // disposed by hand or it leaks. This gives the link its own hit test.
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.zc.primary,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
