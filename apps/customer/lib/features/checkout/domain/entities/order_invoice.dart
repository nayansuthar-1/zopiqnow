import 'package:flutter/foundation.dart';

/// A tax invoice for one delivered order, exactly as `order_invoice` assembled
/// it (migration 0063).
///
/// Nothing here is computed on the phone — not the tax halves, not the totals,
/// not the invoice number. This class parses a document; it does not produce
/// one. That matters because two customers looking at the same order, on two
/// builds of this app, must be holding the same piece of paper.
@immutable
class OrderInvoice {
  const OrderInvoice({
    required this.invoiceNo,
    required this.invoicedAt,
    required this.orderId,
    required this.placedAt,
    required this.seller,
    required this.buyer,
    required this.lines,
    required this.taxableValue,
    required this.discount,
    required this.deliveryFee,
    required this.cgst,
    required this.sgst,
    required this.taxes,
    required this.total,
    required this.paymentMethod,
    this.pricingVersion = 1,
    this.gstRate,
    this.igst = 0,
    this.taxOnFees = 0,
    this.platformFee = 0,
    this.packagingFee = 0,
    this.surgeFee = 0,
    this.taxLines = const <InvoiceTaxLine>[],
    this.couponCode,
    this.paymentId,
    this.placeOfSupply,
  });

  factory OrderInvoice.fromJson(Map<String, dynamic> json) {
    // Absent on a document rendered by a server older than 0078, and the fees
    // it does not name are the fees that did not exist.
    final Map<String, dynamic> fees =
        (json['fees'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return OrderInvoice(
      invoiceNo: json['invoice_no'] as String,
      invoicedAt: DateTime.parse(json['invoiced_at'] as String).toLocal(),
      orderId: json['order_id'] as String,
      placedAt: DateTime.parse(json['placed_at'] as String).toLocal(),
      seller: InvoiceParty.fromJson(json['seller'] as Map<String, dynamic>),
      buyer: InvoiceParty.fromJson(json['buyer'] as Map<String, dynamic>),
      lines: (json['lines'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(InvoiceLine.fromJson)
          .toList(growable: false),
      taxableValue: (json['taxable_value'] as num).toInt(),
      discount: (json['discount'] as num).toInt(),
      couponCode: json['coupon_code'] as String?,
      deliveryFee: (json['delivery_fee'] as num).toInt(),
      platformFee: (fees['platform'] as num?)?.toInt() ?? 0,
      packagingFee: (fees['packaging'] as num?)?.toInt() ?? 0,
      surgeFee: (fees['surge'] as num?)?.toInt() ?? 0,
      taxOnFees: (json['tax_on_fees'] as num?)?.toInt() ?? 0,
      gstRate: (json['gst_rate'] as num?)?.toDouble(),
      taxLines: (json['tax_lines'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(InvoiceTaxLine.fromJson)
          .toList(growable: false),
      cgst: (json['cgst'] as num).toInt(),
      sgst: (json['sgst'] as num).toInt(),
      igst: (json['igst'] as num?)?.toInt() ?? 0,
      taxes: (json['taxes'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      pricingVersion: (json['pricing_version'] as num?)?.toInt() ?? 1,
      paymentMethod: json['payment_method'] as String,
      paymentId: json['payment_id'] as String?,
      placeOfSupply: json['place_of_supply'] as String?,
    );
  }

  final String invoiceNo;
  final DateTime invoicedAt;
  final String orderId;
  final DateTime placedAt;

  final InvoiceParty seller;
  final InvoiceParty buyer;
  final List<InvoiceLine> lines;

  /// What GST was charged on. Post-discount on an order priced by migration
  /// 0078; the plain subtotal on one placed before it, because that is the base
  /// the tax beside it was computed from.
  final int taxableValue;
  final int discount;
  final String? couponCode;

  /// The fee stack, each line gross — the GST inside them is [taxOnFees] and is
  /// not added on top. Everything but delivery is 0 until somebody turns it on.
  final int deliveryFee;
  final int platformFee;
  final int packagingFee;
  final int surgeFee;
  final int taxOnFees;

  /// The rate the tax was charged at, halved between [cgst] and [sgst] for an
  /// intra-state supply. 5.0 on every order so far, and read off the document
  /// rather than assumed, so a rate change does not need an app release to be
  /// printed correctly.
  ///
  /// Null when the order spans more than one GST slab: there is no single rate
  /// to print then, and [taxLines] is the statement that has to be shown
  /// instead.
  final double? gstRate;

  /// The rate-wise summary a tax invoice is required to carry. Empty on an
  /// order placed before 0078, which was taxed once at the order level and has
  /// no honest per-rate split.
  final List<InvoiceTaxLine> taxLines;

  final int cgst;
  final int sgst;
  final int igst;

  /// The whole GST liability on this order — on the food and inside the fees.
  final int taxes;
  final int total;

  final String paymentMethod;
  final String? paymentId;
  final String? placeOfSupply;

  /// 1 for an order priced before migration 0078 — one flat rate on the
  /// pre-discount subtotal, and a delivery fee nobody charged tax on. 2 for one
  /// priced after. The two are read as different documents because they are.
  final int pricingVersion;

  double? get halfRate => gstRate == null ? null : gstRate! / 2;

  /// The body of the bill, in the order it is printed — computed once here so
  /// that the screen and the PDF cannot drift into stating different things
  /// about the same invoice.
  List<InvoiceBillRow> get billRows {
    final List<InvoiceBillRow> rows = <InvoiceBillRow>[];

    if (pricingVersion >= 2) {
      // The tax sits on the discounted value, so the discount has to appear
      // above the taxable value it produced rather than below it.
      rows.add(InvoiceBillRow('Item total', taxableValue + discount));
      if (discount > 0) {
        rows.add(InvoiceBillRow(
          couponCode == null ? 'Discount' : 'Discount ($couponCode)',
          discount,
          negative: true,
        ));
      }
      rows.add(InvoiceBillRow('Taxable value', taxableValue));
      for (final InvoiceTaxLine line in taxLines) {
        final String half = _rate(line.halfRate);
        if (igst > 0) {
          rows.add(InvoiceBillRow('IGST @ ${_rate(line.ratePercent)}%', line.tax));
        } else {
          final int cgstPart = (line.tax / 2).round();
          rows.add(InvoiceBillRow('CGST @ $half%', cgstPart));
          rows.add(InvoiceBillRow('SGST @ $half%', line.tax - cgstPart));
        }
      }
      // Gross, with the GST already inside them — said on the line so nobody
      // has to wonder whether it was charged twice.
      if (deliveryFee > 0) {
        rows.add(InvoiceBillRow('Delivery fee (incl. GST)', deliveryFee));
      }
      if (platformFee > 0) {
        rows.add(InvoiceBillRow('Platform fee (incl. GST)', platformFee));
      }
      if (packagingFee > 0) {
        rows.add(InvoiceBillRow('Packaging (incl. GST)', packagingFee));
      }
      if (surgeFee > 0) {
        rows.add(InvoiceBillRow('Surge (incl. GST)', surgeFee));
      }
      return rows;
    }

    // Version 1, unchanged since migration 0063 — the same rows, in the same
    // order, saying the same thing about an order that was charged that way.
    final String half = gstRate == null ? '2.5' : _rate(gstRate! / 2);
    rows.add(InvoiceBillRow('Taxable value', taxableValue));
    rows.add(InvoiceBillRow('CGST @ $half%', cgst));
    rows.add(InvoiceBillRow('SGST @ $half%', sgst));
    if (deliveryFee > 0) {
      rows.add(InvoiceBillRow('Delivery fee', deliveryFee));
    }
    if (discount > 0) {
      rows.add(InvoiceBillRow(
        couponCode == null ? 'Discount' : 'Discount ($couponCode)',
        discount,
        negative: true,
      ));
    }
    return rows;
  }

  /// "5" and "2.5", never "5.0" — a rate on a document reads as a number, not
  /// as a double.
  static String _rate(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}

/// One printed line of the bill: a label and a rupee amount, the amount shown as
/// a deduction when [negative].
@immutable
class InvoiceBillRow {
  const InvoiceBillRow(this.label, this.amount, {this.negative = false});

  final String label;
  final int amount;
  final bool negative;
}

/// One row of the rate-wise tax summary: everything on the order taxed at this
/// slab, and the tax it bore.
@immutable
class InvoiceTaxLine {
  const InvoiceTaxLine({
    required this.ratePercent,
    required this.taxable,
    required this.tax,
  });

  factory InvoiceTaxLine.fromJson(Map<String, dynamic> json) => InvoiceTaxLine(
    ratePercent: (json['rate_percent'] as num).toDouble(),
    taxable: (json['taxable'] as num).toInt(),
    tax: (json['tax'] as num).toInt(),
  );

  final double ratePercent;
  final int taxable;
  final int tax;

  double get halfRate => ratePercent / 2;
}

/// A named side of the invoice: the kitchen that sold, or the customer who
/// bought. Every field but the name is optional — a restaurant under the GST
/// threshold legitimately has no GSTIN (0028), and a document omits a line it
/// has nothing to put on rather than printing a blank label.
@immutable
class InvoiceParty {
  const InvoiceParty({this.name, this.address, this.phone, this.gstin, this.fssai});

  factory InvoiceParty.fromJson(Map<String, dynamic> json) => InvoiceParty(
    name: json['name'] as String?,
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    gstin: json['gstin'] as String?,
    fssai: json['fssai'] as String?,
  );

  final String? name;
  final String? address;
  final String? phone;
  final String? gstin;
  final String? fssai;
}

/// One frozen line of the order, priced as it was charged.
@immutable
class InvoiceLine {
  const InvoiceLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.options,
    this.hsn,
    this.gstRate,
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    name: json['name'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unitPrice: (json['unit_price'] as num).toInt(),
    lineTotal: (json['line_total'] as num).toInt(),
    options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
        .cast<String>()
        .toList(growable: false),
    hsn: json['hsn'] as String?,
    gstRate: (json['gst_rate'] as num?)?.toDouble(),
  );

  final String name;
  final int quantity;
  final int unitPrice;
  final int lineTotal;
  final List<String> options;

  /// The dish's HSN/SAC, printed beside it when the menu has been classified.
  /// Null on most lines — nobody has classified a menu yet.
  final String? hsn;

  /// The slab this line was taxed at. Null on a line frozen before 0078.
  final double? gstRate;

  String get description =>
      options.isEmpty ? name : '$name (${options.join(', ')})';
}
