import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/profile/domain/entities/restaurant_profile.dart';
import 'package:zopiq_vendor/features/profile/presentation/providers/profile_providers.dart';

/// The form behind "Edit profile".
///
/// Prefilled from the loaded profile, saved through the one RPC that can reach
/// these columns. It is a full page, not a sheet: six fields including a
/// free-text cuisines list is more than a sheet should hold, and this is a slow,
/// deliberate edit, not a mid-rush toggle.
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _cuisines;
  late final TextEditingController _price;
  late final TextEditingController _promo;
  late final TextEditingController _eta;
  bool _isVeg = false;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _cuisines = TextEditingController();
    _price = TextEditingController();
    _promo = TextEditingController();
    _eta = TextEditingController();
  }

  /// Fill the fields once, from the already-loaded profile. Done here rather than
  /// in `initState` because the profile is an `AsyncValue` the build reads; doing
  /// it on every build would fight the user's typing.
  void _prefill(RestaurantProfile p) {
    if (_prefilled) return;
    _prefilled = true;
    _name.text = p.name;
    _cuisines.text = p.cuisines.join(', ');
    _price.text = p.priceForTwo.toString();
    _promo.text = p.promoText ?? '';
    _eta.text = p.etaMinutes.toString();
    _isVeg = p.isVeg;
  }

  @override
  void dispose() {
    _name.dispose();
    _cuisines.dispose();
    _price.dispose();
    _promo.dispose();
    _eta.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Split on commas, trim, drop the empties a trailing comma leaves behind.
    final List<String> cuisines = _cuisines.text
        .split(',')
        .map((String c) => c.trim())
        .where((String c) => c.isNotEmpty)
        .toList();
    final String promo = _promo.text.trim();

    final String? error = await ref
        .read(profileControllerProvider.notifier)
        .save(
          name: _name.text.trim(),
          cuisines: cuisines,
          priceForTwo: int.parse(_price.text.trim()),
          isVeg: _isVeg,
          promoText: promo.isEmpty ? null : promo,
          etaMinutes: int.parse(_eta.text.trim()),
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile updated')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<RestaurantProfile> profile = ref.watch(
      restaurantProfileProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(ZopiqSpacing.xl),
            child: Text('We couldn\'t load your profile to edit.'),
          ),
        ),
        data: (RestaurantProfile p) {
          _prefill(p);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
              children: <Widget>[
                _TextField(
                  controller: _name,
                  label: 'Restaurant name',
                  validator: (String? v) => (v == null || v.trim().isEmpty)
                      ? 'Your restaurant needs a name.'
                      : null,
                ),
                _TextField(
                  controller: _cuisines,
                  label: 'Cuisines (comma-separated)',
                  hint: 'Biryani, Hyderabadi, Kebabs',
                ),
                _TextField(
                  controller: _price,
                  label: 'Cost for two (₹)',
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: _positiveIntValidator,
                ),
                _TextField(
                  controller: _eta,
                  label: 'Prep time (minutes)',
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: _positiveIntValidator,
                ),
                _TextField(
                  controller: _promo,
                  label: 'Offer line (optional)',
                  hint: '50% OFF up to ₹100',
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pure veg restaurant'),
                  value: _isVeg,
                  activeTrackColor: context.zc.veg,
                  onChanged: (bool v) => setState(() => _isVeg = v),
                ),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Save changes',
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _positiveIntValidator(String? v) {
    final int? n = int.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return 'Enter a number greater than zero.';
    return null;
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.lg),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
