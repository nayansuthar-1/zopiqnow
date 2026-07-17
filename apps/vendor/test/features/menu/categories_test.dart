import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/core/images/image_uploader.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/pages/manage_categories_page.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';

import '../../support/fakes.dart';

Widget _app(FakeVendorMenuDataSource menu) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorMenuDataSourceProvider.overrideWithValue(menu),
    vendorOrderDataSourceProvider.overrideWithValue(FakeVendorOrderDataSource()),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    imageUploaderProvider.overrideWithValue(FakeImageUploader()),
    clockProvider.overrideWith((Ref ref) => const Stream<DateTime>.empty()),
  ],
  child: const VendorApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Boots the app, taps through to the menu, then into its section manager.
Future<void> _openSections(WidgetTester tester, FakeVendorMenuDataSource menu) async {
  await tester.pumpWidget(_app(menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Sections'));
  await tester.pumpAndSettle();
  expect(find.byType(ManageCategoriesPage), findsOneWidget);
}

FakeVendorMenuDataSource _threeSections() => FakeVendorMenuDataSource(
  dishes: <VendorDish>[
    dish(id: 'd1', name: 'Chicken Biryani', category: 'Biryanis'),
    dish(id: 'd2', name: 'Paneer Tikka', category: 'Starters'),
    dish(id: 'd3', name: 'Gulab Jamun', category: 'Desserts'),
  ],
);

void main() {
  group('the sections screen', () {
    testWidgets('lists each section with its dish count', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      await _openSections(tester, _threeSections());

      expect(find.text('Biryanis'), findsOneWidget);
      expect(find.text('Starters'), findsOneWidget);
      expect(find.text('Desserts'), findsOneWidget);
      expect(find.text('1 dish'), findsNWidgets(3));
    });

    testWidgets('turning a section off takes it off the menu', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorMenuDataSource menu = _threeSections();
      await _openSections(tester, menu);

      // The switch on the Biryanis tile — the first one.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.text('Off the menu'), findsOneWidget);
      // The store recorded it, which is what hides it from every customer.
      expect(menu.categoryAvailable('Biryanis'), isFalse);
    });

    testWidgets('a refused toggle puts the switch back', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorMenuDataSource menu = _threeSections()
        ..writeFailure = 'Couldn\'t reach the kitchen.';
      await _openSections(tester, menu);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Optimism, then a refusal, then the truth back on the screen.
      expect(find.text('Off the menu'), findsNothing);
      expect(find.text('Couldn\'t reach the kitchen.'), findsOneWidget);
      expect(menu.categoryAvailable('Biryanis'), isTrue);
    });

    testWidgets('renaming a section renames every dish under it', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorMenuDataSource menu = _threeSections();
      await _openSections(tester, menu);

      // The edit icon on the first tile.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Dum Biryanis');
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Dum Biryanis'), findsOneWidget);
      // The category moved on the dish itself — the customer groups by it.
      expect(
        menu.dishes.firstWhere((VendorDish d) => d.id == 'd1').category,
        'Dum Biryanis',
      );
    });

    testWidgets('a section cannot be renamed onto another', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorMenuDataSource menu = _threeSections();
      await _openSections(tester, menu);

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      // Rename Biryanis → Starters, which already exists. Merging two sections
      // whose ranks differ is a mess we refuse before it happens.
      await tester.enterText(find.byType(TextField), 'Starters');
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(
        find.text('There is already a section with that name.'),
        findsOneWidget,
      );
      // Nothing was renamed.
      expect(
        menu.dishes.firstWhere((VendorDish d) => d.id == 'd1').category,
        'Biryanis',
      );
    });

    testWidgets('dragging a section reorders the menu', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorMenuDataSource menu = _threeSections();
      await _openSections(tester, menu);

      // Drag the first section's handle down past the second tile, so Biryanis
      // lands below Starters.
      final Finder handle = find.byIcon(Icons.drag_indicator_rounded).first;
      final TestGesture drag = await tester.startGesture(
        tester.getCenter(handle),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await drag.moveBy(const Offset(0, 140));
      await tester.pump(const Duration(milliseconds: 200));
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      // The store recorded the new order: Biryanis is no longer first.
      final List<VendorMenuSection> sections = await menu.fetchMenu('r1');
      expect(sections.first.title, isNot('Biryanis'));
      expect(
        sections.map((VendorMenuSection s) => s.title),
        containsAll(<String>['Biryanis', 'Starters', 'Desserts']),
      );
    });
  });
}
