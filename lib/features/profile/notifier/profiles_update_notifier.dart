import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const prefKey = "profiles_update_check";
  static const workerInterval = Duration(minutes: 15);

  @override
  Stream<ProfileUpdateStatus?> build() {
    var cycleCount = 0;
    _scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: workerInterval,
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    ref.onDispose(() async {
      await _scheduler?.stop();
      _scheduler = null;
    });

    if (ref.watch(Preferences.introCompleted)) {
      loggy.debug("intro done, starting");
      _scheduler?.start();
    } else {
      loggy.debug("intro in process, skipping");
    }
    return const Stream.empty();
  }

  NeatPeriodicTaskScheduler? _scheduler;
  ProfileUpdateMode? _pendingMode;
  Future<void>? _runningUpdate;
  bool _startupUpdateHandled = false;

  Future<void> trigger({ProfileUpdateMode mode = ProfileUpdateMode.manual}) async {
    loggy.debug("triggering update, mode: [$mode]");
    await updateProfiles(mode: mode);
  }

  Future<void> triggerStartupRefresh() async {
    if (_startupUpdateHandled) {
      loggy.debug("startup profile refresh already completed");
      return;
    }
    await updateProfiles(mode: ProfileUpdateMode.startup);
  }

  @visibleForTesting
  Future<void> updateProfiles({ProfileUpdateMode mode = ProfileUpdateMode.automatic}) async {
    _queueMode(mode);
    if (_runningUpdate case final running?) return running;

    final run = _drainUpdateQueue();
    _runningUpdate = run;
    try {
      await run;
    } finally {
      _runningUpdate = null;
    }
  }

  Future<void> _drainUpdateQueue() async {
    while (true) {
      final mode = _pendingMode;
      if (mode == null) return;
      _pendingMode = null;
      await _updateProfiles(mode);
    }
  }

  void _queueMode(ProfileUpdateMode mode) {
    _pendingMode = _higherPriorityMode(_pendingMode, mode);
  }

  static ProfileUpdateMode _higherPriorityMode(ProfileUpdateMode? current, ProfileUpdateMode next) {
    if (current == null || next.priority > current.priority) {
      return next;
    }
    return current;
  }

  Future<void> _updateProfiles(ProfileUpdateMode mode) async {
    final isStartup =
        mode == ProfileUpdateMode.startup || (mode == ProfileUpdateMode.automatic && !_startupUpdateHandled);
    final profileUpdateMode = isStartup ? ProfileUpdateMode.startup : mode;
    final force = mode == ProfileUpdateMode.manual || isStartup;
    final refreshAccount = mode == ProfileUpdateMode.manual || isStartup;
    final notify = mode == ProfileUpdateMode.manual;
    if (mode == ProfileUpdateMode.startup && _startupUpdateHandled) {
      loggy.debug("skipping duplicate startup profile refresh");
      return;
    }
    if (mode == ProfileUpdateMode.automatic && isStartup) {
      loggy.debug("running automatic update as startup recovery refresh");
    }

    var completed = false;
    try {
      final previousRun = DateTime.tryParse(ref.read(sharedPreferencesProvider).requireValue.getString(prefKey) ?? "");

      if (!force && previousRun != null && previousRun.add(workerInterval).isAfter(DateTime.now())) {
        loggy.debug("too soon! previous run: [$previousRun]");
        return;
      }
      loggy.debug("running [$mode], previous run: [$previousRun]");

      if (refreshAccount) {
        await ref.read(accountNotifierProvider.notifier).refreshSubscriptionStatusSilently();
      }

      final remoteProfiles = await ref
          .read(profileRepositoryProvider)
          .requireValue
          .watchAll()
          .map(
            (event) => event.getOrElse((f) {
              loggy.error("error getting profiles");
              throw f;
            }).whereType<RemoteProfileEntity>(),
          )
          .first;

      await for (final profile in Stream.fromIterable(remoteProfiles)) {
        if (_shouldUpdateProfile(profile: profile, mode: profileUpdateMode, now: DateTime.now())) {
          final t = notify ? ref.read(translationsProvider).requireValue : null;
          await ref
              .read(profileRepositoryProvider)
              .requireValue
              .upsertRemote(profile.url)
              .mapLeft((l) {
                loggy.debug("error updating profile [${profile.id}]", l);
                if (t != null) {
                  ref
                      .read(inAppNotificationControllerProvider)
                      .showErrorToast(t.pages.profiles.msg.update.failureNamed(name: profile.name));
                }
                state = AsyncData((name: profile.name, success: false));
              })
              .map((_) {
                loggy.debug("profile [${profile.id}] updated successfully");
                if (t != null) {
                  ref
                      .read(inAppNotificationControllerProvider)
                      .showSuccessToast(t.pages.profiles.msg.update.successNamed(name: profile.name));
                }
                state = AsyncData((name: profile.name, success: true));
              })
              .run();
        } else {
          loggy.debug(
            "skipping profile [${profile.id}] update. last successful update: [${profile.lastUpdate}] - interval: [${profile.userOverride?.updateInterval}]",
          );
        }
      }
      completed = true;
    } finally {
      await ref.read(sharedPreferencesProvider).requireValue.setString(prefKey, DateTime.now().toIso8601String());
      if (completed && force) {
        _startupUpdateHandled = true;
      }
    }
  }

  @visibleForTesting
  static bool shouldUpdateProfile({
    required RemoteProfileEntity profile,
    required ProfileUpdateMode mode,
    required DateTime now,
    bool startupUpdateHandled = true,
  }) {
    if (!startupUpdateHandled && mode == ProfileUpdateMode.automatic) {
      mode = ProfileUpdateMode.startup;
    }
    return _shouldUpdateProfile(profile: profile, mode: mode, now: now);
  }

  static bool _shouldUpdateProfile({
    required RemoteProfileEntity profile,
    required ProfileUpdateMode mode,
    required DateTime now,
  }) {
    if (mode == ProfileUpdateMode.manual || mode == ProfileUpdateMode.startup) {
      return true;
    }
    if (profile.userOverride?.isAutoUpdateDisable ?? false) {
      return false;
    }
    final updateIntervalHours = profile.userOverride?.updateInterval;
    if (updateIntervalHours == null || updateIntervalHours <= 0) {
      return false;
    }
    final updateInterval = Duration(hours: updateIntervalHours);
    return updateInterval <= now.difference(profile.lastUpdate);
  }
}

enum ProfileUpdateMode {
  automatic(0),
  startup(1),
  manual(2);

  const ProfileUpdateMode(this.priority);

  final int priority;
}
