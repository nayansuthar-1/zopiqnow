import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/invoice_pdf.dart';

/// The tax invoice for one delivered order, on screen and — one tap away — as a
/// PDF the customer can keep.
///
/// The screen and the PDF render the *same document*: both read the fields
/// `order_invoice` returned and neither computes a figure. That is why the page
/// is not a preview of the file — it is the same statement in two media, and
/// they cannot disagree.
class InvoicePage extends ConsumerWidget {
  const InvoicePage({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<OrderInvoice> invoice = ref.watch(
      orderInvoiceProvider(orderId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice'), centerTitle: false),
      body: invoice.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // The service's own sentence, verbatim: "An invoice is issued once your
        // order has been delivered." is a complete answer, and "something went
        // wrong" would replace it with nothing.
        error: (Object error, StackTrace _) => _InvoiceError(
          message: error is InvoiceFailure
              ? error.message
              : 'We couldn\'t load this invoice. Please try again.',
          onRetry: () => ref.invalidate(orderInvoiceProvider(orderId)),
        ),
        data: (OrderInvoice doc) => _InvoiceBody(invoice: doc),
      ),
    );
  }
}

class _InvoiceBody extends StatefulWidget {
  const _InvoiceBody({required this.invoice});

  final OrderInvoice invoice;

  @override
  State<_InvoiceBody> createState() => _InvoiceBodyState();
}

class _InvoiceBodyState extends State<_InvoiceBody> {
  bool _isBuilding = false;

  /// Hands the file to the platform's own share sheet — Drive, Gmail, Files,
  /// whatever the phone has. "Download" on Android has meant "pick where this
  /// goes" for several versions now, and a share sheet is that picker.
  Future<void> _share() async {
    setState(() => _isBuilding = true);
    try {
      final Uint8List bytes = await buildInvoicePdf(widget.invoice);
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        // The invoice number, made safe for a filename: the serial carries
        // slashes, and a slash in a filename is a directory on every platform
        // that has ever had one.
        filename:
            '${widget.invoice.invoiceNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.pdf',
      );
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('We couldn\'t prepare that file.')),
        );
    } finally {
      if (mounted) setState(() => _isBuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OrderInvoice doc = widget.invoice;
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final String half = doc.halfRate.toStringAsFixed(
      doc.halfRate == doc.halfRate.roundToDouble() ? 0 : 1,
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: <Widget>[
              Text(
                'TAX INVOICE',
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                doc.invoiceNo,
                style: t.bodyMedium?.copyWith(
                  color: zc.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${doc.orderId} · ${_date(doc.invoicedAt)}',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),

              const SizedBox(height: 20),
              const _Label('SOLD BY'),
              Text(
                doc.seller.name ?? '—',
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (doc.seller.address case final String address)
                Text(address, style: t.bodySmall),
              if (doc.seller.gstin case final String gstin)
                Text('GSTIN $gstin', style: t.bodySmall),
              if (doc.seller.fssai case final String fssai)
                Text('FSSAI $fssai', style: t.bodySmall),

              const SizedBox(height: 16),
              const _Label('DELIVERED TO'),
              if (doc.buyer.address case final String address)
                Text(address, style: t.bodySmall),
              if (doc.buyer.phone case final String phone)
                Text(phone, style: t.bodySmall),
              if (doc.placeOfSupply case final String state)
                Text('Place of supply: $state', style: t.bodySmall),

              const SizedBox(height: 20),
              const _Label('ITEMS'),
              for (final InvoiceLine line in doc.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${line.quantity}×',
                        style: t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: zc.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(line.description, style: t.bodyMedium),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '₹${line.lineTotal}',
                        style: t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
              const Divider(height: 24),
              _Row(label: 'Taxable value', value: '₹${doc.taxableValue}'),
              _Row(label: 'CGST @ $half%', value: '₹${doc.cgst}'),
              _Row(label: 'SGST @ $half%', value: '₹${doc.sgst}'),
              if (doc.deliveryFee > 0)
                _Row(label: 'Delivery fee', value: '₹${doc.deliveryFee}'),
              if (doc.discount > 0)
                _Row(
                  label: doc.couponCode == null
                      ? 'Discount'
                      : 'Discount (${doc.couponCode})',
                  value: '−₹${doc.discount}',
                ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Total',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '₹${doc.total}',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Text(
                doc.paymentMethod == 'cod'
                    ? 'Paid by cash on delivery.'
                    : 'Paid online. Reference ${doc.paymentId ?? doc.orderId}.',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: 6),
              Text(
                'Zopiqnow is a technology platform. The supply of food above is '
                'made by the restaurant named as the seller.',
                style: t.bodySmall?.copyWith(
                  color: zc.textMuted,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isBuilding ? null : _share,
              icon: _isBuilding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: Text(
                _isBuilding ? 'Preparing…' : 'Download PDF',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: context.zc.textMuted,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodyMedium),
          Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _InvoiceError extends StatelessWidget {
  const _InvoiceError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: context.zc.textMuted,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: t.bodyMedium),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')}/'
    '${at.month.toString().padLeft(2, '0')}/${at.year}';
