#include "clipboard_sync_bridge.h"
#include <windows.h>
#include <wincrypt.h>
#include <shlobj.h>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
std::filesystem::path StorePath() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &folder))) throw std::runtime_error("store");
  std::filesystem::path path(folder);
  CoTaskMemFree(folder);
  return path / L"RemoteSend" / L"clipboard_sync.dpapi";
}
std::string Protect(const std::string& input, bool decrypt) {
  if (input.size() > 300000) throw std::runtime_error("limit");
  DATA_BLOB in{static_cast<DWORD>(input.size()), reinterpret_cast<BYTE*>(const_cast<char*>(input.data()))};
  DATA_BLOB out{};
  const BOOL ok = decrypt ? CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)
                         : CryptProtectData(&in, L"RemoteSend clipboard sync", nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out);
  if (!ok) throw std::runtime_error("store");
  std::string result(reinterpret_cast<char*>(out.pbData), out.cbData);
  SecureZeroMemory(out.pbData, out.cbData); LocalFree(out.pbData);
  return result;
}
std::wstring Wide(const std::string& text) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) throw std::runtime_error("text");
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), length);
  return result;
}
std::string Utf8(const wchar_t* text, size_t count) {
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, static_cast<int>(count), nullptr, 0, nullptr, nullptr);
  if (length <= 0) throw std::runtime_error("text");
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, static_cast<int>(count), result.data(), length, nullptr, nullptr);
  return result;
}
struct ClipboardLock {
  explicit ClipboardLock(HWND window) { if (!OpenClipboard(window)) throw std::runtime_error("clipboard"); }
  ~ClipboardLock() { CloseClipboard(); }
};
void WriteClipboard(HWND window, const std::string& text) {
  if (text.empty() || text.size() > 32768 || text.find('\0') != std::string::npos) throw std::runtime_error("text");
  const auto wide = Wide(text);
  HGLOBAL data = GlobalAlloc(GMEM_MOVEABLE, (wide.size() + 1) * sizeof(wchar_t));
  if (!data) throw std::runtime_error("clipboard");
  auto target = static_cast<wchar_t*>(GlobalLock(data));
  if (!target) { GlobalFree(data); throw std::runtime_error("clipboard"); }
  memcpy(target, wide.c_str(), (wide.size() + 1) * sizeof(wchar_t)); GlobalUnlock(data);
  try {
    ClipboardLock lock(window);
    if (!EmptyClipboard() || !SetClipboardData(CF_UNICODETEXT, data)) throw std::runtime_error("clipboard");
    data = nullptr; // ownership transferred to the OS
  } catch (...) { if (data) GlobalFree(data); throw; }
}
bool MarkedPrivate() {
  if (IsClipboardFormatAvailable(RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing"))) return true;
  for (const auto* name : {L"CanIncludeInClipboardHistory", L"CanUploadToCloudClipboard"}) {
    HANDLE data = GetClipboardData(RegisterClipboardFormatW(name));
    if (data && GlobalSize(data) >= sizeof(DWORD)) {
      auto value = static_cast<const DWORD*>(GlobalLock(data));
      if (value) { const bool skip = *value == 0; GlobalUnlock(data); if (skip) return true; }
    }
  }
  return false;
}
V ReadClipboard(HWND window, DWORD own) {
  ClipboardLock lock(window);
  const bool internal = own != 0 && own == GetClipboardSequenceNumber();
  M meta{{V("kind"), V("unavailable")}, {V("internal"), V(internal)}};
  if (MarkedPrivate()) { meta[V("kind")] = V("sensitive"); return V(meta); }
  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) { meta[V("kind")] = V("non_text"); return V(meta); }
  HANDLE data = GetClipboardData(CF_UNICODETEXT);
  if (!data) return V(meta);
  const size_t capacity = GlobalSize(data) / sizeof(wchar_t);
  const auto* text = static_cast<const wchar_t*>(GlobalLock(data));
  if (!text) return V(meta);
  size_t count = 0; while (count < capacity && text[count]) ++count;
  std::string value;
  try { if (count > 0 && count <= 32768) value = Utf8(text, count); }
  catch (...) { GlobalUnlock(data); throw; }
  GlobalUnlock(data);
  if (count > 32768 || value.size() > 32768) { meta[V("kind")] = V("too_large"); return V(meta); }
  meta[V("kind")] = V(value.empty() ? "empty" : "text");
  meta[V("bytes")] = V(static_cast<int32_t>(value.size()));
  if (!value.empty()) meta[V("text")] = V(value);
  return V(meta);
}
} // namespace

ClipboardSyncBridge::ClipboardSyncBridge(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<V>>(messenger, "remote_send/clipboard_sync", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<V>& call, std::unique_ptr<flutter::MethodResult<V>> result) {
    try {
      const auto* args = call.arguments() ? std::get_if<M>(call.arguments()) : nullptr;
      auto text = [&]() -> std::string {
        if (!args) throw std::runtime_error("argument");
        const auto it = args->find(V("value"));
        if (it == args->end() || !std::holds_alternative<std::string>(it->second)) throw std::runtime_error("argument");
        return std::get<std::string>(it->second);
      };
      const auto& method = call.method_name();
      if (method == "load") {
        const auto path = StorePath();
        if (!std::filesystem::exists(path)) { result->Success(); return; }
        if (std::filesystem::file_size(path) > 300000) throw std::runtime_error("limit");
        std::ifstream file(path, std::ios::binary);
        if (!file) throw std::runtime_error("store");
        const std::string cipher((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        result->Success(V(Protect(cipher, true)));
      } else if (method == "save") {
        const auto value = text();
        if (value.size() > 262144) throw std::runtime_error("limit");
        const auto encrypted = Protect(value, false); const auto path = StorePath();
        std::filesystem::create_directories(path.parent_path()); auto temporary = path; temporary += L".tmp";
        { std::ofstream file(temporary, std::ios::binary | std::ios::trunc); file.write(encrypted.data(), static_cast<std::streamsize>(encrypted.size())); file.flush(); if (!file) throw std::runtime_error("store"); }
        if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) throw std::runtime_error("store");
        result->Success();
      } else if (method == "locked") {
        HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
        result->Success(V(desktop == nullptr)); if (desktop) CloseDesktop(desktop);
      } else if (method == "readClipboard") {
        result->Success(ReadClipboard(window_, last_write_));
      } else if (method == "writeClipboard") {
        WriteClipboard(window_, text()); last_write_ = GetClipboardSequenceNumber(); result->Success();
      } else if (method == "notifyClipboardReceived") {
        std::wstring device = L"another device";
        if (args) {
          const auto it = args->find(V("deviceName"));
          if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
            const auto& name = std::get<std::string>(it->second);
            if (!name.empty() && name.size() <= 128) device = Wide(name);
          }
        }
        ShowClipboardNotification(Utf8(device.c_str(), device.size()));
        result->Success();
      } else { result->NotImplemented(); }
    } catch (...) { result->Error("platform_failed", "Clipboard or encrypted storage operation failed"); }
  });
}

ClipboardSyncBridge::~ClipboardSyncBridge() {
  if (tray_icon_added_) {
    NOTIFYICONDATAW icon{};
    icon.cbSize = sizeof(icon);
    icon.hWnd = window_;
    icon.uID = 0x52;
    Shell_NotifyIconW(NIM_DELETE, &icon);
  }
}

void ClipboardSyncBridge::ShowClipboardNotification(const std::string& device_name) {
  if (!IsWindow(window_)) return;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window_;
  icon.uID = 0x52;
  if (!tray_icon_added_) {
    icon.uFlags = NIF_ICON | NIF_TIP;
    icon.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wcscpy_s(icon.szTip, L"RemoteSend");
    tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &icon) == TRUE;
  }
  icon.uFlags = NIF_INFO;
  wcscpy_s(icon.szInfoTitle, L"RemoteSend");
  auto message = L"Clipboard copied from " + Wide(device_name);
  if (message.size() >= std::size(icon.szInfo)) message.resize(std::size(icon.szInfo) - 1);
  wcscpy_s(icon.szInfo, message.c_str());
  icon.dwInfoFlags = NIIF_INFO;
  Shell_NotifyIconW(NIM_MODIFY, &icon);
  FLASHWINFO flash{sizeof(FLASHWINFO), window_, FLASHW_TRAY | FLASHW_TIMERNOFG, 3, 0};
  FlashWindowEx(&flash);
}
