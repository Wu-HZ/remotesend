import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether RemoteSend is actively being used on this device.
///
/// Mobile uses the Flutter application lifecycle. Desktop additionally treats
/// an unfocused window as background so a long-running instance can defer
/// costly file receive work.
final appForegroundProvider = StateProvider<bool>((ref) => true);
