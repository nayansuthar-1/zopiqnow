import 'dart:async';

import 'package:zopiq_vendor/features/auth/data/vendor_auth_datasource.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/menu/data/vendor_menu_datasource.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/orders/data/vendor_order_datasource.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';

const Vendor testVendor = Vendor(
  email: 'kitchen@paradise.in',
  restaurantId: 'r1',
  restaurantName: 'Paradise Biryani',
  acceptingOrders: true,
);

class FakeVendorAuthDataSource implements VendorAuthDataSource {
  FakeVendorAuthDataSource({this.signedInAs, this.staff = true});

  /// The session in the Keystore, if any.
  final Vendor? signedInAs;

  /// Whether the address that verifies an OTP turns out to work at a restaurant.
  final bool staff;

  String? lastCodeSentTo;

  /// The last value `setAcceptingOrders` was asked to write, and whether that
  /// write should throw — so a test can drive both the happy path and the
  /// revert-on-failure path.
  bool? lastAcceptingOrders;
  bool failAcceptingOrders = false;

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
  Future<void> setAcceptingOrders(bool accepting) async {
    if (failAcceptingOrders) throw Exception('offline');
    lastAcceptingOrders = accepting;
  }

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

VendorDish dish({
  String id = 'd1',
  String name = 'Chicken Biryani',
  String description = '',
  int price = 320,
  bool isVeg = false,
  String category = 'Biryanis',
  bool isAvailable = true,
}) => VendorDish(
  id: id,
  name: name,
  description: description,
  price: price,
  isVeg: isVeg,
  category: category,
  isAvailable: isAvailable,
);

/// The menu, in memory. Grouping mirrors the real datasource — by category, in
/// the order each first appears — and the failure hooks let a test rehearse the
/// two refusals that matter: a write the database rejects, and a delete the
/// foreign key forbids.
class FakeVendorMenuDataSource implements VendorMenuDataSource {
  FakeVendorMenuDataSource({List<VendorDish> dishes = const <VendorDish>[]})
    : _dishes = List<VendorDish>.of(dishes);

  List<VendorDish> _dishes;

  /// Set to make the next add/edit/toggle fail with this sentence.
  String? writeFailure;

  /// Set to make delete fail the way a dish on a past order does.
  bool deleteInUse = false;

  int _nextId = 1;

  List<VendorDish> get dishes => List<VendorDish>.unmodifiable(_dishes);

  @override
  Future<List<VendorMenuSection>> fetchMenu(String restaurantId) async {
    final Map<String, List<VendorDish>> sections =
        <String, List<VendorDish>>{};
    for (final VendorDish d in _dishes) {
      sections.putIfAbsent(d.category, () => <VendorDish>[]).add(d);
    }
    return sections.entries
        .map(
          (MapEntry<String, List<VendorDish>> e) =>
              VendorMenuSection(title: e.key, dishes: e.value),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setAvailability({
    required String dishId,
    required bool isAvailable,
  }) async {
    if (writeFailure != null) throw MenuWriteFailure(writeFailure!);
    _dishes = _dishes
        .map(
          (VendorDish d) =>
              d.id == dishId ? d.copyWith(isAvailable: isAvailable) : d,
        )
        .toList(growable: false);
  }

  @override
  Future<VendorDish> saveDish(
    VendorDish dish, {
    required String restaurantId,
  }) async {
    if (writeFailure != null) throw MenuWriteFailure(writeFailure!);
    if (dish.isNew) {
      final VendorDish created = VendorDish(
        id: 'new-${_nextId++}',
        name: dish.name,
        description: dish.description,
        price: dish.price,
        isVeg: dish.isVeg,
        category: dish.category,
        isAvailable: true,
      );
      _dishes = <VendorDish>[..._dishes, created];
      return created;
    }
    _dishes = _dishes
        .map((VendorDish d) => d.id == dish.id ? dish : d)
        .toList(growable: false);
    return dish;
  }

  @override
  Future<void> deleteDish(String dishId) async {
    if (deleteInUse) throw const MenuItemInUseFailure();
    _dishes = _dishes
        .where((VendorDish d) => d.id != dishId)
        .toList(growable: false);
  }
}
