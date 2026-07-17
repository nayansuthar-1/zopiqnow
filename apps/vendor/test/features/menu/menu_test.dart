import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/core/images/image_uploader.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';

import '../../support/fakes.dart';

Widget _app({
  required FakeVendorMenuDataSource menu,
  FakeImageUploader? uploader,
}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorMenuDataSourceProvider.overrideWithValue(menu),
    // The queue is the app's first screen; it needs a data source even though
    // this suite is about the menu one tap away from it.
    vendorOrderDataSourceProvider.overrideWithValue(
      FakeVendorOrderDataSource(),
    ),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
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

/// Boots the app on the queue and taps through to the menu screen.
Future<void> _openMenu(WidgetTester tester) async {
  await tester.pumpWidget(_app(menu: tester.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  expect(find.byType(MenuPage), findsOneWidget);
}

/// Stashes the menu source for [_openMenu], so each test reads like a story.
extension on WidgetTester {
  static final Expando<FakeVendorMenuDataSource> _menus =
      Expando<FakeVendorMenuDataSource>();

  FakeVendorMenuDataSource get menu => _menus[this]!;
  set menu(FakeVendorMenuDataSource value) => _menus[this] = value;
}

void main() {
  group('the menu screen', () {
    testWidgets('lists dishes under their sections, with prices', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource(
        dishes: <VendorDish>[
          dish(id: 'd1', name: 'Chicken Biryani', price: 320),
          dish(
            id: 'd2',
            name: 'Gulab Jamun',
            price: 90,
            isVeg: true,
            category: 'Desserts',
          ),
        ],
      );

      await _openMenu(tester);

      expect(find.text('BIRYANIS'), findsOneWidget);
      expect(find.text('DESSERTS'), findsOneWidget);
      expect(find.text('Chicken Biryani'), findsOneWidget);
      expect(find.text('₹320'), findsOneWidget);
      expect(find.text('Gulab Jamun'), findsOneWidget);
    });

    testWidgets('marking a dish sold out flips the switch and saves it', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource(
        dishes: <VendorDish>[dish(id: 'd1', name: 'Chicken Biryani')],
      );

      await _openMenu(tester);
      expect(find.text('Available'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Sold out'), findsOneWidget);
      // The write reached the store, not just the switch.
      expect(tester.menu.dishes.single.isAvailable, isFalse);
    });

    testWidgets('a refused availability change puts the switch back', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource(
        dishes: <VendorDish>[dish(id: 'd1', name: 'Chicken Biryani')],
      )..writeFailure = 'Couldn\'t reach the kitchen.';

      await _openMenu(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // The switch flipped optimistically, the write was refused, so it went
      // back — a screen that says "Sold out" over a dish that is still selling
      // is the one lie this screen must not tell.
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Sold out'), findsNothing);
      expect(find.text('Couldn\'t reach the kitchen.'), findsOneWidget);
    });

    testWidgets('adding a dish appends it to the menu', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource(
        dishes: <VendorDish>[dish(id: 'd1', name: 'Chicken Biryani')],
      );

      await _openMenu(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Paneer Tikka'); // name
      await tester.enterText(fields.at(2), '260'); // price
      await tester.enterText(fields.at(3), 'Starters'); // section
      await tester.tap(find.widgetWithText(FilledButton, 'Add dish'));
      await tester.pumpAndSettle();

      // The sheet closed and the new dish is on the menu, under its section.
      expect(find.byType(MenuPage), findsOneWidget);
      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('STARTERS'), findsOneWidget);
      expect(tester.menu.dishes.length, 2);
    });

    testWidgets('a photo added to a dish is uploaded and saved with it', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource();
      final FakeImageUploader uploader = FakeImageUploader(
        url: 'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/d.jpg',
      );

      await tester.pumpWidget(_app(menu: tester.menu, uploader: uploader));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap the photo well — the upload runs and the well shows the result.
      await tester.tap(find.text('Add a photo'));
      await tester.pumpAndSettle();
      expect(uploader.calls, 1);

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Paneer Tikka');
      await tester.enterText(fields.at(2), '260');
      await tester.enterText(fields.at(3), 'Starters');
      await tester.tap(find.widgetWithText(FilledButton, 'Add dish'));
      await tester.pumpAndSettle();

      // The dish saved with the URL the upload returned — which is exactly what
      // the customer menu will render.
      final VendorDish saved = tester.menu.dishes.firstWhere(
        (VendorDish d) => d.name == 'Paneer Tikka',
      );
      expect(
        saved.imageUrl,
        'https://res.cloudinary.com/mqppsahn/image/upload/zopiqnow/d.jpg',
      );
    });

    testWidgets('a new dish with no price is refused, not saved', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource();

      await _openMenu(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Paneer Tikka');
      await tester.tap(find.widgetWithText(FilledButton, 'Add dish'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a price in rupees.'), findsOneWidget);
      expect(tester.menu.dishes, isEmpty);
    });

    testWidgets('a dish on a past order cannot be deleted, and is told so', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      tester.menu = FakeVendorMenuDataSource(
        dishes: <VendorDish>[dish(id: 'd1', name: 'Chicken Biryani')],
      )..deleteInUse = true;

      await _openMenu(tester);
      await tester.tap(find.text('Chicken Biryani'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove from menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove')); // confirm the dialog
      await tester.pumpAndSettle();

      // The FK protected the receipt; the vendor is pointed at the switch
      // instead, not shown a crash.
      expect(find.textContaining('on past orders'), findsOneWidget);
      expect(tester.menu.dishes.length, 1);
    });
  });
}
