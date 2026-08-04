import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/staff/domain/entities/staff_member.dart';
import 'package:zopiq_vendor/features/staff/presentation/providers/staff_providers.dart';

/// Who can sign in to this kitchen team.
class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});

  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<StaffMember>> roster = ref.watch(staffProvider);
    final String? me = ref.watch(vendorProvider)?.email.toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: context.zc.primary,
        foregroundColor: Colors.white,
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add'),
      ),
      body: roster.when(
        loading: () => const Center(child: ZopiqLoader()),
        error: (Object _, StackTrace _) => _ErrorBody(
          onRetry: () => ref.invalidate(staffProvider),
        ),
        data: (List<StaffMember> members) => AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.only(
              top: ZopiqSpacing.sm,
              bottom: ZopiqSpacing.xxl * 2,
            ),
            children: <Widget>[
              const VendorFadeSlide(child: _Explainer()),
              for (int i = 0; i < members.length; i++)
                VendorFadeSlide(
                  delay: Duration(milliseconds: 50 + i * 50),
                  child: _MemberTile(
                    member: members[i],
                    isMe: members[i].email.toLowerCase() == me,
                    onChangeRole: () => _changeRole(members[i]),
                    onRemove: () => _remove(members[i]),
                  ),
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
    final StaffRole to = member.role.isOwner ? StaffRole.staff : StaffRole.owner;
    final bool ok = await _confirm(
      title: to.isOwner ? 'Make an owner?' : 'Remove owner access?',
      body: to.isOwner
          ? '${member.email} will be able to see revenue earnings, settlements, and manage staff access.'
          : '${member.email} will keep working here, but will no longer see earnings or manage team members.',
      confirm: to.isOwner ? 'Make owner' : 'Change',
    );
    if (!ok) return;

    await _run(
      () => ref
          .read(staffControllerProvider.notifier)
          .setRole(email: member.email, role: to),
      to.isOwner
          ? '${member.email} is now an Owner.'
          : '${member.email} is now Staff.',
    );
  }

  Future<void> _remove(StaffMember member) async {
    final bool ok = await _confirm(
      title: 'Remove from the team?',
      body: '${member.email} will be signed out of this store and won\'t be able to log back in.',
      confirm: 'Remove',
      destructive: true,
    );
    if (!ok) return;

    await _run(
      () => ref.read(staffControllerProvider.notifier).remove(member.email),
      '${member.email} was removed from team.',
    );
  }

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
      child: Container(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        decoration: BoxDecoration(
          color: zc.primary.withValues(alpha: 0.06),
          borderRadius: ZopiqRadii.rMd,
          border: Border.all(color: zc.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: <Widget>[
            VendorSvgIcon(
              type: VendorSvgType.staffRoster,
              size: 20,
              color: zc.primary,
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Text(
        'Everyone here can take orders and manage the menu. Only owners see '
        'earnings and settlements, or change who is on the team.',
                style: t.bodySmall?.copyWith(color: zc.textStrong),
              ),
            ),
          ],
        ),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: zc.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: VendorSvgIcon(
                  type: VendorSvgType.staffRoster,
                  size: 22,
                  color: zc.primary,
                ),
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
                      fontWeight: FontWeight.bold,
                      color: zc.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: member.role.isOwner
                              ? zc.primary.withValues(alpha: 0.12)
                              : zc.divider.withValues(alpha: 0.5),
                          borderRadius: ZopiqRadii.rPill,
                        ),
                        child: Text(
                          isMe
                              ? '${member.role.isOwner ? 'Owner' : 'Staff'} · you'
                              : member.role.isOwner
                              ? 'Owner'
                              : 'Staff',
                          style: t.labelSmall?.copyWith(
                            color: member.role.isOwner ? zc.primary : zc.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
              labelText: 'Staff Email Address',
              helperText: 'A sign-in code will be sent to this email',
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
            VendorSvgIcon(
              type: VendorSvgType.storeClosed,
              size: 56,
              color: zc.textMuted,
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('We couldn\'t load your team', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
