import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/app_config.dart';

void main() {
  test('cleanup defaults on for new and older configurations', () {
    expect(AppConfig().autoClearTransferHistory, isTrue);
    for (final version in [1, 2, 3, 11]) {
      final config = AppConfig.fromJson({'version': version, 'servers': []});
      expect(config.autoClearTransferHistory, isTrue);
      expect(config.version, AppConfig.currentVersion);
    }
  });

  test('disabled cleanup survives serialization and both copy operations', () {
    final config = AppConfig(autoClearTransferHistory: false);
    final loaded = AppConfig.fromJsonString(config.toJsonString());
    expect(loaded.autoClearTransferHistory, isFalse);
    expect(
      loaded.copyWith(localName: 'new name').autoClearTransferHistory,
      isFalse,
    );
    expect(
      loaded
          .copyWithNullActiveServers(clearText: true)
          .autoClearTransferHistory,
      isFalse,
    );
    expect(
      loaded.copyWith(autoClearTransferHistory: true).autoClearTransferHistory,
      isTrue,
    );
    expect(
      loaded
          .copyWithNullActiveServers(autoClearTransferHistory: true)
          .autoClearTransferHistory,
      isTrue,
    );
  });

  test('cleanup preference participates in configuration equality', () {
    final config = AppConfig();
    expect(config.copyWith(), config);
    expect(config.copyWith().hashCode, config.hashCode);
    expect(config.copyWith(autoClearTransferHistory: false), isNot(config));
  });
}
