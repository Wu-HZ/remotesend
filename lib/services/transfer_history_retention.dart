import 'dart:async';

/// Tracks successful records independently of the transfer UI and file cache.
/// Timers are only allocated while completed records exist.
class TransferHistoryRetention {
  TransferHistoryRetention({
    required this.canPrune,
    required this.onExpired,
    this.retention = const Duration(minutes: 5),
  });

  final bool Function() canPrune;
  final void Function(Set<String>) onExpired;
  final Duration retention;
  final Map<String, Timer> _timers = {};
  final Set<String> _expired = {};
  Set<String> _completedIds = {};
  bool _enabled = true;
  bool _disposed = false;
  bool _pruneScheduled = false;

  /// Re-enabling starts a fresh retention period for existing success records.
  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _expired.clear();
    } else {
      update(_completedIds);
    }
  }

  void update(Iterable<String> completedIds) {
    if (_disposed) return;
    final ids = completedIds.toSet();
    _completedIds = ids;
    if (!_enabled) return;
    for (final id in _timers.keys.toList()) {
      if (!ids.contains(id)) _timers.remove(id)?.cancel();
    }
    _expired.removeWhere((id) => !ids.contains(id));
    for (final id in ids) {
      if (_timers.containsKey(id) || _expired.contains(id)) continue;
      _timers[id] = Timer(retention, () {
        _timers.remove(id);
        _expired.add(id);
        _schedulePrune();
      });
    }
    _schedulePrune();
  }

  void _schedulePrune() {
    if (_disposed ||
        !_enabled ||
        _pruneScheduled ||
        _expired.isEmpty ||
        !canPrune()) {
      return;
    }
    // State observers may call update(). Never publish another state while
    // those observers are still receiving the previous state.
    _pruneScheduled = true;
    scheduleMicrotask(() {
      _pruneScheduled = false;
      _prune();
    });
  }

  void _prune() {
    if (_disposed || !_enabled || _expired.isEmpty || !canPrune()) return;
    final ids = Set<String>.from(_expired);
    _expired.clear();
    onExpired(ids);
  }

  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _expired.clear();
    _completedIds.clear();
  }
}
