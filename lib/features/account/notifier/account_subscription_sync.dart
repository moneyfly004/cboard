import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final accountSubscriptionSyncProvider = Provider<AccountSubscriptionSync>((ref) {
  return AccountSubscriptionSync(ref);
});

class AccountSubscriptionSync {
  const AccountSubscriptionSync(this._ref);

  final Ref _ref;

  Future<void> sync(AccountDashboard? dashboard) async {
    final subscription = dashboard?.subscription;
    final url = subscription?.importUrl ?? '';
    if (!_isUniversalSubscriptionUrl(url)) {
      return;
    }

    final repo = _ref.read(profileRepositoryProvider).requireValue;
    await repo
        .upsertRemote(
          url,
          userOverride: UserOverride(name: _profileName(subscription!), updateInterval: 1),
          active: true,
        )
        .getOrElse((failure) => throw failure)
        .run();
  }

  Future<void> refreshActiveSubscription() async {
    final repo = _ref.read(profileRepositoryProvider).requireValue;
    final activeProfile = await repo
        .watchActiveProfile()
        .map((event) => event.getOrElse((failure) => throw failure))
        .first;
    if (activeProfile case RemoteProfileEntity(:final url) when _isUniversalSubscriptionUrl(url)) {
      await repo.upsertRemote(url, active: true).getOrElse((failure) => throw failure).run();
    }
  }

  bool _isUniversalSubscriptionUrl(String url) {
    return url.contains('/subscriptions/universal/');
  }

  String _profileName(AccountSubscription subscription) {
    if (subscription.packageName.isNotEmpty) {
      return subscription.packageName;
    }
    return 'MoneyFly 账户订阅';
  }
}
