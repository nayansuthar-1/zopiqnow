import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/account/presentation/providers/customer_profile_provider.dart';

class ProfileDetailsPage extends ConsumerStatefulWidget {
  const ProfileDetailsPage({super.key});

  @override
  ConsumerState<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends ConsumerState<ProfileDetailsPage> {
  late final TextEditingController _name;
  late final TextEditingController _mobile;
  late final TextEditingController _dob;
  DateTime? _dobDate;
  Gender? _selectedGender;
  bool _saving = false;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _mobileFocus = FocusNode();

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    const List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  @override
  void initState() {
    super.initState();
    final CustomerProfile profile = ref.read(customerProfileProvider);
    _name = TextEditingController(text: profile.name);
    _mobile = TextEditingController(text: profile.mobile);
    _dob = TextEditingController(text: _formatDate(profile.dob));
    _dobDate = profile.dob;
    _selectedGender = profile.gender;
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted) return;
    
    ref.read(customerProfileProvider.notifier).updateProfile(
      name: _name.text,
      mobile: _mobile.text,
      dob: _dobDate,
      gender: _selectedGender,
    );
    
    setState(() => _saving = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final String email = auth is AuthSignedIn ? auth.user.email : 'Not signed in';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Form(
              child: ListView(
                padding: ZopiqSpacing.pagePadding,
                physics: const BouncingScrollPhysics(),
                children: <Widget>[
                  const SizedBox(height: ZopiqSpacing.md),
                  _buildAvatarSection(zc),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Personal Details', t, zc),
                  _buildCard(
                    context: context,
                    children: <Widget>[
                      _PremiumTextField(
                        controller: _name,
                        label: 'Full Name',
                        icon: Icons.badge_rounded,
                        focusNode: _nameFocus,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                      ),
                      _buildDivider(zc),
                      _PremiumTextField(
                        controller: TextEditingController(text: email),
                        label: 'Email Address',
                        icon: Icons.email_rounded,
                        readOnly: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: ZopiqSpacing.xl),
                  _buildSectionHeader('Contact & Demographics', t, zc),
                  _buildCard(
                    context: context,
                    children: <Widget>[
                      _PremiumTextField(
                        controller: _mobile,
                        label: 'Mobile Number',
                        icon: Icons.phone_rounded,
                        focusNode: _mobileFocus,
                        keyboardType: TextInputType.phone,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        ],
                      ),
                      _buildDivider(zc),
                      _PremiumTextField(
                        controller: _dob,
                        label: 'Date of Birth',
                        icon: Icons.calendar_today_rounded,
                        readOnly: true,
                        onTap: () async {
                          FocusScope.of(context).unfocus();
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _dobDate ?? DateTime(1990, 1, 1),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                            builder: (BuildContext context, Widget? child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: zc.primary,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            _dobDate = picked;
                            _dob.text = _formatDate(picked);
                          }
                        },
                      ),
                      _buildDivider(zc),
                      _PremiumDropdown(
                        value: _selectedGender,
                        label: 'Gender',
                        icon: Icons.person_outline_rounded,
                        items: Gender.values,
                        onChanged: (Gender? val) {
                          setState(() {
                            _selectedGender = val;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          _buildStickyBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildAvatarSection(ZopiqColors zc) {
    return Center(
      child: Stack(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: zc.primary.withValues(alpha: 0.2), width: 2),
            ),
            child: CircleAvatar(
              radius: 54,
              backgroundColor: zc.primary.withValues(alpha: 0.1),
              child: Icon(Icons.person_rounded, color: zc.primary, size: 60),
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
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, TextTheme t, ZopiqColors zc) {
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

  Widget _buildCard({required BuildContext context, required List<Widget> children}) {
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
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDivider(ZopiqColors zc) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, thickness: 1, color: zc.divider.withValues(alpha: 0.5)),
    );
  }

  Widget _buildStickyBottomBar(BuildContext context) {
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
        label: 'Save Changes',
        isLoading: _saving,
        onPressed: _saving ? null : _save,
      ),
    );
  }
}

class _PremiumTextField extends StatelessWidget {
  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.readOnly = false,
    this.onTap,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextFormField(
          controller: controller,
          readOnly: readOnly,
          enabled: onTap == null, // disable raw input if onTap is provided
          focusNode: focusNode,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: zc.textMuted),
            prefixIcon: Icon(icon, color: zc.primary, size: 22),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _PremiumDropdown extends StatelessWidget {
  const _PremiumDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final Gender? value;
  final String label;
  final IconData icon;
  final List<Gender> items;
  final ValueChanged<Gender?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<Gender>(
        value: value,
        icon: Icon(Icons.expand_more_rounded, color: zc.textMuted),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: zc.textMuted),
          prefixIcon: Icon(icon, color: zc.primary, size: 22),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        items: items.map((Gender g) {
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
