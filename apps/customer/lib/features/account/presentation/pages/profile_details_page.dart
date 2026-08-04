import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/core/images/image_uploader.dart';
import 'package:zopiqnow/features/account/presentation/widgets/profile_avatar.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// Edit the signed-in customer's profile.
///
/// Everything on this screen is stored against the Supabase user and survives a
/// reinstall; until 2026-07-30 it was an in-memory object and a one-second
/// `Future.delayed` pretending to be a network call.
class ProfileDetailsPage extends ConsumerStatefulWidget {
  const ProfileDetailsPage({super.key});

  @override
  ConsumerState<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends ConsumerState<ProfileDetailsPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _mobileFocus = FocusNode();

  late final TextEditingController _name;
  late final TextEditingController _mobile;
  late final TextEditingController _dob;

  DateTime? _dobDate;
  Gender? _gender;

  /// The uploaded URL, held here until Save. Uploading is immediate — the
  /// customer sees their photo the moment it lands — but it is not *theirs*
  /// until they save, so backing out of the screen leaves the old one.
  String? _pendingAvatarUrl;

  bool _saving = false;
  bool _uploading = false;

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime? date) => date == null
      ? ''
      : '${date.day.toString().padLeft(2, '0')} '
            '${_months[date.month - 1]} ${date.year}';

  AuthUser? get _user {
    final AuthState auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn ? auth.user : null;
  }

  @override
  void initState() {
    super.initState();
    final AuthUser? user = _user;
    _name = TextEditingController(text: user?.fullName ?? '');
    // Shown without the +91 the metadata carries: the field takes ten digits,
    // because that is what somebody knows their number as.
    _mobile = TextEditingController(text: _localDigits(user?.phone));
    _dobDate = user?.dateOfBirth;
    _dob = TextEditingController(text: _formatDate(_dobDate));
    _gender = user?.gender;
  }

  /// Strips a `+91` / `91` prefix and everything that is not a digit, leaving
  /// the ten-digit subscriber number. Anything else is handed back as-is rather
  /// than mangled — a number we did not write is not ours to reformat.
  static String _localDigits(String? e164) {
    if (e164 == null) return '';
    final String digits = e164.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    return digits.length == 10 ? digits : e164;
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _name.dispose();
    _mobile.dispose();
    _dob.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _changePhoto() async {
    final PhotoSource? source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.gallery),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final String? url = await ref
          .read(imageUploaderProvider)
          .pickAndUpload(source);
      if (!mounted) return;
      // Null means they closed the picker without choosing. Not a failure, and
      // not something to announce.
      if (url != null) setState(() => _pendingAvatarUrl = url);
    } on ImageUploadFailure catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final String typed = _mobile.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .saveProfile(
            fullName: _name.text.trim(),
            // Stored in E.164, which is the shape `place_order` passes on and
            // the rider's dialler needs. The field takes ten digits; the +91 is
            // added here, once, rather than being typed.
            phone: typed.isEmpty ? null : '+91$typed',
            avatarUrl: _pendingAvatarUrl,
            dateOfBirth: _dobDate,
            gender: _gender,
          );
      if (!mounted) return;
      _say('Profile saved');
      Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (mounted) _say(e.message);
    } on Object {
      if (mounted) _say('We couldn\'t save that. Check your connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    if (auth is! AuthSignedIn) {
      // Reachable only by a session that expired while the screen was open —
      // the route is behind the auth guard. Better than a form saving into
      // nothing.
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: const Center(child: Text('You\'re signed out.')),
      );
    }

    final AuthUser user = auth.user;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Edit profile'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: ZopiqSpacing.pagePadding,
                physics: const BouncingScrollPhysics(),
                children: <Widget>[
                  const SizedBox(height: ZopiqSpacing.md),
                  _AvatarEditor(
                    url: _pendingAvatarUrl ?? user.avatarUrl,
                    initial: user.initial,
                    busy: _uploading,
                    onTap: _uploading ? null : _changePhoto,
                  ),
                  const SizedBox(height: 32),

                  _SectionHeader('Personal details', t, zc),
                  _Card(
                    children: <Widget>[
                      _Field(
                        controller: _name,
                        label: 'Full name',
                        icon: Icons.badge_rounded,
                        focusNode: _nameFocus,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        validator: (String? v) {
                          final String name = (v ?? '').trim();
                          if (name.isEmpty) return 'Please enter your name';
                          if (name.length < 2) return 'That looks too short';
                          return null;
                        },
                      ),
                      _Divider(zc),
                      _Field(
                        // Read-only and not editable anywhere: the email *is*
                        // the identity this account signs in with. Changing it
                        // is an account migration, not a profile edit.
                        initialValue: user.email,
                        label: 'Email address',
                        icon: Icons.email_rounded,
                        readOnly: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: ZopiqSpacing.xl),
                  _SectionHeader('Contact & demographics', t, zc),
                  _Card(
                    children: <Widget>[
                      _Field(
                        controller: _mobile,
                        label: 'Mobile number',
                        helperText: 'Your rider calls this number',
                        icon: Icons.phone_rounded,
                        focusNode: _mobileFocus,
                        keyboardType: TextInputType.phone,
                        prefixText: '+91 ',
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (String? v) {
                          final String digits = (v ?? '').trim();
                          // Optional here, unlike at checkout, where
                          // `place_order` refuses an order without one. Somebody
                          // editing their name should not be forced to supply a
                          // number they have not been asked for yet.
                          if (digits.isEmpty) return null;
                          if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits)) {
                            return 'Enter a 10-digit Indian mobile number';
                          }
                          return null;
                        },
                      ),
                      _Divider(zc),
                      _Field(
                        controller: _dob,
                        label: 'Date of birth',
                        icon: Icons.calendar_today_rounded,
                        readOnly: true,
                        onTap: _pickDob,
                      ),
                      _Divider(zc),
                      _GenderField(
                        value: _gender,
                        onChanged: (Gender? g) => setState(() => _gender = g),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          _SaveBar(saving: _saving, onSave: _saving ? null : _save),
        ],
      ),
    );
  }

  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dobDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1920),
      // A birthday in the future is not a birthday. The picker refuses it,
      // which is better than a validator refusing it after the fact.
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dobDate = picked;
      _dob.text = _formatDate(picked);
    });
  }
}

/// The tappable avatar, with its camera badge — which now does something.
class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.url,
    required this.initial,
    required this.busy,
    required this.onTap,
  });

  final String? url;
  final String initial;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Center(
      child: Semantics(
        button: true,
        label: 'Change profile photo',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Stack(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: zc.primary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: ProfileAvatar(url: url, initial: initial, radius: 54),
              ),
              if (busy)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                    child: const Center(
                      child: ZopiqLoader(
                        size: 28,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: zc.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.t, this.zc);

  final String title;
  final TextTheme t;
  final ZopiqColors zc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: t.labelSmall?.copyWith(
          color: zc.textMuted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(color: context.zc.divider),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider(this.zc);

  final ZopiqColors zc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        thickness: 1,
        color: zc.divider.withValues(alpha: 0.5),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
        ZopiqSpacing.pageGutter,
        MediaQuery.paddingOf(context).bottom + ZopiqSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ZopiqButton(
        label: 'Save changes',
        isLoading: saving,
        onPressed: onSave,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.icon,
    this.controller,
    this.initialValue,
    this.readOnly = false,
    this.onTap,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.validator,
    this.prefixText,
    this.helperText,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final IconData icon;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final String? prefixText;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        // `readOnly` rather than `enabled: false`: a disabled field is greyed
        // out and unreadable, and these two — the email, and the date the picker
        // fills — are meant to be read. It also keeps the tap: the old build set
        // `enabled: onTap == null`, which made the date field's own `onTap` the
        // reason it could not receive one.
        readOnly: readOnly,
        onTap: onTap,
        focusNode: focusNode,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          prefixText: prefixText,
          labelStyle: TextStyle(color: zc.textMuted),
          prefixIcon: Icon(icon, color: zc.primary, size: 22),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _GenderField extends StatelessWidget {
  const _GenderField({required this.value, required this.onChanged});

  final Gender? value;
  final ValueChanged<Gender?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<Gender>(
        initialValue: value,
        icon: Icon(Icons.expand_more_rounded, color: zc.textMuted),
        decoration: InputDecoration(
          labelText: 'Gender',
          labelStyle: TextStyle(color: zc.textMuted),
          prefixIcon: Icon(
            Icons.person_outline_rounded,
            color: zc.primary,
            size: 22,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        items: Gender.values.map((Gender g) {
          return DropdownMenuItem<Gender>(
            value: g,
            child: Text(g.label, style: Theme.of(context).textTheme.bodyLarge),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
