import 'package:flutter/material.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
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

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
