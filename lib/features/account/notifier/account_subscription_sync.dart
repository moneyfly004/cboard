import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final accountSubscriptionSyncProvider = Provider<AccountSubscriptionSync>((ref) {
  return AccountSubscriptionSync(ref);
});

class AccountSubscriptionSync {
  const AccountSubscriptionSync(this._ref);

  final Ref _ref;
  static const accountProfileName = 'MoneyFly 账户订阅';
  static const accountProfileOverride = UserOverride(name: accountProfileName, isAutoUpdateDisable: true);

  Future<void> clearAccountSubscriptions() async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteAccountProfiles(repo);
  }

  Future<void> sync(AccountDashboard? dashboard) async {
    final subscription = dashboard?.subscription;
    final url = subscription?.importUrl ?? '';
    final repo = await _ref.read(profileRepositoryProvider.future);
    final canImport = subscription != null && subscription.canImport && _isUniversalSubscriptionUrl(url);
    final existingAccountProfile = await _deleteAccountProfiles(repo, activeUrl: url, keepActiveUrl: canImport);
    if (!canImport) {
      return;
    }

    await repo
        .upsertRemote(url, userOverride: _accountUserOverride(existingAccountProfile), active: true)
        .getOrElse((failure) => throw failure)
        .run();
  }

  Future<void> refreshActiveSubscription(AccountDashboard? dashboard) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final subscription = dashboard?.subscription;
    final activeUrl = subscription?.importUrl ?? '';
    final canImport = subscription != null && subscription.canImport && _isUniversalSubscriptionUrl(activeUrl);
    final existingAccountProfile = await _deleteAccountProfiles(repo, activeUrl: activeUrl, keepActiveUrl: canImport);
    if (!canImport) {
      return;
    }
    await repo
        .upsertRemote(activeUrl, userOverride: _accountUserOverride(existingAccountProfile), active: true)
        .getOrElse((failure) => throw failure)
        .run();
  }

  bool _isUniversalSubscriptionUrl(String url) {
    return url.contains('/subscriptions/universal/');
  }

  Future<RemoteProfileEntity?> _deleteAccountProfiles(
    ProfileRepository repo, {
    String? activeUrl,
    bool keepActiveUrl = false,
  }) async {
    final profiles = await repo
        .watchAll(sortMode: SortMode.descending)
        .map((event) => event.getOrElse((failure) => throw failure))
        .first;
    RemoteProfileEntity? keptAccountProfile;
    for (final profile in profiles.where((profile) => _isAccountProfile(profile, activeUrl: activeUrl))) {
      if (keepActiveUrl &&
          activeUrl != null &&
          activeUrl.isNotEmpty &&
          profile is RemoteProfileEntity &&
          profile.url == activeUrl) {
        keptAccountProfile = profile;
        continue;
      }
      await repo.deleteById(profile.id, profile.active).getOrElse((failure) => throw failure).run();
    }
    return keptAccountProfile;
  }

  UserOverride _accountUserOverride(RemoteProfileEntity? existingProfile) {
    final userOverride = existingProfile?.userOverride;
    if (userOverride != null &&
        userOverride.version >= 2 &&
        (userOverride.updateInterval != null || userOverride.isAutoUpdateDisable)) {
      return userOverride.copyWith(name: accountProfileName);
    }
    return accountProfileOverride;
  }

  bool _isAccountProfile(ProfileEntity profile, {String? activeUrl}) {
    return switch (profile) {
      RemoteProfileEntity(:final name, :final url, :final userOverride) =>
        name == accountProfileName ||
            userOverride?.name == accountProfileName ||
            (activeUrl != null && activeUrl.isNotEmpty && url == activeUrl) ||
            _isLegacyAccountProfile(name: name, url: url, userOverride: userOverride),
      LocalProfileEntity(:final name, :final userOverride) =>
        name == accountProfileName || userOverride?.name == accountProfileName,
    };
  }

  bool _isLegacyAccountProfile({required String name, required String url, required UserOverride? userOverride}) {
    if (userOverride?.name != name || !_hasLegacyAccountUpdateInterval(userOverride)) {
      return false;
    }
    final uri = Uri.tryParse(url);
    return uri != null &&
        _isKnownAccountSubscriptionHost(uri.host) &&
        uri.pathSegments.contains('subscriptions') &&
        uri.pathSegments.contains('universal');
  }

  bool _hasLegacyAccountUpdateInterval(UserOverride? userOverride) {
    return userOverride?.updateInterval == 1 || userOverride?.isAutoUpdateDisable == true;
  }

  bool _isKnownAccountSubscriptionHost(String host) {
    final apiHost = Uri.tryParse(kCBoardApiBaseUrl)?.host;
    return host == 'dy.moneyfly.top' || (apiHost != null && apiHost.isNotEmpty && host == apiHost);
  }
}
