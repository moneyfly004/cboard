import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/widget/responsive_page.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.title),
        actions: [
          PopupMenuButton<ProxiesSort>(
            initialValue: sortBy,
            onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
            icon: const Icon(FluentIcons.arrow_sort_24_regular),
            tooltip: t.pages.proxies.sort,
            itemBuilder: (context) {
              return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
            },
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select"),
        tooltip: t.pages.proxies.testDelay,
        child: const Icon(FluentIcons.flash_24_filled),
      ),
      body: proxies.when(
        data: (group) => group != null
            ? ResponsivePage(
                maxWidth: 1180,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (group.items.isEmpty) {
                      return _ProxyStateCard(icon: Icons.hub_outlined, message: t.pages.proxies.empty);
                    }
                    final width = constraints.maxWidth;
                    final crossAxisCount = PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 292).floor());
                    return GridView.builder(
                      itemCount: group.items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisExtent: 78,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        final proxy = group.items[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: ProxyTile(
                            proxy,
                            selected: group.selected == proxy.tag,
                            onTap: () async {
                              await ref
                                  .read(proxiesOverviewNotifierProvider.notifier)
                                  .changeProxy(group.tag, proxy.tag);
                              // if (selectActiveProxyMutation.state.isInProgress) return;
                              // selectActiveProxyMutation.setFuture(
                              // );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              )
            : _ProxyStateCard(icon: Icons.hub_outlined, message: t.pages.proxies.empty),
        error: (error, stackTrace) =>
            _ProxyStateCard(icon: Icons.error_outline_rounded, message: t.presentShortError(error)),
        loading: () => const _ProxyStateCard.loading(),
      ),
    );
  }
}

class _ProxyStateCard extends StatelessWidget {
  const _ProxyStateCard({required this.icon, required this.message});
  const _ProxyStateCard.loading() : icon = null, message = null;

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
