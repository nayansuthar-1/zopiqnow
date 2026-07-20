import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/new_order_alarm.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

import '../../support/fakes.dart';

/// Instantiates the alarm and holds it alive (it auto-disposes without a
/// listener), then lets the stream drain so its adopt-first-batch runs.
Future<ProviderContainer> _armed(FakeVendorOrderDataSource orders) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      vendorProvider.overrideWithValue(testVendor),
      vendorOrderDataSourceProvider.overrideWithValue(orders),
    ],
  );
  addTearDown(container.dispose);
  container.listen<int>(newOrderAlarmProvider, (_, _) {});
  await _drain();
  return container;
}

/// Let the fake's `async*` stream deliver its queued emissions.
Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  // HapticFeedback speaks to a platform channel; the binding answers it with a
  // no-op under test, so the alarm can ring without a device.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the new-order alarm', () {
    test('adopts the backlog it wakes up to without ringing', () async {
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[
          order(id: 'A'),
          order(id: 'B'),
        ],
      );
      addTearDown(orders.dispose);

      final ProviderContainer container = await _armed(orders);

      expect(container.read(newOrderAlarmProvider), 0);
    });

    test('rings once for an order that arrives after it woke', () async {
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order(id: 'A')],
      );
      addTearDown(orders.dispose);

      final ProviderContainer container = await _armed(orders);
      expect(container.read(newOrderAlarmProvider), 0);

      orders.arrive(order(id: 'B'));
      await _drain();

      expect(container.read(newOrderAlarmProvider), 1);
    });

    test('does not ring when an order merely changes status', () async {
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order(id: 'A')],
      );
      addTearDown(orders.dispose);

      final ProviderContainer container = await _armed(orders);

      // A → accepted: the placed set shrinks, nothing new appears.
      await orders.setStatus(orderId: 'A', status: OrderStatus.accepted);
      await _drain();

      expect(container.read(newOrderAlarmProvider), 0);
    });

    test('an arrival that is not a fresh placed order stays silent', () async {
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order(id: 'A')],
      );
      addTearDown(orders.dispose);

      final ProviderContainer container = await _armed(orders);

      // Something lands on the stream that is not a new order to cook — say a
      // delivered one syncing in. The kitchen has nothing to answer.
      orders.arrive(order(id: 'B', status: OrderStatus.delivered));
      await _drain();

      expect(container.read(newOrderAlarmProvider), 0);
    });
  });
}
