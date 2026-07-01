import 'package:flutter/material.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<bool> syncAccountSubscriptionWithFeedback(BuildContext context, WidgetRef ref) async {
  try {
    final imported = await ref.read(accountNotifierProvider.notifier).syncSubscription();
    if (context.mounted) {
      _showSnack(context, imported ? '订阅已同步' : '未找到可同步的账户订阅，请确认套餐已生效');
    }
    return imported;
  } on AccountApiException catch (error) {
    if (context.mounted) _showSnack(context, error.message);
    return false;
  } catch (error) {
    if (context.mounted) _showSnack(context, error.toString());
    return false;
  }
}

Future<ProfileEntity?> ensureAccountSubscriptionProfileWithFeedback(BuildContext context, WidgetRef ref) async {
  final activeProfile = ref.read(activeProfileProvider).valueOrNull;
  if (activeProfile != null) {
    return activeProfile;
  }

  if (ref.read(accountNotifierProvider).isAuthenticated) {
    final imported = await syncAccountSubscriptionWithFeedback(context, ref);
    if (!context.mounted) {
      return null;
    }
    if (imported) {
      ref.invalidate(activeProfileProvider);
      final syncedProfile = await ref.read(activeProfileProvider.future);
      if (syncedProfile != null) {
        return syncedProfile;
      }
    }
  }

  await ref.read(dialogNotifierProvider.notifier).showNoActiveProfile();
  return null;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
