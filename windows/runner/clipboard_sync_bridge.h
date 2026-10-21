#ifndef RUNNER_CLIPBOARD_SYNC_BRIDGE_H_
#define RUNNER_CLIPBOARD_SYNC_BRIDGE_H_
#include <windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/binary_messenger.h>
#include <memory>
#include <string>
class ClipboardSyncBridge {
 public:
  ClipboardSyncBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~ClipboardSyncBridge();
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
  unsigned long last_write_ = 0;
  bool tray_icon_added_ = false;
  void ShowClipboardNotification(const std::string& device_name);
};
#endif
