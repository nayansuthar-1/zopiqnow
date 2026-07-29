import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart'
    show formatClockTime;

/// A short conversation with the rider, in sentences the database chose.
///
/// **Canned, and not a keyboard.** Free text is a moderation problem and a
/// retention problem, and neither belongs in the same week as the button. What
/// is here instead is the six things anybody actually says at a doorstep, and
/// the rider's app offers the six things a rider says. Migration 0061 owns both
/// lists, which is why they are fetched rather than written here: the button
/// says exactly what will be sent.
Future<void> showRiderChatSheet(
  BuildContext context, {
  required String orderId,
  required String riderName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZopiqRadii.xl)),
    ),
    builder: (_) => RiderChatSheet(orderId: orderId, riderName: riderName),
  );
}

class RiderChatSheet extends ConsumerStatefulWidget {
  const RiderChatSheet({
    required this.orderId,
    required this.riderName,
    super.key,
  });

  final String orderId;
  final String riderName;

  @override
  ConsumerState<RiderChatSheet> createState() => _RiderChatSheetState();
}

class _RiderChatSheetState extends ConsumerState<RiderChatSheet> {
  final ScrollController _scroll = ScrollController();
  String? _failure;

  @override
  void initState() {
    super.initState();
    // Opening the sheet *is* reading the thread. Deferred one frame because
    // this runs during a build and the RPC would otherwise mutate a provider
    // mid-render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(orderMessageControllerProvider.notifier)
          .markRead(widget.orderId);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A thread reads downward, so the newest line has to be the one in view.
  /// Jumped, not animated: on open there is nothing to animate *from*, and on a
  /// new message the sheet is short enough that a scroll animation reads as lag.
  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(String code) async {
    final String? failure = await ref
        .read(orderMessageControllerProvider.notifier)
        .send(orderId: widget.orderId, code: code);
    if (!mounted) return;
    setState(() => _failure = failure);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final List<OrderMessage> messages =
        ref.watch(orderMessagesProvider(widget.orderId)).valueOrNull ??
        const <OrderMessage>[];
    final List<CannedMessage> menu =
        ref.watch(messageMenuProvider).valueOrNull ?? const <CannedMessage>[];
    final bool sending = ref.watch(orderMessageControllerProvider);

    // A line the rider sent while the sheet is open has been read by definition.
    ref.listen(orderMessagesProvider(widget.orderId), (_, _) {
      ref.read(orderMessageControllerProvider.notifier).markRead(widget.orderId);
    });
    // Every build, which covers both cases: the first frame, when the list has
    // not been laid out yet, and a new message arriving.
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
          Text('Message ${widget.riderName}', style: t.titleLarge),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'Quick messages only — call them if it\'s urgent.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.lg),

          // A fixed height rather than a shrink-wrap: a sheet that grows by one
          // bubble per message would walk up the screen under the thumb that is
          // tapping the buttons below it.
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
            Text(
              _failure!,
              style: t.bodySmall?.copyWith(color: zc.nonVeg),
            ),
          ],

          const SizedBox(height: ZopiqSpacing.md),
          Divider(height: 1, color: zc.divider),
          const SizedBox(height: ZopiqSpacing.md),

          // Chips rather than a list: six short sentences read as a set of
          // choices, and a doorstep is not where anybody scrolls a menu.
          Wrap(
            spacing: ZopiqSpacing.sm,
            runSpacing: ZopiqSpacing.sm,
            children: <Widget>[
              for (final CannedMessage option in menu)
                ActionChip(
                  label: Text(option.body),
                  // Every chip goes dead while one is in flight — the server
                  // refuses a second line within three seconds anyway, and a
                  // refusal the customer caused by tapping twice is a refusal
                  // the screen should have prevented.
                  onPressed: sending ? null : () => _send(option.code),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line. Mine on the right, theirs on the left — the arrangement everybody
/// already knows, so nothing has to be labelled.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final OrderMessage message;

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
              // "Seen" only on a line of mine that the rider has opened. On
              // theirs it would be reporting my own behaviour back to me.
              mine && message.isRead
                  ? '${formatClockTime(message.sentAt)} · Seen'
                  : formatClockTime(message.sentAt),
              style: t.bodySmall?.copyWith(color: zc.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
