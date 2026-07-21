import 'dart:async';

import 'package:zopiq_vendor/features/auth/data/vendor_auth_datasource.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/menu/data/vendor_menu_datasource.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/notifications/data/notifications_datasource.dart';
import 'package:zopiq_vendor/features/notifications/domain/entities/vendor_notification.dart';
import 'package:zopiq_vendor/features/orders/data/vendor_order_datasource.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/core/images/image_uploader.dart';
import 'package:zopiq_vendor/features/analytics/data/analytics_datasource.dart';
import 'package:zopiq_vendor/features/analytics/domain/entities/analytics_summary.dart';
import 'package:zopiq_vendor/features/payments/data/payments_datasource.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/settlement.dart';
import 'package:zopiq_vendor/features/profile/data/restaurant_hours_datasource.dart';
import 'package:zopiq_vendor/features/profile/data/vendor_restaurant_datasource.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/opening_hours.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/restaurant_profile.dart';
import 'package:zopiq_vendor/features/staff/data/staff_datasource.dart';
import 'package:zopiq_vendor/features/staff/domain/entities/staff_member.dart';

/// The default signed-in vendor: the owner, because that is what every existing
/// test was written against (before 0024 there was only one kind of vendor, and
/// it could do everything).
const Vendor testVendor = Vendor(
  email: 'kitchen@paradise.in',
  restaurantId: 'r1',
  restaurantName: 'Paradise Biryani',
  acceptingOrders: true,
  role: StaffRole.owner,
);

/// The same kitchen, seen by someone who is not the owner.
const Vendor testStaffVendor = Vendor(
  email: 'cook@paradise.in',
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
  Future<List<VendorOrder>> fetchHistory({
    required String restaurantId,
    required DateTime from,
    required DateTime to,
    int limit = 500,
  }) async {
    final List<VendorOrder> matches = _orders
        .where(
          (VendorOrder o) =>
              !o.status.isOpen &&
              !o.placedAt.isBefore(from) &&
              !o.placedAt.isAfter(to),
        )
        .toList();
    matches.sort((VendorOrder a, VendorOrder b) => b.placedAt.compareTo(a.placedAt));
    return matches.take(limit).toList(growable: false);
  }

  /// A brand-new order lands on the stream — the event the new-order alarm rings
  /// for. `setStatus` only ever *moves* an order already here, so this is the one
  /// way to rehearse arrival.
  void arrive(VendorOrder newOrder) {
    _orders = <VendorOrder>[..._orders, newOrder];
    _controller.add(_orders);
  }

  @override
  Future<List<OrderLine>> fetchLines(String orderId) async => lines;

  @override
  Future<OrderStatus> setStatus({
    required String orderId,
    required OrderStatus status,
    String? reason,
    int? prepMinutes,
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
                  subtotal: o.subtotal,
                  deliveryFee: o.deliveryFee,
                  taxes: o.taxes,
                  discount: o.discount,
                  total: o.total,
                  paymentMethod: o.paymentMethod,
                  etaMinutes: o.etaMinutes,
                  // Mirrors the database: a prep time stamps ready_by on accept.
                  readyBy:
                      status == OrderStatus.accepted && prepMinutes != null
                      ? DateTime.now().add(Duration(minutes: prepMinutes))
                      : o.readyBy,
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
  int? subtotal,
  int deliveryFee = 0,
  int taxes = 0,
  int discount = 0,
  int etaMinutes = 30,
  DateTime? readyBy,
}) => VendorOrder(
  id: id,
  status: status,
  placedAt: DateTime.now().subtract(age),
  customerPhone: '+919876543210',
  deliveryTo: 'Banjara Hills, Hyderabad',
  subtotal: subtotal ?? total,
  deliveryFee: deliveryFee,
  taxes: taxes,
  discount: discount,
  total: total,
  paymentMethod: paymentMethod,
  etaMinutes: etaMinutes,
  readyBy: readyBy,
);

VendorDish dish({
  String id = 'd1',
  String name = 'Chicken Biryani',
  String description = '',
  int price = 320,
  bool isVeg = false,
  bool isBestseller = false,
  String category = 'Biryanis',
  bool isAvailable = true,
}) => VendorDish(
  id: id,
  name: name,
  description: description,
  price: price,
  isVeg: isVeg,
  isBestseller: isBestseller,
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

  /// Which sections are switched off. Absent means on — the same default the
  /// `category_available` column carries.
  final Map<String, bool> _categoryAvailable = <String, bool>{};

  /// Set to make the next add/edit/toggle fail with this sentence.
  String? writeFailure;

  /// Set to make delete fail the way a dish on a past order does.
  bool deleteInUse = false;

  int _nextId = 1;

  List<VendorDish> get dishes => List<VendorDish>.unmodifiable(_dishes);

  /// Whether a section is on the customer menu, as the store last recorded it.
  bool categoryAvailable(String category) => _categoryAvailable[category] ?? true;

  @override
  Future<List<VendorMenuSection>> fetchMenu(String restaurantId) async {
    // Insertion-ordered, like the real one: a section appears where its first
    // dish sits, so reordering the dish list reorders the sections.
    final Map<String, List<VendorDish>> sections =
        <String, List<VendorDish>>{};
    for (final VendorDish d in _dishes) {
      sections.putIfAbsent(d.category, () => <VendorDish>[]).add(d);
    }
    return sections.entries
        .map(
          (MapEntry<String, List<VendorDish>> e) => VendorMenuSection(
            title: e.key,
            dishes: e.value,
            isAvailable: categoryAvailable(e.key),
          ),
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
        isBestseller: dish.isBestseller,
        category: dish.category,
        isAvailable: true,
        imageUrl: dish.imageUrl,
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

  @override
  Future<void> reorderCategories({
    required String restaurantId,
    required List<String> orderedTitles,
  }) async {
    if (writeFailure != null) throw MenuWriteFailure(writeFailure!);
    // Regroup the flat list into the new section order, keeping each section's
    // own dishes in place — the same way stamping category_rank re-sorts it.
    _dishes = <VendorDish>[
      for (final String title in orderedTitles)
        ..._dishes.where((VendorDish d) => d.category == title),
    ];
  }

  @override
  Future<void> renameCategory({
    required String restaurantId,
    required String from,
    required String to,
  }) async {
    if (writeFailure != null) throw MenuWriteFailure(writeFailure!);
    _dishes = _dishes
        .map(
          (VendorDish d) => d.category == from ? d.copyWith(category: to) : d,
        )
        .toList(growable: false);
    if (_categoryAvailable.containsKey(from)) {
      _categoryAvailable[to] = _categoryAvailable.remove(from)!;
    }
  }

  @override
  Future<void> setCategoryAvailability({
    required String restaurantId,
    required String category,
    required bool isAvailable,
  }) async {
    if (writeFailure != null) throw MenuWriteFailure(writeFailure!);
    _categoryAvailable[category] = isAvailable;
  }
}

/// The money read side, in memory. Defaults to a kitchen with nothing earned
/// yet, so the Home dashboard — always mounted first now — renders without
/// reaching for Supabase. A test that cares about earnings passes its own.
class FakePaymentsDataSource implements PaymentsDataSource {
  FakePaymentsDataSource({
    this.earnings,
    this.settlements = const <Settlement>[],
  });

  final EarningsSummary? earnings;
  final List<Settlement> settlements;

  @override
  Future<EarningsSummary> fetchEarnings({
    required DateTime from,
    required DateTime to,
  }) async =>
      earnings ??
      EarningsSummary(
        from: from,
        to: to,
        commissionBps: 2000,
        orderCount: 0,
        grossSales: 0,
        commission: 0,
        netEarnings: 0,
        daily: const <DailyEarning>[],
      );

  @override
  Future<List<Settlement>> fetchSettlements() async => settlements;

  @override
  Future<List<SettlementOrder>> fetchSettlementOrders(int settlementId) async =>
      const <SettlementOrder>[];
}

/// The inbox, in memory, with a stream that behaves like Postgres does: a write
/// goes to the store, and the store pushes the new list at everyone. Defaults to
/// an empty inbox, so the Home bell — always mounted — renders without Supabase.
class FakeNotificationsDataSource implements NotificationsDataSource {
  FakeNotificationsDataSource({
    List<VendorNotification> initial = const <VendorNotification>[],
  }) : _items = List<VendorNotification>.of(initial);

  List<VendorNotification> _items;

  final StreamController<List<VendorNotification>> _controller =
      StreamController<List<VendorNotification>>.broadcast();

  /// What the screen asked to mark read, so a test can assert the tap wrote.
  final List<int> markedRead = <int>[];
  int markAllCalls = 0;

  @override
  Stream<List<VendorNotification>> watch(String restaurantId) async* {
    yield _items;
    yield* _controller.stream;
  }

  @override
  Future<void> markRead(int id) async {
    markedRead.add(id);
    _items = _items
        .map((VendorNotification n) => n.id == id ? _seen(n) : n)
        .toList(growable: false);
    _controller.add(_items);
  }

  @override
  Future<void> markAllRead() async {
    markAllCalls++;
    _items = _items.map(_seen).toList(growable: false);
    _controller.add(_items);
  }

  static VendorNotification _seen(VendorNotification n) => n.isUnread
      ? VendorNotification(
          id: n.id,
          kind: n.kind,
          title: n.title,
          body: n.body,
          orderId: n.orderId,
          createdAt: n.createdAt,
          readAt: DateTime.now(),
        )
      : n;

  void dispose() => _controller.close();
}

VendorNotification notification({
  int id = 1,
  NotificationKind kind = NotificationKind.newOrder,
  String title = 'New order',
  String? body = 'Order ZPQ-1042 · ₹720',
  String? orderId = 'ZPQ-1042',
  Duration age = const Duration(minutes: 2),
  bool read = false,
}) => VendorNotification(
  id: id,
  kind: kind,
  title: title,
  body: body,
  orderId: orderId,
  createdAt: DateTime.now().subtract(age),
  readAt: read ? DateTime.now() : null,
);

/// The roster, in memory. Mirrors 0024's refusals that the screen actually
/// renders — acting on yourself, and an address already on another team.
class FakeStaffDataSource implements StaffDataSource {
  FakeStaffDataSource({
    List<StaffMember> initial = const <StaffMember>[],
    this.callerEmail = 'kitchen@paradise.in',
  }) : _members = List<StaffMember>.of(initial);

  List<StaffMember> _members;

  /// Who the database would see as the caller — used for the self-action rules.
  final String callerEmail;

  /// Addresses the database would report as belonging to another restaurant.
  final Set<String> takenElsewhere = <String>{};

  List<StaffMember> get members => List<StaffMember>.unmodifiable(_members);

  @override
  Future<List<StaffMember>> fetch() async => _sorted(_members);

  @override
  Future<void> add({required String email, required StaffRole role}) async {
    if (_members.any((StaffMember m) => m.email == email)) {
      throw StaffWriteFailure('$email already works here.');
    }
    if (takenElsewhere.contains(email)) {
      throw StaffWriteFailure(
        '$email is already on another restaurant\'s team.',
      );
    }
    _members = <StaffMember>[
      ..._members,
      StaffMember(email: email, role: role, createdAt: DateTime.now()),
    ];
  }

  @override
  Future<void> setRole({
    required String email,
    required StaffRole role,
  }) async {
    if (email == callerEmail) {
      throw const StaffWriteFailure('You can\'t change your own role.');
    }
    _require(email);
    _members = _members
        .map(
          (StaffMember m) => m.email == email
              ? StaffMember(email: m.email, role: role, createdAt: m.createdAt)
              : m,
        )
        .toList(growable: false);
  }

  @override
  Future<void> remove(String email) async {
    if (email == callerEmail) {
      throw const StaffWriteFailure('You can\'t remove yourself.');
    }
    _require(email);
    _members = _members
        .where((StaffMember m) => m.email != email)
        .toList(growable: false);
  }

  void _require(String email) {
    if (!_members.any((StaffMember m) => m.email == email)) {
      throw StaffWriteFailure('$email is not on your team.');
    }
  }

  /// Owners first, then oldest first — the order the RPC returns.
  static List<StaffMember> _sorted(List<StaffMember> members) {
    final List<StaffMember> copy = List<StaffMember>.of(members)
      ..sort((StaffMember a, StaffMember b) {
        if (a.role != b.role) return a.role.isOwner ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    return List<StaffMember>.unmodifiable(copy);
  }
}

StaffMember staffMember({
  String email = 'cook@paradise.in',
  StaffRole role = StaffRole.staff,
  Duration age = const Duration(days: 3),
}) => StaffMember(
  email: email,
  role: role,
  createdAt: DateTime.now().subtract(age),
);

/// The opening hours, in memory. Defaults to an empty week — "always open",
/// which is what a restaurant that has never set an hour is.
class FakeRestaurantHoursDataSource implements RestaurantHoursDataSource {
  FakeRestaurantHoursDataSource({List<OpeningHours> initial = const <OpeningHours>[]})
    : _hours = List<OpeningHours>.of(initial);

  List<OpeningHours> _hours;

  /// Set to make the next save fail with this sentence.
  String? saveFailure;

  /// The week the last successful save wrote.
  List<OpeningHours>? lastSaved;

  @override
  Future<List<OpeningHours>> fetch(String restaurantId) async => _hours;

  @override
  Future<void> save(List<OpeningHours> hours) async {
    if (saveFailure != null) throw HoursWriteFailure(saveFailure!);
    _hours = List<OpeningHours>.of(hours);
    lastSaved = _hours;
  }
}

/// The analytics summary, served from memory. Defaults to an empty window.
class FakeAnalyticsDataSource implements AnalyticsDataSource {
  FakeAnalyticsDataSource({this.summary});

  /// The summary to return; a zero window when null.
  final AnalyticsSummary? summary;

  @override
  Future<AnalyticsSummary> fetch({
    required DateTime from,
    required DateTime to,
  }) async =>
      summary ??
      AnalyticsSummary(
        from: from,
        to: to,
        orderCount: 0,
        itemsSold: 0,
        avgOrderValue: 0,
        topDishes: const <DishSales>[],
        hourly: const <HourBucket>[],
      );
}

const RestaurantProfile testProfile = RestaurantProfile(
  name: 'Paradise Biryani',
  cuisines: <String>['Biryani', 'Hyderabadi', 'Kebabs'],
  priceForTwo: 500,
  isVeg: false,
  promoText: '50% OFF up to ₹100',
  etaMinutes: 32,
  imageUrl: '',
  rating: 4.4,
  ratingCount: 12800,
);

/// The restaurant row, in memory. `fetch` returns whatever was last saved (so a
/// test can save then read back), and the failure hook rehearses the database
/// refusing a bad value with its own sentence.
class FakeVendorRestaurantDataSource implements VendorRestaurantDataSource {
  FakeVendorRestaurantDataSource({RestaurantProfile initial = testProfile})
    : _profile = initial;

  RestaurantProfile _profile;

  /// Set to make the next save fail with this sentence.
  String? saveFailure;

  /// What the last successful save wrote — the customer app would read exactly
  /// this from the shared row.
  RestaurantProfile? lastSaved;

  @override
  Future<RestaurantProfile> fetch(String restaurantId) async => _profile;

  @override
  Future<void> save({
    required String name,
    required List<String> cuisines,
    required int priceForTwo,
    required bool isVeg,
    required String? promoText,
    required int etaMinutes,
    required String imageUrl,
  }) async {
    if (saveFailure != null) throw ProfileWriteFailure(saveFailure!);
    _profile = RestaurantProfile(
      name: name,
      cuisines: cuisines,
      priceForTwo: priceForTwo,
      isVeg: isVeg,
      promoText: promoText,
      etaMinutes: etaMinutes,
      imageUrl: imageUrl,
      rating: _profile.rating,
      ratingCount: _profile.ratingCount,
    );
    lastSaved = _profile;
  }
}

/// An uploader with neither a gallery nor a network: it hands back a fixed URL
/// (or null, for the user backing out), or throws to rehearse a failed upload.
class FakeImageUploader implements ImageUploader {
  FakeImageUploader({
    this.url = 'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/x.jpg',
    this.fail = false,
  });

  /// The URL a pick resolves to. Null models the user closing the picker.
  final String? url;
  final bool fail;
  int calls = 0;

  @override
  Future<String?> pickAndUpload() async {
    calls++;
    if (fail) throw const ImageUploadFailure();
    return url;
  }
}
