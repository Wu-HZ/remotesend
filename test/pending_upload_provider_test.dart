import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/providers/pending_upload_provider.dart';

void main() {
  test('移交快照后保留并发追加与上传失败回退的文件', () {
    final notifier = PendingUploadNotifier();
    addTearDown(notifier.dispose);
    notifier.addFiles(['first.jpg', 'second.jpg']);
    final batch = notifier.beginSubmission();
    expect(batch, ['first.jpg', 'second.jpg']);
    expect(notifier.state.isSubmitting, isTrue);
    expect(notifier.beginSubmission(), isEmpty);

    notifier.addFiles(['new.jpg', 'first.jpg']);
    notifier.clear();
    notifier.finishSubmission();
    expect(notifier.state.filePaths, ['new.jpg', 'first.jpg']);
    expect(notifier.state.isSubmitting, isFalse);
  });

  test('未成功移交的文件恢复到待发送列表，不覆盖新文件', () {
    final notifier = PendingUploadNotifier();
    addTearDown(notifier.dispose);
    notifier.addFiles(['first.jpg', 'second.jpg']);
    notifier.beginSubmission();
    notifier.addFiles(['new.jpg']);
    notifier.finishSubmission(unsubmitted: ['second.jpg']);
    expect(notifier.state.filePaths, ['second.jpg', 'new.jpg']);
  });

  test('正常移除和清空保持原有语义', () {
    final notifier = PendingUploadNotifier();
    addTearDown(notifier.dispose);
    notifier.addFiles(['first.jpg', 'second.jpg']);
    notifier.removeFile('first.jpg');
    expect(notifier.state.filePaths, ['second.jpg']);
    notifier.clear();
    expect(notifier.state.filePaths, isEmpty);
    expect(notifier.beginSubmission(), isEmpty);
    expect(notifier.state.isSubmitting, isFalse);
  });
}
