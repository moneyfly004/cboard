import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AddProfileModal extends ConsumerWidget {
  const AddProfileModal({super.key, this.url});

  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded, color: theme.colorScheme.primary),
                const Gap(10),
                Expanded(child: Text('账户订阅同步', style: theme.textTheme.titleLarge)),
                IconButton(tooltip: '关闭', onPressed: context.pop, icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const Gap(12),
            Text(
              '订阅配置由登录账户自动下发。请登录账户后同步订阅，本客户端不支持手动添加订阅地址。',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Gap(18),
            FilledButton.icon(
              onPressed: state.loading || !state.isAuthenticated
                  ? null
                  : () async {
                      final imported = await ref.read(accountNotifierProvider.notifier).syncSubscription();
                      if (!imported) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('未找到可同步的账户订阅，请确认套餐已生效')));
                        }
                        return;
                      }
                      if (context.mounted && context.canPop()) {
                        context.pop();
                      }
                    },
              icon: state.loading
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.update_rounded),
              label: const Text('同步账户订阅'),
            ),
            const Gap(8),
            OutlinedButton.icon(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                }
                context.goNamed('account');
              },
              icon: const Icon(Icons.person_rounded),
              label: const Text('前往账户中心登录'),
            ),
          ],
        ),
      ),
    );
  }
}
