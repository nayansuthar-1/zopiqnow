import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/offers/domain/entities/vendor_offer.dart';
import 'package:zopiq_vendor/features/offers/presentation/providers/offers_providers.dart';

/// Run and track promotions — the other tile on the More hub that used to say
/// "coming soon".
///
/// **Paused, never deleted.** An order placed last week carries this code as a
/// foreign key into `coupons` (0003), so removing a row would either fail or
/// take a receipt with it. Ending an offer is a switch, and the row stays.
class OffersPage extends ConsumerStatefulWidget {
  const OffersPage({super.key});

  @override
  ConsumerState<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends ConsumerState<OffersPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<VendorOffer>> offers = ref.watch(offersProvider);
    final bool isOwner = ref.watch(vendorProvider)?.role.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Offers'), centerTitle: true),
      // A discount is money out of the business, so the button is the owner's —
      // the same line 0024 drew around settlements, and the database draws it
      // again underneath.
      floatingActionButton: !isOwner
          ? null
          : FloatingActionButton.extended(
              backgroundColor: context.zc.primary,
              foregroundColor: Colors.white,
              onPressed: _busy ? null : () => _edit(null),
              icon: const Icon(Icons.local_offer_rounded),
              label: const Text('New offer'),
            ),
      body: offers.when(
        loading: () => const Center(child: ZopiqLoader()),
        error: (Object _, StackTrace _) =>
            _ErrorBody(onRetry: () => ref.invalidate(offersProvider)),
        data: (List<VendorOffer> list) => AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.only(
              top: ZopiqSpacing.sm,
              bottom: ZopiqSpacing.xxl * 2,
            ),
            children: <Widget>[
              const VendorFadeSlide(child: _Explainer()),
              if (list.isEmpty)
                const VendorFadeSlide(
                  delay: Duration(milliseconds: 80),
                  child: _EmptyBody(),
                )
              else
                for (int i = 0; i < list.length; i++)
                  VendorFadeSlide(
                    delay: Duration(milliseconds: 50 + i * 50),
                    child: _OfferTile(
                      offer: list[i],
                      canEdit: isOwner,
                      onEdit: () => _edit(list[i]),
                      onToggle: (bool on) => _toggle(list[i], on),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(VendorOffer? existing) async {
    final _OfferDraft? draft = await showModalBottomSheet<_OfferDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OfferSheet(existing: existing),
    );
    if (draft == null) return;

    await _run(
      () => ref
          .read(offersControllerProvider.notifier)
          .save(
            code: draft.code,
            minSubtotal: draft.minSubtotal,
            flatOff: draft.flatOff,
            percentOff: draft.percentOff,
            maxOff: draft.maxOff,
            validUntil: draft.validUntil,
          ),
      existing == null ? 'Your offer is live.' : 'Offer updated.',
    );
  }

  Future<void> _toggle(VendorOffer offer, bool on) => _run(
    () => ref
        .read(offersControllerProvider.notifier)
        .setActive(code: offer.code, isActive: on),
    on ? '${offer.code} is live again.' : '${offer.code} is paused.',
  );

  Future<void> _run(Future<String?> Function() call, String success) async {
    setState(() => _busy = true);
    final String? failure = await call();
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure ?? success)));
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.lg,
        ZopiqSpacing.md,
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
      ),
      child: Text(
        'Offers you create apply only to orders from this restaurant, and the '
        'discount comes out of your own bill. Customers see the code on your '
        'page and at checkout.',
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.offer,
    required this.canEdit,
    required this.onEdit,
    required this.onToggle,
  });

  final VendorOffer offer;
  final bool canEdit;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isLive = offer.isActive && !offer.hasExpired;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.lg,
        vertical: ZopiqSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          offer.code,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            // A paused offer is not deleted, and should not
                            // look deleted — but it must not look live either.
                            color: isLive ? null : zc.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Copy code',
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 15,
                            color: zc.textMuted,
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: offer.code));
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text('${offer.code} copied.'),
                                ),
                              );
                          },
                        ),
                      ],
                    ),
                    Text(
                      offer.minSubtotal > 0
                          ? '${offer.label} · min ₹${offer.minSubtotal}'
                          : offer.label,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                Switch(
                  value: isLive,
                  // Expiry is a date, not a switch: flipping this back on would
                  // change nothing while the end date is in the past, so the
                  // control goes away and the Edit button is the way out.
                  onChanged: offer.hasExpired ? null : onToggle,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              if (offer.hasExpired)
                _Tag(text: 'Ended ${_date(offer.validUntil!)}', muted: true)
              else if (offer.validUntil case final DateTime until)
                _Tag(text: 'Until ${_date(until)}', muted: true)
              else if (!offer.isActive)
                const _Tag(text: 'Paused', muted: true),
              if (offer.timesUsed > 0) ...<Widget>[
                const SizedBox(width: 6),
                _Tag(
                  text:
                      'Used ${offer.timesUsed}× · ₹${offer.totalGiven} given',
                  muted: true,
                ),
              ],
              const Spacer(),
              if (canEdit)
                TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          Divider(height: 1, color: zc.textMuted.withValues(alpha: 0.15)),
        ],
      ),
    );
  }

  static String _date(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: zc.textMuted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: muted ? zc.textMuted : null,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// What the sheet hands back. Validated properly by 0064 — this only carries
/// the numbers across, and the sheet's own checks exist so the commonest
/// mistakes are caught without a round trip.
class _OfferDraft {
  const _OfferDraft({
    required this.code,
    required this.minSubtotal,
    this.flatOff,
    this.percentOff,
    this.maxOff,
    this.validUntil,
  });

  final String code;
  final int minSubtotal;
  final int? flatOff;
  final int? percentOff;
  final int? maxOff;
  final DateTime? validUntil;
}

class _OfferSheet extends StatefulWidget {
  const _OfferSheet({this.existing});

  final VendorOffer? existing;

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  late bool _isFlat = widget.existing?.isFlat ?? true;
  late final TextEditingController _code = TextEditingController(
    // The prefix is the database's, so an edit shows the readable half only —
    // typing `R3-R3-WEEKEND` is the mistake this avoids.
    text: _suffixOf(widget.existing?.code ?? ''),
  );
  late final TextEditingController _amount = TextEditingController(
    text: (widget.existing?.flatOff ?? widget.existing?.percentOff)?.toString() ?? '',
  );
  late final TextEditingController _cap = TextEditingController(
    text: widget.existing?.maxOff?.toString() ?? '',
  );
  late final TextEditingController _min = TextEditingController(
    text: (widget.existing?.minSubtotal ?? 0) == 0
        ? ''
        : '${widget.existing!.minSubtotal}',
  );
  late DateTime? _until = widget.existing?.validUntil;

  String? _error;

  static String _suffixOf(String code) {
    final int dash = code.indexOf('-');
    return dash == -1 ? code : code.substring(dash + 1);
  }

  @override
  void dispose() {
    _code.dispose();
    _amount.dispose();
    _cap.dispose();
    _min.dispose();
    super.dispose();
  }

  void _submit() {
    final String code = _code.text.trim();
    final int? amount = int.tryParse(_amount.text.trim());
    final int? cap = int.tryParse(_cap.text.trim());
    final int min = int.tryParse(_min.text.trim()) ?? 0;

    if (code.length < 3) {
      setState(() => _error = 'Give the offer a code of at least 3 characters.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(
        () => _error = _isFlat
            ? 'How many rupees off?'
            : 'What percentage off?',
      );
      return;
    }
    if (!_isFlat && (cap == null || cap <= 0)) {
      setState(() => _error = 'A percentage offer needs a maximum discount.');
      return;
    }

    Navigator.of(context).pop(
      _OfferDraft(
        code: code,
        minSubtotal: min,
        flatOff: _isFlat ? amount : null,
        percentOff: _isFlat ? null : amount,
        maxOff: _isFlat ? null : cap,
        validUntil: _until,
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _until ?? now.add(const Duration(days: 7)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    // The end of the chosen day, not its midnight: an offer that runs "until
    // Sunday" should still work on Sunday evening.
    setState(
      () => _until = DateTime(picked.year, picked.month, picked.day, 23, 59),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: ZopiqSpacing.lg,
        right: ZopiqSpacing.lg,
        top: ZopiqSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.existing == null ? 'New offer' : 'Edit offer',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            TextField(
              controller: _code,
              enabled: widget.existing == null,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Code',
                helperText: widget.existing == null
                    // Said plainly rather than discovered after saving: the
                    // database prefixes the restaurant id (0064), and a vendor
                    // who does not know that thinks their code was mangled.
                    ? 'Your restaurant\'s id is added in front automatically.'
                    : 'A code can\'t be renamed — pause it and make a new one.',
                isDense: true,
              ),
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('₹ off')),
                ButtonSegment<bool>(value: false, label: Text('% off')),
              ],
              selected: <bool>{_isFlat},
              onSelectionChanged: (Set<bool> s) =>
                  setState(() => _isFlat = s.first),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _isFlat ? 'Rupees off' : 'Percent off',
                      isDense: true,
                    ),
                  ),
                ),
                if (!_isFlat) ...<Widget>[
                  const SizedBox(width: ZopiqSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _cap,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Up to ₹',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: ZopiqSpacing.md),

            TextField(
              controller: _min,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum order value (optional)',
                isDense: true,
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _until == null
                        ? 'No end date'
                        : 'Ends ${_until!.day}/${_until!.month}/${_until!.year}',
                    style: t.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: _pickDate,
                  child: Text(_until == null ? 'Set end date' : 'Change'),
                ),
                if (_until != null)
                  TextButton(
                    onPressed: () => setState(() => _until = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),

            if (_error case final String message) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.sm),
              Text(
                message,
                style: t.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: ZopiqSpacing.lg),
            // Said before the button, not after the payout. An offer a
            // restaurant creates is funded by that restaurant — it comes off
            // the weekly statement, and commission is charged on what is left.
            // A vendor finding that out from a smaller bank transfer is how a
            // partner stops being one.
            Container(
              padding: const EdgeInsets.all(ZopiqSpacing.md),
              decoration: BoxDecoration(
                color: zc.textMuted.withValues(alpha: 0.06),
                borderRadius: ZopiqRadii.rMd,
              ),
              child: Text(
                'You fund this offer. The discount is deducted from your weekly '
                'payout, and commission is charged on the amount left after it.',
                style: t.bodySmall?.copyWith(color: zc.textMuted, height: 1.4),
              ),
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: zc.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _submit,
                child: Text(
                  widget.existing == null ? 'Create offer' : 'Save changes',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(ZopiqSpacing.xxl),
      child: Column(
        children: <Widget>[
          Icon(Icons.local_offer_outlined, size: 44, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.md),
          Text(
            'No offers yet',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'A code you create here works only on your own food, and shows up '
            'on your restaurant page.',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'We couldn\'t load your offers.',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
            const SizedBox(height: ZopiqSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
