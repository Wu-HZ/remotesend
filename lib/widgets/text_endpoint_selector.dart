import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/server_endpoint.dart';
import '../providers/text_endpoint_provider.dart';
import '../providers/text_send_provider.dart';
import '../providers/ui_state_provider.dart';

String textEndpointName(ServerEndpoint endpoint, AppLocalizations _) =>
    endpoint.name;

Widget _icon(ServerEndpoint endpoint) => endpoint.emoji.isNotEmpty
    ? Text(endpoint.emoji, style: const TextStyle(fontSize: 18))
    : const Icon(Icons.cloud, size: 20);

Future<void> _select(
  BuildContext context,
  WidgetRef ref,
  ServerEndpoint endpoint,
) async {
  final saved = await ref.read(textEndpointActionsProvider).select(endpoint);
  if (!saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.failedToSave)),
    );
  }
}

class TextEndpointSelector extends ConsumerWidget {
  const TextEndpointSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpoints = ref.watch(textServerEndpointsProvider);
    final active = ref.watch(activeTextEndpointProvider);
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      key: const ValueKey('text-endpoint-selector'),
      tooltip: l10n.switchServer,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active != null)
            _icon(active)
          else
            const Icon(Icons.cloud_off, size: 20),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      onSelected: (id) =>
          _select(context, ref, endpoints.firstWhere((e) => e.id == id)),
      itemBuilder: (_) => [
        for (final endpoint in endpoints)
          PopupMenuItem(
            value: endpoint.id,
            child: Row(
              children: [
                _icon(endpoint),
                const SizedBox(width: 8),
                Expanded(child: Text(textEndpointName(endpoint, l10n))),
                if (endpoint.id == active?.id)
                  const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// Registration does not silently change the selected text destination.
class ChooseTextEndpointScreen extends ConsumerWidget {
  const ChooseTextEndpointScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final endpoints = ref.watch(textServerEndpointsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.textLabel)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 630),
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.selectTargetServer),
              ),
              for (final endpoint in endpoints)
                ListTile(
                  leading: _icon(endpoint),
                  title: Text(textEndpointName(endpoint, l10n)),
                  onTap: () => _select(context, ref, endpoint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text-only presentation. It cannot be used as a file drop target.
class TextEndpointPanel extends ConsumerWidget {
  const TextEndpointPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(serverSidebarCollapsedProvider);
    final endpoints = ref.watch(textServerEndpointsProvider);
    final active = ref.watch(activeTextEndpointProvider);
    final l10n = AppLocalizations.of(context)!;
    return AnimatedContainer(
      width: collapsed ? 64 : 180,
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        children: [
          Align(
            alignment: collapsed ? Alignment.center : Alignment.centerRight,
            child: IconButton(
              onPressed: () => ref
                  .read(serverSidebarCollapsedProvider.notifier)
                  .setCollapsed(!collapsed),
              tooltip: collapsed ? l10n.expandText : l10n.collapseText,
              icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final endpoint in endpoints)
                  Tooltip(
                    message: textEndpointName(endpoint, l10n),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: collapsed ? 20 : 12,
                      ),
                      selected: endpoint.id == active?.id,
                      leading: _icon(endpoint),
                      title: collapsed
                          ? null
                          : Text(textEndpointName(endpoint, l10n)),
                      onTap: () => _select(context, ref, endpoint),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
