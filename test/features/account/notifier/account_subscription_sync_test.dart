import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_subscription_sync.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('sync only replaces account subscription profile', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final manualProfile = RemoteProfileEntity(
      id: 'manual',
      active: true,
      name: 'Manual',
      url: 'https://example.com/manual.yaml',
      lastUpdate: DateTime(2026),
    );
    final manualUniversalProfile = RemoteProfileEntity(
      id: 'manual-universal',
      active: false,
      name: 'Manual Universal',
      url: 'https://example.com/subscriptions/universal/manual-token',
      lastUpdate: DateTime(2026),
    );
    final legacyAccountProfile = RemoteProfileEntity(
      id: 'legacy-account',
      active: false,
      name: 'VIP',
      url: 'https://dy.moneyfly.top/api/v1/subscriptions/universal/legacy-token',
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(version: 1, name: 'VIP', updateInterval: 1),
    );
    final oldAccountProfile = RemoteProfileEntity(
      id: 'account',
      active: false,
      name: AccountSubscriptionSync.accountProfileName,
      url: accountUrl,
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(version: 1, name: AccountSubscriptionSync.accountProfileName, updateInterval: 1),
    );
    final repo = _FakeProfileRepository([
      manualProfile,
      manualUniversalProfile,
      legacyAccountProfile,
      oldAccountProfile,
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              singboxUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.deletedIds, ['legacy-account']);
    expect(repo.profiles.map((profile) => profile.id), contains('manual'));
    expect(repo.profiles.map((profile) => profile.id), contains('manual-universal'));
    expect(repo.profiles.map((profile) => profile.id), contains('account'));
    expect(repo.upsertedUrls, [accountUrl]);
    expect(repo.upsertedUserOverrides, [AccountSubscriptionSync.accountProfileOverride]);
  });

  test('sync removes account subscription profile when subscription is expired', () async {
    const expiredAccountUrl = 'https://dy.moneyfly.top/api/v1/subscriptions/universal/expired-token';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'old-expired-account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: expiredAccountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(
          version: 1,
          name: AccountSubscriptionSync.accountProfileName,
          updateInterval: 1,
        ),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'Expired',
              universalUrl: expiredAccountUrl,
              status: 'expired',
              remainingDays: -1,
            ),
          ),
        );

    expect(repo.deletedIds, ['old-expired-account']);
    expect(repo.upsertedUrls, isEmpty);
  });

  test('sync preserves account subscription when backend status is unavailable', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: accountUrl,
        lastUpdate: DateTime(2026),
        userOverride: AccountSubscriptionSync.accountProfileOverride,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(const AccountDashboard().preserveExistingLocalSubscription());

    expect(repo.deletedIds, isEmpty);
    expect(repo.upsertedUrls, isEmpty);
    expect(repo.profiles.map((profile) => profile.id), contains('account'));
  });

  test('refresh active subscription preserves account subscription when backend status is unavailable', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/subscriptions/universal/account-token';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: accountUrl,
        lastUpdate: DateTime(2026),
        userOverride: AccountSubscriptionSync.accountProfileOverride,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .refreshActiveSubscription(const AccountDashboard().preserveExistingLocalSubscription());

    expect(repo.deletedIds, isEmpty);
    expect(repo.upsertedUrls, isEmpty);
    expect(repo.profiles.map((profile) => profile.id), contains('account'));
  });

  test('sync keeps user configured account subscription update interval', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: accountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(name: AccountSubscriptionSync.accountProfileName, updateInterval: 12),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              singboxUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUserOverrides, [
      const UserOverride(name: AccountSubscriptionSync.accountProfileName, updateInterval: 12),
    ]);
  });

  test('sync keeps existing account subscription when importing new config fails', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: accountUrl,
        lastUpdate: DateTime(2026),
        userOverride: AccountSubscriptionSync.accountProfileOverride,
      ),
    ])..upsertFailure = const ProfileFailure.invalidConfig('disabled');
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(accountSubscriptionSyncProvider)
          .sync(
            const AccountDashboard(
              subscription: AccountSubscription(
                id: 1,
                packageName: 'VIP',
                singboxUrl: accountUrl,
                status: 'active',
                remainingDays: 30,
                isActive: true,
              ),
            ),
          ),
      throwsA(isA<ProfileInvalidConfigFailure>()),
    );

    expect(repo.deletedIds, isEmpty);
    expect(repo.profiles.map((profile) => profile.id), contains('account'));
    expect(repo.upsertedUrls, [accountUrl]);
  });

  test('sync deletes old account subscription after importing replacement config', () async {
    const oldAccountUrl = 'https://dy.moneyfly.top/api/v1/subscriptions/universal/old-token';
    const accountUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const accountSingboxUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'old-account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: oldAccountUrl,
        lastUpdate: DateTime(2026),
        userOverride: AccountSubscriptionSync.accountProfileOverride,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              universalUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [accountSingboxUrl]);
    expect(repo.deletedIds, ['old-account']);
    expect(repo.profiles.whereType<RemoteProfileEntity>().single.url, accountSingboxUrl);
  });

  test('sync deletes legacy account subscription from custom API host after replacement', () async {
    const oldAccountUrl = 'https://client.example.com/api/v1/client/subscribe?token=old-token';
    const accountUrl = 'https://client.example.com/api/v1/client/subscribe?token=account-token&type=singbox';
    final manualProfile = RemoteProfileEntity(
      id: 'manual',
      active: false,
      name: 'Manual',
      url: 'https://client.example.com/api/v1/client/subscribe?token=manual-token',
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(name: 'Manual', updateInterval: 1),
    );
    final repo = _FakeProfileRepository([
      manualProfile,
      RemoteProfileEntity(
        id: 'legacy-custom-account',
        active: true,
        name: 'VIP',
        url: oldAccountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(version: 1, name: 'VIP', updateInterval: 1),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              singboxUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [accountUrl]);
    expect(repo.deletedIds, ['legacy-custom-account']);
    expect(repo.profiles.map((profile) => profile.id), contains('manual'));
    expect(repo.profiles.whereType<RemoteProfileEntity>().map((profile) => profile.url), contains(accountUrl));
  });

  test('sync removes account subscription profile when subscription is disabled but still has a url', () async {
    const disabledAccountUrl = 'https://dy.moneyfly.top/api/v1/subscriptions/universal/disabled-token';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'old-disabled-account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: disabledAccountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(
          version: 1,
          name: AccountSubscriptionSync.accountProfileName,
          updateInterval: 1,
        ),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'Disabled',
              universalUrl: disabledAccountUrl,
              status: 'disabled',
              remainingDays: 30,
            ),
          ),
        );

    expect(repo.deletedIds, ['old-disabled-account']);
    expect(repo.upsertedUrls, isEmpty);
  });

  test('sync imports backend client subscribe url after login', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const accountSingboxUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              universalUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [accountSingboxUrl]);
    expect(repo.upsertedUserOverrides, [AccountSubscriptionSync.accountProfileOverride]);
    expect(repo.profiles.whereType<RemoteProfileEntity>().single.url, accountSingboxUrl);
  });

  test('sync imports backend sing-box subscribe url when available', () async {
    const singboxUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              singboxUrl: singboxUrl,
              universalUrl: 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token',
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [singboxUrl]);
    expect(repo.profiles.whereType<RemoteProfileEntity>().single.url, singboxUrl);
  });

  test('sync does not fall back when backend sing-box subscription cannot be parsed', () async {
    const singboxUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    const universalUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token';
    final repo = _FakeProfileRepository([])
      ..upsertFailuresByUrl[singboxUrl] = const ProfileFailure.invalidConfig(
        '[SingboxParser] unmarshal error: outbounds[0].server: json: unknown field "server"',
      );
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    final sync = container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              singboxUrl: singboxUrl,
              universalUrl: universalUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    await expectLater(sync, throwsA(isA<ProfileFailure>()));
    expect(repo.upsertedUrls, [singboxUrl]);
    expect(repo.deletedIds, isEmpty);
    expect(repo.profiles.whereType<RemoteProfileEntity>(), isEmpty);
  });

  test('sync only tries derived sing-box url and never falls back to universal url', () async {
    const singboxUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    const universalUrl = 'https://dy.moneyfly.top/api/v1/client/subscribe?token=account-token';
    final repo = _FakeProfileRepository([])
      ..upsertFailuresByUrl[singboxUrl] = const ProfileFailure.invalidConfig(
        '[SingboxParser] unmarshal error: outbounds[0].server: json: unknown field "server"',
      );
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    final sync = container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              universalUrl: universalUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    await expectLater(sync, throwsA(isA<ProfileFailure>()));
    expect(repo.upsertedUrls, [singboxUrl]);
    expect(repo.deletedIds, isEmpty);
    expect(repo.profiles.whereType<RemoteProfileEntity>(), isEmpty);
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profiles);

  final List<ProfileEntity> profiles;
  final List<String> deletedIds = [];
  final List<String> upsertedUrls = [];
  final List<UserOverride?> upsertedUserOverrides = [];
  final Map<String, ProfileFailure> upsertFailuresByUrl = {};
  ProfileFailure? upsertFailure;

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) {
    return TaskEither.tryCatch(() async {
      deletedIds.add(id);
      profiles.removeWhere((profile) => profile.id == id);
      return unit;
    }, ProfileFailure.unexpected);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return Stream.value(right(List<ProfileEntity>.of(profiles)));
  }

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    bool active = false,
  }) {
    final failure = upsertFailuresByUrl[url] ?? upsertFailure;
    if (failure != null) {
      upsertedUrls.add(url);
      upsertedUserOverrides.add(userOverride);
      return TaskEither.left(failure);
    }
    return TaskEither.tryCatch(() async {
      upsertedUrls.add(url);
      upsertedUserOverrides.add(userOverride);
      profiles.add(
        RemoteProfileEntity(
          id: 'new-account',
          active: active,
          name: userOverride?.name ?? 'Remote',
          url: url,
          lastUpdate: DateTime(2026),
          userOverride: userOverride,
        ),
      );
      return unit;
    }, ProfileFailure.unexpected);
  }

  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride}) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return TaskEither.of(unit);
  }

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug) {
    throw UnimplementedError();
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    throw UnimplementedError();
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    throw UnimplementedError();
  }
}
