import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Android's battery optimiser is allowed to kill this app's location
/// service, and the way to ask the rider to stop it (audit RID-001).
///
/// **Why this exists at all.** The foreground service in [RiderLocationReporter]
/// is what stock Android honours. Xiaomi, Oppo, Vivo, Realme and Samsung all
/// ship an additional killer on top of it that stock Android does not have, and
/// between them they are most of the Indian rider handset fleet. On those phones
/// a foreground service that is not on the exemption list is stopped anyway,
/// usually within minutes of the screen going off — which is exactly the state a
/// rider's phone is in while they ride.
///
/// **Why it opens a settings screen and not the grant dialog.** Android has a
/// one-tap version of this, `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. It
/// needs the `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission, and Play
/// restricts that permission to a short list of app categories that delivery
/// tracking is not on. Declaring it is a rejection waiting to happen. The list
/// screen needs no permission, is not restricted, and costs the rider two more
/// taps once a year.
///
/// An interface with a provider for the same reason as [Launcher]: a platform
/// channel has nothing on the other end in a test.
abstract interface class BatteryOptimisation {
  /// True when Android will leave our location service alone.
  ///
  /// Also true when we cannot tell — a missing channel, a non-Android host. The
  /// honest failure here is to say nothing rather than to nag a rider about a
  /// setting we could not read.
  Future<bool> isExempt();

  /// Opens the system's battery-optimisation list, where the rider finds Zopiq
  /// Rider and sets it to "Don't optimise". Returns false if no such screen
  /// exists on this device.
  Future<bool> openSettings();
}

class PlatformBatteryOptimisation implements BatteryOptimisation {
  const PlatformBatteryOptimisation();

  static const MethodChannel _channel = MethodChannel('zopiq/rider/battery');

  @override
  Future<bool> isExempt() async {
    try {
      return await _channel.invokeMethod<bool>('isExempt') ?? true;
    } on Object {
      return true;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on Object {
      return false;
    }
  }
}

final Provider<BatteryOptimisation> batteryOptimisationProvider =
    Provider<BatteryOptimisation>(
      (Ref ref) => const PlatformBatteryOptimisation(),
    );
