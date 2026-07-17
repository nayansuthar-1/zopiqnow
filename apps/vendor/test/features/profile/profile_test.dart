import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/core/images/image_uploader.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/profile/presentation/pages/profile_edit_page.dart';
import 'package:zopiq_vendor/features/profile/presentation/pages/profile_page.dart';
import 'package:zopiq_vendor/features/profile/presentation/providers/profile_providers.dart';

import '../../support/fakes.dart';

Widget _app({
  required FakeVendorRestaurantDataSource restaurant,
  FakeImageUploader? uploader,
}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(
      FakeVendorOrderDataSource(),
    ),
    vendorRestaurantDataSourceProvider.overrideWithValue(restaurant),
    imageUploaderProvider.overrideWithValue(uploader ?? FakeImageUploader()),
    clockProvider.overrideWith((Ref ref) => const Stream<DateTime>.empty()),
  ],
  child: const VendorApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the profile shows what customers see', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(restaurant: FakeVendorRestaurantDataSource()),
    );
    await tester.pumpAndSettle();

    await _openProfile(tester);

    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('Paradise Biryani'), findsOneWidget);
    expect(find.text('₹500'), findsOneWidget);
    expect(find.text('32 min'), findsOneWidget);
    // A cuisine chip, and the offer line.
    expect(find.text('Biryani'), findsOneWidget);
    expect(find.text('50% OFF up to ₹100'), findsOneWidget);
  });

  testWidgets('adding a cover photo uploads it and saves the URL', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorRestaurantDataSource restaurant =
        FakeVendorRestaurantDataSource();
    final FakeImageUploader uploader = FakeImageUploader(
      url: 'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/c.jpg',
    );
    await tester.pumpWidget(_app(restaurant: restaurant, uploader: uploader));
    await tester.pumpAndSettle();

    await _openProfile(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a photo'));
    await tester.pumpAndSettle();
    expect(uploader.calls, 1);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // The URL the upload returned is what got saved — and what the customer feed
    // and menu header will now show for this restaurant.
    expect(
      restaurant.lastSaved?.imageUrl,
      'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/c.jpg',
    );
  });

  testWidgets('editing the name saves it and the queue header follows', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorRestaurantDataSource restaurant =
        FakeVendorRestaurantDataSource();
    await tester.pumpWidget(_app(restaurant: restaurant));
    await tester.pumpAndSettle();

    await _openProfile(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Restaurant name'),
      'Paradise Biryani (Jubilee Hills)',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // The write carried the new name — this is exactly what the customer app
    // would read from the shared row.
    expect(restaurant.lastSaved?.name, 'Paradise Biryani (Jubilee Hills)');

    // Back on the profile, showing the new name.
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('Paradise Biryani (Jubilee Hills)'), findsWidgets);

    // And the queue's header followed, without a re-login.
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Paradise Biryani (Jubilee Hills)'), findsOneWidget);
  });

  testWidgets('a save the database refuses is shown, and stays on the form', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorRestaurantDataSource restaurant =
        FakeVendorRestaurantDataSource()
          ..saveFailure = 'The cost for two has to be more than zero.';
    await tester.pumpWidget(_app(restaurant: restaurant));
    await tester.pumpAndSettle();

    await _openProfile(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('The cost for two has to be more than zero.'),
      findsOneWidget,
    );
    // Did not navigate away.
    expect(find.byType(ProfileEditPage), findsOneWidget);
  });
}
