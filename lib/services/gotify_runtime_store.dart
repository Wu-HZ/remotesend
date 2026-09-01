import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/gotify_models.dart';

const _runtimeKeyPrefix = 'gotify_runtime_v1';

class PendingGotifyEvent {
  const PendingGotifyEvent({
    required this.event,
    required this.title,
    required this.message,
    required this.priority,
  });

  final RemoteSendEvent event;
  final String title;
  final String message;
  final int priority;

  Map<String, dynamic> toJson() => {
    'event': event.toJson(),
    'title': title,
    'message': message,
    'priority': priority,
  };

  factory PendingGotifyEvent.fromJson(Map<String, dynamic> json) {
    return PendingGotifyEvent(
      event: RemoteSendEvent.fromJson(
        Map<String, dynamic>.from(json['event'] as Map),
      ),
      title: json['title'] as String? ?? 'RemoteSend',
      message: json['message'] as String? ?? 'RemoteSend event',
      priority: (json['priority'] as num?)?.toInt() ?? 0,
    );
  }
}

class GotifyRuntimeData {
  const GotifyRuntimeData({
    this.lastMessageId = 0,
    this.devices = const {},
    this.processedEventIds = const [],
    this.pendingInboundEvents = const [],
    this.deferredInboundEvents = const [],
    this.outbox = const [],
  });

  final int lastMessageId;
  final Map<String, RemoteDevice> devices;
  final List<String> processedEventIds;

  /// Session-only receive work. It is deliberately omitted from persistence.
  final List<RemoteSendEvent> pendingInboundEvents;

  /// Background notifications persisted until the app returns to foreground.
  final List<RemoteSendEvent> deferredInboundEvents;
  final List<PendingGotifyEvent> outbox;

  GotifyRuntimeData copyWith({
    int? lastMessageId,
    Map<String, RemoteDevice>? devices,
    List<String>? processedEventIds,
    List<RemoteSendEvent>? pendingInboundEvents,
    List<RemoteSendEvent>? deferredInboundEvents,
    List<PendingGotifyEvent>? outbox,
  }) {
    return GotifyRuntimeData(
      lastMessageId: lastMessageId ?? this.lastMessageId,
      devices: devices ?? this.devices,
      processedEventIds: processedEventIds ?? this.processedEventIds,
      pendingInboundEvents: pendingInboundEvents ?? this.pendingInboundEvents,
      deferredInboundEvents:
          deferredInboundEvents ?? this.deferredInboundEvents,
      outbox: outbox ?? this.outbox,
    );
  }

  Map<String, dynamic> toJson() => {
    'lastMessageId': lastMessageId,
    'devices': {
      for (final item in devices.entries) item.key: item.value.toJson(),
    },
    'processedEventIds': processedEventIds,
    // Active inbound work is session-only; intentionally deferred background
    // notifications are persisted so Android can recover after process death.
    'deferredInboundEvents': deferredInboundEvents
        .map((event) => event.toJson())
        .toList(),
    'outbox': outbox.map((item) => item.toJson()).toList(),
  };

  factory GotifyRuntimeData.fromJson(Map<String, dynamic> json) {
    final devices = <String, RemoteDevice>{};
    final rawDevices = json['devices'];
    if (rawDevices is Map) {
      for (final entry in rawDevices.entries) {
        try {
          final device = RemoteDevice.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          devices[device.id] = device;
        } catch (_) {
          // Keep the rest of the registry if one item is malformed.
        }
      }
    }

    final deferredInboundEvents = <RemoteSendEvent>[];
    final rawDeferredInbound = json['deferredInboundEvents'];
    if (rawDeferredInbound is List) {
      for (final item in rawDeferredInbound.whereType<Map>()) {
        try {
          deferredInboundEvents.add(
            RemoteSendEvent.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Ignore malformed deferred events.
        }
      }
    }

    final outbox = <PendingGotifyEvent>[];
    final rawOutbox = json['outbox'];
    if (rawOutbox is List) {
      for (final item in rawOutbox.whereType<Map>()) {
        try {
          outbox.add(
            PendingGotifyEvent.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Ignore malformed pending events.
        }
      }
    }

    return GotifyRuntimeData(
      lastMessageId: (json['lastMessageId'] as num?)?.toInt() ?? 0,
      devices: devices,
      processedEventIds:
          (json['processedEventIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      deferredInboundEvents: deferredInboundEvents,
      outbox: outbox,
    );
  }
}

class GotifyRuntimeStore {
  GotifyRuntimeStore(String namespace)
    : _key = '${_runtimeKeyPrefix}_$namespace';

  final String _key;

  Future<GotifyRuntimeData> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
      if (raw == null) return const GotifyRuntimeData();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const GotifyRuntimeData();
      return GotifyRuntimeData.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const GotifyRuntimeData();
    }
  }

  Future<void> save(GotifyRuntimeData data) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(data.toJson()));
  }
}
