import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_status_views.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_list_skeleton.dart';

Widget _app(RestaurantMockDataSource dataSource) {
  return ProviderScope(
    overrides: <Override>[
      restaurantDataSourceProvider.overrideWithValue(dataSource),
    ],
    child: const ZopiqApp(),
  );
}

void main() {
  testWidgets('shows shimmer while loading, then the restaurant list',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(latency: Duration(milliseconds: 200))),
    );

    // First frame: the feed is loading → skeleton, no cards yet.
    expect(find.byType(RestaurantListSkeleton), findsOneWidget);
    expect(find.byType(RestaurantCard), findsNothing);

    // Let the mock future resolve (not pumpAndSettle: shimmer never settles).
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RestaurantListSkeleton), findsNothing);
    expect(find.byType(RestaurantCard), findsWidgets);
    expect(find.text('Paradise Biryani'), findsOneWidget);
  });

  testWidgets('shows a retryable error state when the feed fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(
        latency: Duration(milliseconds: 10),
        shouldFail: true,
      )),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeErrorView), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(RestaurantCard), findsNothing);
  });
}
