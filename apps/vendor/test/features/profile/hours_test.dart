import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/opening_hours.dart';
import 'package:zopiq_vendor/features/profile/presentation/pages/hours_editor_page.dart';
import 'package:zopiq_vendor/features/profile/presentation/providers/hours_providers.dart';

import '../../support/fakes.dart';

Widget _app(FakeRestaurantHoursDataSource hours) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(FakeVendorOrderDataSource()),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    restaurantHoursDataSourceProvider.overrideWithValue(hours),
    clockProvider.overrideWith((Ref ref) => const Stream<DateTime>.empty()),
  ],
  child: const VendorApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Boots the app and taps through the More hub into the hours editor.
Future<void> _openHours(WidgetTester tester, FakeRestaurantHoursDataSource hours) async {
  await tester.pumpWidget(_app(hours));
  await tester.pumpAndSettle();
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Opening hours'));
  await tester.pumpAndSettle();
  expect(find.byType(HoursEditorPage), findsOneWidget);
}

void main() {
  testWidgets('the saved week seeds the editor — open days and closed ones', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    // Only Monday is open (9:00–23:00); the other six days have no row.
    final FakeRestaurantHoursDataSource hours = FakeRestaurantHoursDataSource(
      initial: const <OpeningHours>[
        OpeningHours(weekday: 1, opensMinutes: 540, closesMinutes: 1380),
      ],
    );

    await _openHours(tester, hours);

    expect(find.text('Monday'), findsOneWidget);
    // The six untouched days read as closed.
    expect(find.text('Closed'), findsNWidgets(6));
  });

  testWidgets('turning a day on and saving writes it with default hours', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeRestaurantHoursDataSource hours = FakeRestaurantHoursDataSource();

    await _openHours(tester, hours);

    // Every day starts closed. Switch Monday (the first row) on and save.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save hours'));
    await tester.pumpAndSettle();

    // The week the vendor set — Monday, 9 AM to 11 PM by default — is what the
    // database would receive.
    expect(hours.lastSaved, isNotNull);
    expect(hours.lastSaved!.length, 1);
    final OpeningHours monday = hours.lastSaved!.single;
    expect(monday.weekday, 1);
    expect(monday.opensMinutes, 540);
    expect(monday.closesMinutes, 1380);
  });
}
