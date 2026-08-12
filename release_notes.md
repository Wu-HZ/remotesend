## What's Changed in v1.1.0

### 🎨 Icon & Branding
- Adaptive icon redesign (SVG-based, fills tablet icon area)
- Settings page footer logo with theme tint

### ✨ New Features
- Auto-sync persistence (survives app restart)
- Own messages on left layout option
- Portable mode as data-location picker dialog
- Config import/export (JSON sharing)
- Storage usage widget with clear button
- Server enable/disable toggle
- Server emoji icon picker
- Drag & drop with instant/pending modes
- Upload failure auto-fallback to pending page

### 🐛 Fixes & Polish
- Full English localization (no hardcoded Chinese left)
- Content max-width 700px, pending page same constraint
- NavigationRail adapts to screen width (tablet landscape)
- APK slimmed to 19.5MB (arm64 only + minify)
- Settings entry row height unified
- Error messages show HTTP status, URL, auth details
- Serialized init to avoid concurrent PROPFIND requests
- Windows window title changed to "RemoteSend"
- Copyright year now dynamic
