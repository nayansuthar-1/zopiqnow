import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

/// A short conversation with the customer, in sentences the database chose.
///
/// **Canned, and not a keyboard.** A rider typing at a traffic light is a thing
/// this app should not make easy, and free text is a moderation problem besides.
/// What is here instead is the six things a rider actually needs to say, each
/// one tap, each one already written. Migration 0061 owns the wording — the
/// chips are fetched, so what the button says is what gets sent.
Future<void> showCustomerChatSheet(
  BuildContext context, {
  required String orderId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => CustomerChatSheet(orderId: orderId),
  );
}

class CustomerChatSheet extends ConsumerStatefulWidget {
  const CustomerChatSheet({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<CustomerChatSheet> createState() => _CustomerChatSheetState();
}

class _CustomerChatSheetState extends ConsumerState<CustomerChatSheet> {
  final ScrollController _scroll = ScrollController();
  String? _failure;

  @override
  void initState() {
    super.initState();
    // Opening the sheet *is* reading the thread. Deferred a frame — this runs
    // during a build, and the RPC would otherwise fire mid-render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jobsControllerProvider.notifier).markMessagesRead(widget.orderId);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A thread reads downward, so the newest line has to be in view. Jumped, not
  /// animated: on open there is nothing to animate from, and a rider glancing at
  /// this while holding a helmet does not need a scroll to finish first.
  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(String code) async {
    setState(() => _failure = null);
    final String? failure = await ref
        .read(jobsControllerProvider.notifier)
        .sendMessage(orderId: widget.orderId, code: code);
    if (!mounted) return;
    setState(() => _failure = failure);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final List<JobMessage> messages =
        ref.watch(jobMessagesProvider(widget.orderId)).valueOrNull ??
        const <JobMessage>[];
    final List<CannedMessage> menu =
        ref.watch(messageMenuProvider).valueOrNull ?? const <CannedMessage>[];

    ref.listen(jobMessagesProvider(widget.orderId), (_, _) {
      ref.read(jobsControllerProvider.notifier).markMessagesRead(widget.orderId);
    });
    _stickToBottom();

    return Padding(
      padding: EdgeInsets.only(
        left: ZopiqSpacing.pageGutter,
        right: ZopiqSpacing.pageGutter,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.pageGutter,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Message the customer', style: t.titleLarge),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'One tap each. Call them if it\'s urgent.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.lg),

          // Fixed height rather than shrink-wrapped: a sheet that grew by a
          // bubble per message would walk the chips up under the thumb aiming
          // at them.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, minHeight: 88),
            child: messages.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Nothing said yet.',
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int i) =>
                        _Bubble(message: messages[i]),
                  ),
          ),

          if (_failure != null) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.sm),
            Text(_failure!, style: t.bodySmall?.copyWith(color: zc.nonVeg)),
          ],

          const SizedBox(height: ZopiqSpacing.md),
          Divider(height: 1, color: zc.divider),
          const SizedBox(height: ZopiqSpacing.md),

          Wrap(
            spacing: ZopiqSpacing.sm,
            runSpacing: ZopiqSpacing.sm,
            children: <Widget>[
              for (final CannedMessage option in menu)
                ActionChip(
                  label: Text(option.body),
                  onPressed: () => _send(option.code),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line. Mine on the right, theirs on the left.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final JobMessage message;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool mine = message.isMine;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.md,
          vertical: ZopiqSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        decoration: BoxDecoration(
          color: mine
              ? zc.primary.withValues(alpha: 0.12)
              : zc.divider.withValues(alpha: 0.35),
          borderRadius: ZopiqRadii.rMd,
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            Text(message.body, style: t.bodyMedium),
            const SizedBox(height: 2),
            Text(
              // "Seen" only on a line of mine the customer has opened. On theirs
              // it would be reporting the rider's own behaviour back to them.
              mine && message.isRead
                  ? '${_clock(message.sentAt)} · Seen'
                  : _clock(message.sentAt),
              style: t.bodySmall?.copyWith(color: zc.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// 24-hour, zero-padded. A rider reading a timestamp between two junctions
  /// does not need to parse an am/pm.
  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
