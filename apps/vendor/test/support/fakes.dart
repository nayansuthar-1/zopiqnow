import 'dart:async';

import 'package:zopiq_vendor/features/auth/data/vendor_auth_datasource.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/orders/data/vendor_order_datasource.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';

const Vendor testVendor = Vendor(
  email: 'kitchen@paradise.in',
  restaurantId: 'r1',
  restaurantName: 'Paradise Biryani',
);

class FakeVendorAuthDataSource implements VendorAuthDataSource {
  FakeVendorAuthDataSource({this.signedInAs, this.staff = true});

  /// The session in the Keystore, if any.
  final Vendor? signedInAs;

  /// Whether the address that verifies an OTP turns out to work at a restaurant.
  final bool staff;

  String? lastCodeSentTo;

  @override
  Future<void> sendEmailOtp(String email) async => lastCodeSentTo = email;

  @override
  Future<Vendor?> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    if (code != '123456') throw const VendorAuthFailure();
    return staff ? testVendor : null;
  }

  @override
  Future<Vendor?> restoreSession() async => signedInAs;

  @override
  Future<void> signOut() async {}
}

/// The order book, in memory, with a stream that behaves like Postgres does:
/// a write goes to the store, and the *store* pushes the new list at everyone.
/// Nothing echoes a status back to the caller, because the real one does not.
class FakeVendorOrderDataSource implements VendorOrderDataSource {
  FakeVendorOrderDataSource({List<VendorOrder> orders = const <VendorOrder>[]})
    : _orders = List<VendorOrder>.of(orders);

  List<VendorOrder> _orders;

  final StreamController<List<VendorOrder>> _controller =
      StreamController<List<VendorOrder>>.broadcast();

  /// Set to refuse the next move, the way `set_order_status` refuses an illegal
  /// transition — with a sentence written for a human.
  String? refusal;

  final List<OrderLine> lines = const <OrderLine>[
    OrderLine(name: 'Chicken Biryani', quantity: 2, lineTotal: 640),
    OrderLine(name: 'Raita', quantity: 1, lineTotal: 40),
  ];

  @override
  Stream<List<VendorOrder>> watchOrders(String restaurantId) async* {
    yield _orders;
    yield* _controller.stream;
  }

  @override
  Future<List<OrderLine>> fetchLines(String orderId) async => lines;

  @override
  Future<OrderStatus> setStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    if (refusal != null) throw OrderStatusFailure(refusal!);

    _orders = _orders
        .map(
          (VendorOrder o) => o.id == orderId
              ? VendorOrder(
                  id: o.id,
                  status: status,
                  placedAt: o.placedAt,
                  customerPhone: o.customerPhone,
                  deliveryTo: o.deliveryTo,
                  total: o.total,
                  paymentMethod: o.paymentMethod,
                )
              : o,
        )
        .toList(growable: false);
    _controller.add(_orders);
    return status;
  }

  void dispose() => _controller.close();
}

VendorOrder order({
  String id = 'ZPQ-1042',
  OrderStatus status = OrderStatus.placed,
  Duration age = const Duration(minutes: 4),
  PaymentMethod paymentMethod = PaymentMethod.cod,
  int total = 720,
}) => VendorOrder(
  id: id,
  status: status,
  placedAt: DateTime.now().subtract(age),
  customerPhone: '+919876543210',
  deliveryTo: 'Banjara Hills, Hyderabad',
  total: total,
  paymentMethod: paymentMethod,
);
