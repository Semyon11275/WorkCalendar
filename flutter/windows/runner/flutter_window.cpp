#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <cstring>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  clipboard_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "workcalendar/image_clipboard",
      &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "copyRgba") { result->NotImplemented(); return; }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) { result->Error("args", "Invalid image"); return; }
    auto w = args->find(flutter::EncodableValue("width"));
    auto h = args->find(flutter::EncodableValue("height"));
    auto b = args->find(flutter::EncodableValue("bytes"));
    if (w == args->end() || h == args->end() || b == args->end()) {
      result->Error("args", "Missing image data"); return;
    }
    const auto* width = std::get_if<int32_t>(&w->second);
    const auto* height = std::get_if<int32_t>(&h->second);
    const auto* pixels = std::get_if<std::vector<uint8_t>>(&b->second);
    if (!width || !height || !pixels || *width <= 0 || *height <= 0 ||
        *width > 16000 || *height > 16000 ||
        pixels->size() != static_cast<size_t>(*width) * *height * 4) {
      result->Error("args", "Invalid dimensions"); return;
    }
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPV5HEADER) + pixels->size());
    if (!memory) { result->Error("memory", "Cannot allocate clipboard image"); return; }
    auto* header = static_cast<BITMAPV5HEADER*>(GlobalLock(memory));
    if (!header) { GlobalFree(memory); result->Error("memory", "Cannot lock image"); return; }
    std::memset(header, 0, sizeof(*header));
    header->bV5Size = sizeof(*header);
    header->bV5Width = *width;
    header->bV5Height = -*height;
    header->bV5Planes = 1;
    header->bV5BitCount = 32;
    header->bV5Compression = BI_BITFIELDS;
    header->bV5RedMask = 0x00ff0000;
    header->bV5GreenMask = 0x0000ff00;
    header->bV5BlueMask = 0x000000ff;
    header->bV5AlphaMask = 0xff000000;
    header->bV5CSType = LCS_sRGB;
    auto* dst = reinterpret_cast<uint8_t*>(header + 1);
    for (size_t i = 0; i < pixels->size(); i += 4) {
      dst[i] = (*pixels)[i+2]; dst[i+1] = (*pixels)[i+1];
      dst[i+2] = (*pixels)[i]; dst[i+3] = (*pixels)[i+3];
    }
    GlobalUnlock(memory);
    if (!OpenClipboard(GetHandle())) {
      GlobalFree(memory); result->Error("busy", "Clipboard is busy; try again"); return;
    }
    bool ok = EmptyClipboard() && SetClipboardData(CF_DIBV5, memory) != nullptr;
    CloseClipboard();
    if (!ok) { GlobalFree(memory); result->Error("copy", "Clipboard write failed"); return; }
    result->Success();
  });


  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  clipboard_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
