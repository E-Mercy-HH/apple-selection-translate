<p align="center">English | <a href="zh-CN/">简体中文</a></p>

# Apple Selection Translate

<img src="Resources/AppIcon-1024.png" alt="Apple Selection Translate icon" width="128">

Select English or Chinese text with the mouse in another Mac app. A translation appears near the cursor automatically, using the macOS Translation framework.

## Features and cost

- Translates between English and Simplified Chinese in either direction. The popup sizes itself to the result and scrolls for longer text. The menu bar menu can pause monitoring and open settings.
- Uses Apple-managed on-device translation models. No translation account, API key, subscription, or per-request paid service is needed. macOS may ask to download language models on first use.
- Shows the translation without replacing the source text or writing to the clipboard. This is sentence translation, not the macOS Dictionary definition UI.

## Requirements and build

- An Apple Silicon Mac running **macOS 26.4 or later**. The current build targets `arm64` only; Intel Macs and earlier macOS versions are unsupported.
- Xcode/developer tools with a compatible macOS SDK. The app is written in Swift 6 with SwiftUI, AppKit, and system frameworks. The build script calls `swiftc` directly and has no SwiftPM or third-party dependency.

From the repository root:

```sh
./build.sh
open dist/AppleSelectionTranslate.app
```

If the selected developer tools do not find a compatible SDK, set `MACOS_SDK_PATH` to an installed SDK path before building. The icon is included. To change it, edit [the icon source](tools/render_icon.swift), run `./tools/generate_icon.sh`, then rebuild the app.

## First run and usage

1. Move the `.app` to its intended long-term location before granting access. Launch it and click “请求授权” (Request Access). In System Settings → Privacy & Security, allow the app to use Accessibility. The category name varies by macOS version; on the tested macOS 27 system it appears as “设备控制和数据访问” (Device Control and Data Access). Return to the app and click “重新检查并开始” (Recheck and Start). Each Mac needs its own grant.
2. Click “准备英中双向翻译” (Prepare English–Chinese Translation) in the same window. Approve the macOS language download and wait until the window says both directions are ready.
3. Drag to select text, double- or triple-click a word, or Shift-click to extend a selection in another app. The popup opens automatically when the selection is complete. Use “设置与语言包…” (Settings and Language Packs) in the menu bar to reopen setup.

## Known issues and functional boundaries

- **Access may be lost after a rebuild.** `build.sh` uses ad-hoc signing. When the code changes, macOS may no longer recognize the build as the app previously authorized, even if its permission switch still looks enabled. Quit the app, remove its old permission entry, add and enable the current `.app`, then relaunch and recheck. The current build is neither Developer ID signed nor notarized; no ready-to-distribute notarized installer is provided. See [Apple's explanation of ad-hoc code identity](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
- Automatic activation recognizes mouse drags, double/triple clicks, and Shift-clicks. A single click, keyboard-only selection, or global hotkey does not trigger it. An unchanged prior selection is not shown repeatedly; if an app does not expose the selection range, select different text before translating the same passage again.
- It only reads **currently selected text** exposed by the frontmost app through macOS Accessibility. Some browser pages, terminals, document readers, or custom controls may not expose it, so no popup appears. There is no screenshot, OCR, or clipboard-copy fallback. Cross-app compatibility has not been comprehensively tested.
- Setup prepares **English ↔ Simplified Chinese** only. Recognized Traditional Chinese is attempted, but macOS may reject that language pair. Other languages are unsupported. Very short text, Han characters shared by both Chinese scripts, and mixed-language text can be misidentified; try a longer selection in one language.
- Oversized selections are ignored: limits are 5,000 Swift characters, 10,000 UTF-16 units, and 20,000 UTF-8 bytes. Translation quality and model/language availability depend on macOS. The app UI is currently in Simplified Chinese only.

## Privacy and permissions

Accessibility is a broad system permission. This app reads the focused, frontmost element's selected text only after the listed mouse gestures and rejects secure text fields. It does not read an entire input field, save translation history, or read or modify the clipboard; the app source makes no direct network requests. Sensitive text that you deliberately select still enters the app's memory and the system translation flow. You can pause monitoring from the menu bar or revoke access in System Settings. [Apple states](https://developer.apple.com/documentation/translation/translationsession) that `TranslationSession` processes source and translated text on-device, while Apple may collect API usage and performance metrics without the text content.

For the reviewed source scope and remaining risks, see the [security review](SECURITY_REVIEW.md) (Chinese).

## License

This project is licensed under the [MIT License](LICENSE).
