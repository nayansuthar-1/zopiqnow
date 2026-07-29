import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';

/// Lays [invoice] out as a one-page A4 tax invoice.
///
/// **Nothing is computed here.** Every figure printed is a field of the document
/// the order service assembled (migration 0063) — the tax halves, the totals,
/// the serial. This file chooses where the numbers sit on the page and nothing
/// else, which is the only way two builds of this app can produce the same
/// piece of paper for the same order.
///
/// Deliberately black-on-white and typographic rather than branded: an invoice
/// is read by an accounts department, printed on a mono laser, and filed. The
/// orange belongs on the app, not on the paper.
Future<Uint8List> buildInvoicePdf(OrderInvoice invoice) async {
  final pw.Document doc = pw.Document(
    title: 'Invoice ${invoice.invoiceNo}',
    author: 'Zopiqnow',
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          _header(invoice),
          pw.SizedBox(height: 18),
          pw.Divider(height: 1, thickness: 0.8),
          pw.SizedBox(height: 14),
          _parties(invoice),
          pw.SizedBox(height: 18),
          _lines(invoice),
          pw.SizedBox(height: 14),
          _totals(invoice),
          pw.Spacer(),
          _footer(invoice),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _header(OrderInvoice invoice) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: <pw.Widget>[
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'TAX INVOICE',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Zopiqnow',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          _kv('Invoice no.', invoice.invoiceNo),
          _kv('Invoice date', _date(invoice.invoicedAt)),
          _kv('Order', invoice.orderId),
          _kv('Order date', _date(invoice.placedAt)),
        ],
      ),
    ],
  );
}

pw.Widget _parties(OrderInvoice invoice) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            _sectionLabel('SOLD BY'),
            pw.Text(
              invoice.seller.name ?? '—',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            if (invoice.seller.address case final String address)
              pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
            if (invoice.seller.phone case final String phone)
              pw.Text('Phone $phone', style: const pw.TextStyle(fontSize: 9)),
            // Not every kitchen is GST-registered — one under the threshold
            // legitimately has none (0028) — so the line is absent rather than
            // blank. A label with nothing after it reads as a missing number.
            if (invoice.seller.gstin case final String gstin)
              pw.Text('GSTIN $gstin', style: const pw.TextStyle(fontSize: 9)),
            if (invoice.seller.fssai case final String fssai)
              pw.Text('FSSAI $fssai', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            _sectionLabel('DELIVERED TO'),
            if (invoice.buyer.address case final String address)
              pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
            if (invoice.buyer.phone case final String phone)
              pw.Text(phone, style: const pw.TextStyle(fontSize: 9)),
            if (invoice.placeOfSupply case final String state) ...<pw.Widget>[
              pw.SizedBox(height: 4),
              pw.Text(
                'Place of supply: $state',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

pw.Widget _lines(OrderInvoice invoice) {
  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellHeight: 20,
    headerAlignment: pw.Alignment.centerLeft,
    cellAlignments: <int, pw.Alignment>{
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.center,
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
    },
    headers: <String>['Item', 'Qty', 'Rate', 'Amount'],
    data: <List<String>>[
      for (final InvoiceLine line in invoice.lines)
        <String>[
          line.description,
          '${line.quantity}',
          _money(line.unitPrice),
          _money(line.lineTotal),
        ],
    ],
  );
}

pw.Widget _totals(OrderInvoice invoice) {
  final String half = invoice.halfRate.toStringAsFixed(
    invoice.halfRate == invoice.halfRate.roundToDouble() ? 0 : 1,
  );

  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 240,
      child: pw.Column(
        children: <pw.Widget>[
          _totalRow('Taxable value', _money(invoice.taxableValue)),
          _totalRow('CGST @ $half%', _money(invoice.cgst)),
          _totalRow('SGST @ $half%', _money(invoice.sgst)),
          if (invoice.deliveryFee > 0)
            _totalRow('Delivery fee', _money(invoice.deliveryFee)),
          if (invoice.discount > 0)
            _totalRow(
              invoice.couponCode == null
                  ? 'Discount'
                  : 'Discount (${invoice.couponCode})',
              '- ${_money(invoice.discount)}',
            ),
          pw.Divider(height: 8, thickness: 0.8),
          _totalRow('Total', _money(invoice.total), bold: true),
        ],
      ),
    ),
  );
}

pw.Widget _footer(OrderInvoice invoice) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Divider(height: 1, thickness: 0.5),
      pw.SizedBox(height: 6),
      pw.Text(
        invoice.paymentMethod == 'cod'
            ? 'Paid by cash on delivery.'
            : 'Paid online. Reference ${invoice.paymentId ?? invoice.orderId}.',
        style: const pw.TextStyle(fontSize: 9),
      ),
      pw.SizedBox(height: 4),
      // The honest sentence about who sold what. Zopiqnow carried the food; the
      // kitchen cooked and sold it, and the GSTIN above is the kitchen's.
      pw.Text(
        'Zopiqnow is a technology platform. The supply of food above is made by '
        'the restaurant named as the seller. This is a computer-generated '
        'invoice and needs no signature.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
    ],
  );
}

pw.Widget _sectionLabel(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 4),
  child: pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey700,
      letterSpacing: 0.6,
    ),
  ),
);

pw.Widget _kv(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 1),
  child: pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: <pw.Widget>[
      pw.Text(
        '$label  ',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);

pw.Widget _totalRow(String label, String value, {bool bold = false}) {
  final pw.TextStyle style = pw.TextStyle(
    fontSize: bold ? 11 : 9,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    ),
  );
}

/// `Rs.` and not `₹`. The rupee glyph is absent from the PDF standard fonts, and
/// a missing glyph renders as a hollow box on somebody's tax document. A bundled
/// Unicode font would fix it and cost ~300 KB in the APK; this costs nothing and
/// is what most Indian invoices print anyway.
String _money(int rupees) => 'Rs. $rupees';

String _date(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')}/'
    '${at.month.toString().padLeft(2, '0')}/${at.year}';
