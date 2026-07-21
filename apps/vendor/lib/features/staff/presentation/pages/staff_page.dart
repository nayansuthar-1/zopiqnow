import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/staff/domain/entities/staff_member.dart';
import 'package:zopiq_vendor/features/staff/presentation/providers/staff_providers.dart';

/// Who can sign in to this kitchen, and as what.
///
/// The owner's screen, and only the owner's — the More hub does not offer the
/// row to anyone else, and every RPC behind it refuses a non-owner anyway (0024).
/// Two things are worth knowing while reading it:
///
/// The list is *not* optimistic, unlike the sections screen. Access is not a
/// switch to be flipped and put back — showing someone as removed a beat before
/// the database agrees is the one lie this screen must not tell — so each write
/// waits, then refreshes.
///
/// And the owner's own row is inert: no menu, no role chip to change. The
/// database refuses a self-demote and a self-removal (that one rule is what
/// guarantees a restaurant can never be left with no owner at all), so offering
/// the buttons would only be a way to be told no.
class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});

  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  /// Blocks the whole screen while a write is in flight. One flag and not a
  /// per-row set, because these are rare, deliberate actions — unlike the order
  /// queue, where two tickets are genuinely moved at once.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<StaffMember>> roster = ref.watch(staffProvider);
    final String? me = ref.watch(vendorProvider)?.email.toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add'),
      ),
      body: roster.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => _ErrorBody(
          onRetry: () => ref.invalidate(staffProvider),
        ),
        data: (List<StaffMember> members) => AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.only(
              top: ZopiqSpacing.sm,
              // Clear of the FAB, so the last row is never trapped under it.
              bottom: ZopiqSpacing.xxl * 2,
            ),
            children: <Widget>[
              const _Explainer(),
              for (final StaffMember m in members)
                _MemberTile(
                  member: m,
                  isMe: m.email.toLowerCase() == me,
                  onChangeRole: () => _changeRole(m),
                  onRemove: () => _remove(m),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final _NewMember? added = await showDialog<_NewMember>(
      context: context,
      builder: (_) => const _AddDialog(),
    );
    if (added == null) return;

    await _run(
      () => ref
          .read(staffControllerProvider.notifier)
          .add(email: added.email, role: added.role),
      '${added.email} can now sign in.',
    );
  }

  Future<void> _changeRole(StaffMember member) async {
    // The only move available: two roles, so "change" is unambiguous and a
    // picker would be a menu of one.
    final StaffRole to = member.role.isOwner ? StaffRole.staff : StaffRole.owner;
    final bool ok = await _confirm(
      title: to.isOwner ? 'Make an owner?' : 'Remove owner access?',
      body: to.isOwner
          ? '${member.email} will also be able to see earnings and settlements, '
                'and manage the team.'
          : '${member.email} will keep working here, but will no longer see '
                'earnings and settlements or manage the team.',
      confirm: to.isOwner ? 'Make owner' : 'Change',
    );
    if (!ok) return;

    await _run(
      () => ref
          .read(staffControllerProvider.notifier)
          .setRole(email: member.email, role: to),
      to.isOwner
          ? '${member.email} is now an owner.'
          : '${member.email} is now staff.',
    );
  }

  Future<void> _remove(StaffMember member) async {
    final bool ok = await _confirm(
      title: 'Remove from the team?',
      body: '${member.email} will be signed out of this restaurant and won\'t '
          'be able to sign back in. Their past orders are unaffected.',
      confirm: 'Remove',
      destructive: true,
    );
    if (!ok) return;

    await _run(
      () => ref.read(staffControllerProvider.notifier).remove(member.email),
      '${member.email} was removed.',
    );
  }

  /// Run a write with the screen blocked, then say what happened either way.
  Future<void> _run(Future<String?> Function() write, String success) async {
    setState(() => _busy = true);
    final String? failure = await write();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(failure ?? success);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirm,
    bool destructive = false,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: dialogContext.zc.nonVeg,
                  )
                : null,
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// What the two roles mean, said once at the top rather than repeated on every
/// row. An owner adding their first colleague has no other way to find out.
class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
      ),
      child: Text(
        'Everyone here can take orders and manage the menu. Only owners see '
        'earnings and settlements, or change who is on the team.',
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isMe,
    required this.onChangeRole,
    required this.onRemove,
  });

  final StaffMember member;

  /// The signed-in owner's own row — shown, but with nothing to press.
  final bool isMe;

  final VoidCallback onChangeRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: zc.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                member.role.isOwner
                    ? Icons.workspace_premium_rounded
                    : Icons.person_rounded,
                color: zc.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    member.email,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: zc.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isMe
                        ? '${member.role.isOwner ? 'Owner' : 'Staff'} · you'
                        : member.role.isOwner
                        ? 'Owner'
                        : 'Staff',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            if (!isMe)
              PopupMenuButton<_MemberAction>(
                icon: Icon(Icons.more_vert_rounded, color: zc.textMuted),
                onSelected: (_MemberAction a) => switch (a) {
                  _MemberAction.changeRole => onChangeRole(),
                  _MemberAction.remove => onRemove(),
                },
                itemBuilder: (_) => <PopupMenuEntry<_MemberAction>>[
                  PopupMenuItem<_MemberAction>(
                    value: _MemberAction.changeRole,
                    child: Text(
                      member.role.isOwner ? 'Make staff' : 'Make owner',
                    ),
                  ),
                  const PopupMenuItem<_MemberAction>(
                    value: _MemberAction.remove,
                    child: Text('Remove'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _MemberAction { changeRole, remove }

/// What [_AddDialog] hands back.
class _NewMember {
  const _NewMember({required this.email, required this.role});

  final String email;
  final StaffRole role;
}

class _AddDialog extends StatefulWidget {
  const _AddDialog();

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final TextEditingController _controller = TextEditingController();
  StaffRole _role = StaffRole.staff;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String email = _controller.text.trim().toLowerCase();
    // A shape check only. Whether the address is free, or already on another
    // restaurant's team, is the database's to answer — asking here would mean
    // an endpoint that reports which emails are taken, which is the enumeration
    // hole 0009 was written to close.
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    Navigator.pop(context, _NewMember(email: email, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to the team'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Email address',
              // They sign in with a code mailed to this address, so it has to be
              // one they actually read.
              helperText: 'They sign in with a code sent here',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          SegmentedButton<StaffRole>(
            segments: const <ButtonSegment<StaffRole>>[
              ButtonSegment<StaffRole>(
                value: StaffRole.staff,
                label: Text('Staff'),
              ),
              ButtonSegment<StaffRole>(
                value: StaffRole.owner,
                label: Text('Owner'),
              ),
            ],
            selected: <StaffRole>{_role},
            onSelectionChanged: (Set<StaffRole> s) =>
                setState(() => _role = s.first),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('We couldn\'t load your team', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'Check the internet and try again.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(label: 'Retry', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
