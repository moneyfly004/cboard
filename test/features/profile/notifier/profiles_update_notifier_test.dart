import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';

void main() {
  group('ForegroundProfilesUpdateNotifier.shouldUpdateProfile', () {
    final now = DateTime(2026, 6, 22, 12);

    RemoteProfileEntity profile({
      Duration age = const Duration(hours: 24),
      ProfileOptions? options,
      UserOverride? userOverride,
    }) {
      return RemoteProfileEntity(
        id: 'profile',
        active: true,
        name: 'Profile',
        url: 'https://example.com/sub',
        lastUpdate: now.subtract(age),
        options: options,
        userOverride: userOverride,
      );
    }

    test('manual and startup updates refresh regardless of auto interval', () {
      final remote = profile(userOverride: const UserOverride(isAutoUpdateDisable: true));

      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(profile: remote, mode: ProfileUpdateMode.manual, now: now),
        isTrue,
      );
      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: remote,
          mode: ProfileUpdateMode.startup,
          now: now,
        ),
        isTrue,
      );
    });

    test('startup updates refresh even when the profile was just updated', () {
      final remote = profile(age: const Duration(minutes: 5), userOverride: const UserOverride(updateInterval: 24));

      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: remote,
          mode: ProfileUpdateMode.startup,
          now: now,
        ),
        isTrue,
      );
    });

    test('automatic update acts as startup recovery until startup refresh completes', () {
      final remote = profile(age: const Duration(minutes: 5), userOverride: const UserOverride(updateInterval: 24));

      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: remote,
          mode: ProfileUpdateMode.automatic,
          now: now,
          startupUpdateHandled: false,
        ),
        isTrue,
      );
    });

    test('automatic updates only use explicit user interval', () {
      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: profile(options: const ProfileOptions(updateInterval: Duration(hours: 1))),
          mode: ProfileUpdateMode.automatic,
          now: now,
        ),
        isFalse,
      );
      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: profile(userOverride: const UserOverride(updateInterval: 12)),
          mode: ProfileUpdateMode.automatic,
          now: now,
        ),
        isTrue,
      );
      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: profile(age: const Duration(hours: 1), userOverride: const UserOverride(updateInterval: 12)),
          mode: ProfileUpdateMode.automatic,
          now: now,
        ),
        isFalse,
      );
    });

    test('automatic updates respect disabled auto update', () {
      expect(
        ForegroundProfilesUpdateNotifier.shouldUpdateProfile(
          profile: profile(userOverride: const UserOverride(isAutoUpdateDisable: true, updateInterval: 1)),
          mode: ProfileUpdateMode.automatic,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
