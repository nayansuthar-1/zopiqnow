import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Gender { male, female, other }

extension GenderExt on Gender {
  String get label {
    switch (this) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
    }
  }
}

class CustomerProfile {
  const CustomerProfile({
    required this.name,
    required this.mobile,
    this.dob,
    this.gender,
  });

  final String name;
  final String mobile;
  final DateTime? dob;
  final Gender? gender;

  CustomerProfile copyWith({
    String? name,
    String? mobile,
    DateTime? dob,
    Gender? gender,
  }) {
    return CustomerProfile(
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
    );
  }
}

class CustomerProfileNotifier extends StateNotifier<CustomerProfile> {
  CustomerProfileNotifier()
      : super(CustomerProfile(
          name: 'Zopiq user',
          mobile: '+91 9876543210',
          dob: DateTime(1990, 1, 1),
          gender: Gender.male,
        ));

  void updateProfile({
    String? name,
    String? mobile,
    DateTime? dob,
    Gender? gender,
  }) {
    state = state.copyWith(
      name: name,
      mobile: mobile,
      dob: dob,
      gender: gender,
    );
  }
}

final customerProfileProvider = StateNotifierProvider<CustomerProfileNotifier, CustomerProfile>((ref) {
  return CustomerProfileNotifier();
});
