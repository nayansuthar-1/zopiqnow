import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/staff/domain/entities/staff_member.dart';
import 'package:zopiq_vendor/features/staff/presentation/pages/staff_page.dart';
import 'package:zopiq_vendor/features/staff/presentation/providers/staff_providers.dart';

import '../../support/fakes.dart';

Widget _app({required Vendor as, FakeStaffDataSource? staff}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: as),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(FakeVendorOrderDataSource()),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    notificationsDataSourceProvider.overrideWithValue(
      FakeNotificationsDataSource(),
    ),
    staffDataSourceProvider.overrideWithValue(staff ?? FakeStaffDataSource()),
    clockProvider.overrideWith((Ref ref) => const Stream<DateTime>.empty()),
  ],
  child: const VendorApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an owner reaches the team room and sees the roster', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeStaffDataSource staff = FakeStaffDataSource(
      initial: <StaffMember>[
        staffMember(email: 'kitchen@paradise.in', role: StaffRole.owner),
        staffMember(email: 'cook@paradise.in'),
      ],
    );
    await tester.pumpWidget(_app(as: testVendor, staff: staff));
    await _openMore(tester);

    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffPage), findsOneWidget);
    expect(find.text('cook@paradise.in'), findsOneWidget);
    // The owner's own row is labelled, and carries no menu to act on itself.
    expect(find.text('Owner · you'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });

  testWidgets('staff are offered neither Payments nor the team room', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(as: testStaffVendor));
    await _openMore(tester);

    expect(find.text('Payments'), findsNothing);
    expect(find.text('Team'), findsNothing);
    // The rest of the hub is untouched — this gates money and access, not work.
    expect(find.text('Restaurant profile'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('the home dashboard hides the week\'s earnings from staff', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(as: testStaffVendor));
    await tester.pumpAndSettle();

    // Today's revenue is the shift they are working, and stays.
    expect(find.text('Revenue today'), findsOneWidget);
    // The week's take, and the shortcut into Payments, do not.
    expect(find.text('Payments'), findsNothing);
  });

  testWidgets('the home dashboard shows the owner both', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(as: testVendor));
    await tester.pumpAndSettle();

    expect(find.text('Revenue today'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
  });

  testWidgets('adding a colleague puts them on the roster', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeStaffDataSource staff = FakeStaffDataSource(
      initial: <StaffMember>[
        staffMember(email: 'kitchen@paradise.in', role: StaffRole.owner),
      ],
    );
    await tester.pumpWidget(_app(as: testVendor, staff: staff));
    await _openMore(tester);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // A shape check happens before the round trip — the database is not asked
    // to adjudicate a typo.
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'newcook@paradise.in');
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    expect(staff.members.map((StaffMember m) => m.email), <String>[
      'kitchen@paradise.in',
      'newcook@paradise.in',
    ]);
    expect(find.text('newcook@paradise.in'), findsWidgets);
  });

  testWidgets('a refusal from the database is shown in its own words', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeStaffDataSource staff = FakeStaffDataSource(
      initial: <StaffMember>[
        staffMember(email: 'kitchen@paradise.in', role: StaffRole.owner),
      ],
    )..takenElsewhere.add('poached@rival.in');
    await tester.pumpWidget(_app(as: testVendor, staff: staff));
    await _openMore(tester);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'poached@rival.in');
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    expect(
      find.text('poached@rival.in is already on another restaurant\'s team.'),
      findsOneWidget,
    );
    expect(staff.members.length, 1);
  });

  testWidgets('removing someone takes them off the roster, after a confirm', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeStaffDataSource staff = FakeStaffDataSource(
      initial: <StaffMember>[
        staffMember(email: 'kitchen@paradise.in', role: StaffRole.owner),
        staffMember(email: 'cook@paradise.in'),
      ],
    );
    await tester.pumpWidget(_app(as: testVendor, staff: staff));
    await _openMore(tester);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    // Backing out of the confirm changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(staff.members.length, 2);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(staff.members.map((StaffMember m) => m.email), <String>[
      'kitchen@paradise.in',
    ]);
  });
}
