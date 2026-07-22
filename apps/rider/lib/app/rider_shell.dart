import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/auth/presentation/pages/profile_page.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/pages/earnings_page.dart';
import 'package:zopiq_rider/features/jobs/presentation/pages/home_page.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

/// Three tabs, which is two more than this app had.
///
/// A plain `IndexedStack` behind a `NavigationBar` rather than go_router's
/// `StatefulShellRoute`: nothing here is deep-linked, nothing is pushed on top,
/// and the router's whole job in this app is the signed-in/signed-out redirect
/// (see `router.dart`). A second routing mechanism to remember which of three
/// tabs is showing would be machinery bought for a problem nobody has.
///
/// `IndexedStack` and not a swapped child, so that the board's scroll position
/// survives a rider checking what they have made and coming back.
class RiderShell extends ConsumerStatefulWidget {
  const RiderShell({super.key});

  @override
  ConsumerState<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends ConsumerState<RiderShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // A rider with work in hand gets a badge on the tab they should be on, and
    // the count now that a run can hold more than one. It is the one thing
    // worth interrupting the other two screens about.
    final List<Job> run = ref.watch(activeJobsProvider);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[HomePage(), EarningsPage(), ProfilePage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: run.isEmpty
                ? const Icon(Icons.two_wheeler_outlined)
                : Badge(
                    backgroundColor: context.zc.primary,
                    // The count only once there is more than one — "1" on a
                    // badge is noise when the icon already means "you have a
                    // job".
                    label: run.length > 1 ? Text('${run.length}') : null,
                    child: const Icon(Icons.two_wheeler_rounded),
                  ),
            selectedIcon: const Icon(Icons.two_wheeler_rounded),
            // Always "Jobs". The label tracking the state would only repeat the
            // app bar directly above it, in smaller type.
            label: 'Jobs',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Earnings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
