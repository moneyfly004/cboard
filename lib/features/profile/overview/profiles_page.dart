import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/responsive_page.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hiddify/features/account/widget/account_subscription_sync_feedback.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfilesPage extends HookConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);
    final accountState = ref.watch(accountNotifierProvider);

    ref.listen(hasAnyProfileProvider, (_, next) {
      if (next.value == false) {
        context.goNamed('home');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.profiles.title),
        actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.update_rounded),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          IconButton(
            onPressed: () => ref.read(dialogNotifierProvider.notifier).showSortProfiles(),
            icon: const Icon(Icons.sort_rounded),
            tooltip: t.common.sort,
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: accountState.loading
            ? null
            : accountState.isAuthenticated
            ? () => syncAccountSubscriptionWithFeedback(context, ref)
            : () => context.goNamed('account'),
        label: Text(accountState.isAuthenticated ? '同步账户订阅' : '登录账户'),
        icon: accountState.loading
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cloud_sync_rounded),
      ),
      body: asyncProfiles.when(
        data: (data) {
          if (data.isEmpty) {
            return _ProfilesStateCard(icon: Icons.view_list_outlined, message: t.common.empty);
          }
          return ResponsivePage(
            maxWidth: 760,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            child: ListView.separated(
              separatorBuilder: (context, index) => const Gap(12),
              itemBuilder: (context, index) => ProfileTile(profile: data[index]),
              itemCount: data.length,
            ),
          );
        },
        loading: () => const _ProfilesStateCard.loading(),
        error: (error, stackTrace) =>
            _ProfilesStateCard(icon: Icons.error_outline_rounded, message: t.presentShortError(error)),
      ),
    );
  }
}

class _ProfilesStateCard extends StatelessWidget {
  const _ProfilesStateCard({required this.icon, required this.message});
  const _ProfilesStateCard.loading() : icon = null, message = null;

  final IconData? icon;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ResponsivePage(
      maxWidth: 520,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == null)
                const CircularProgressIndicator()
              else ...[
                Icon(icon, size: 34, color: theme.colorScheme.primary),
                const Gap(12),
                Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
