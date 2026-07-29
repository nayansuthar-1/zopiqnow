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
    required this.gstRate,
    required this.cgst,
    required this.sgst,
    required this.taxes,
    required this.total,
    required this.paymentMethod,
    this.couponCode,
    this.paymentId,
    this.placeOfSupply,
  });

  factory OrderInvoice.fromJson(Map<String, dynamic> json) {
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
      gstRate: (json['gst_rate'] as num).toDouble(),
      cgst: (json['cgst'] as num).toInt(),
      sgst: (json['sgst'] as num).toInt(),
      taxes: (json['taxes'] as num).toInt(),
      total: (json['total'] as num).toInt(),
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

  final int taxableValue;
  final int discount;
  final String? couponCode;
  final int deliveryFee;

  /// The rate the tax was charged at, halved between [cgst] and [sgst] for an
  /// intra-state supply. 5.0 today, and read off the document rather than
  /// assumed, so a rate change does not need an app release to be printed
  /// correctly.
  final double gstRate;
  final int cgst;
  final int sgst;
  final int taxes;
  final int total;

  final String paymentMethod;
  final String? paymentId;
  final String? placeOfSupply;

  double get halfRate => gstRate / 2;
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
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    name: json['name'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unitPrice: (json['unit_price'] as num).toInt(),
    lineTotal: (json['line_total'] as num).toInt(),
    options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
        .cast<String>()
        .toList(growable: false),
  );

  final String name;
  final int quantity;
  final int unitPrice;
  final int lineTotal;
  final List<String> options;

  String get description =>
      options.isEmpty ? name : '$name (${options.join(', ')})';
}
