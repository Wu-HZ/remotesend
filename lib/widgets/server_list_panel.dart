import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../providers/ui_state_provider.dart';
import '../services/webdav_service.dart';

/// A vertical server switcher for wide content layouts.
class ServerListPanel extends ConsumerWidget {
  const ServerListPanel({
    super.key,
    required this.l10n,
    required this.servers,
    required this.activeServer,
    required this.onServerSelected,
    this.onFileDropped,
  });

  final AppLocalizations l10n;
  final List<ServerConfig> servers;
  final ServerConfig? activeServer;
  final ValueChanged<ServerConfig> onServerSelected;
  final Future<void> Function(ServerConfig, RemoteFile)? onFileDropped;

  static const _expandedWidth = 180.0;
  static const _collapsedWidth = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCollapsed = ref.watch(serverSidebarCollapsedProvider);

    return AnimatedContainer(
      width: isCollapsed ? _collapsedWidth : _expandedWidth,
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Align(
            alignment: isCollapsed ? Alignment.center : Alignment.centerRight,
            child: IconButton(
              onPressed: () => ref
                  .read(serverSidebarCollapsedProvider.notifier)
                  .setCollapsed(!isCollapsed),
              icon: Icon(
                isCollapsed ? Icons.chevron_right : Icons.chevron_left,
              ),
              tooltip: isCollapsed ? l10n.expandText : l10n.collapseText,
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final server in servers)
                  _buildServerItem(colorScheme, server, isCollapsed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerItem(
    ColorScheme colorScheme,
    ServerConfig server,
    bool isCollapsed,
  ) {
    final isActive = server.id == activeServer?.id;

    final item = Tooltip(
      message: server.name,
      child: Material(
        color: isActive ? colorScheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: isActive ? null : () => onServerSelected(server),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 0 : 12,
              vertical: 10,
            ),
            child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Center(
                    child: server.emoji.isNotEmpty
                        ? Text(
                            server.emoji,
                            style: const TextStyle(fontSize: 18),
                          )
                        : Icon(
                            Icons.cloud,
                            size: 20,
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      server.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check, size: 18, color: colorScheme.primary),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (onFileDropped == null) return item;

    return DragTarget<RemoteFile>(
      onWillAcceptWithDetails: (details) => !isActive,
      onAcceptWithDetails: (details) {
        onFileDropped!(server, details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: candidateData.isNotEmpty ? colorScheme.primaryContainer : null,
          child: item,
        );
      },
    );
  }
}
