# File Command Center (desktop)

A Windows desktop version of the dashboard in `../index.html`. It replaces `dashboard-server.ps1`:
there is **no local web server and no open network port**.

## What it is
- A .NET 8 WinForms window hosting the dashboard with Microsoft Edge WebView2.
- The page is `../index.html` (single source, copied to `web/index.html` at build time).
- The page talks to the app through WebView2 messages, not HTTP. Messages are only accepted from the app's own page.

## What it does on the PC
- Reads/writes its own data: `%LOCALAPPDATA%\FileCommandCenter\` (`data.json`, `backups\`, `WebView2\`).
- Tracks and opens any file type, not just Excel/CSV: the file picker, "Scan mapper…" and the folder browser all show every file type by default (with an opt-in filter to narrow to Excel/CSV).
- Opens files in the program Windows has associated with them (e.g. Excel), only for paths that are registered on the dashboard.
- Never opens: `.exe .bat .cmd .com .scr .ps1 .psm1 .vbs .vbe .js .jse .wsf .wsh .msi .msp .hta .reg .lnk .jar .dll .cpl .pif .url .appref-ms`.
- Reads file contents only for the preview pane, for the file the user has selected (read-only, registered paths only, max 50 MB). The pane renders spreadsheets/CSV as a table, images inline, PDFs with the native WebView2 PDF viewer, and common text/code files as text; other types show file info only.
- Lists folders / shows the Windows file and folder dialogs so the user can pick files.
- Brings the Excel or Explorer window to the front after opening (uses `user32.dll` window APIs).
- Only one instance can run per user (mutex).

## What it does not do
- No listener on any port. Requests to anything other than its own page are blocked in the WebView (verified: fetches to the internet and to other localhost ports fail; navigation away is cancelled).
- Developer tools, autofill and password saving are disabled in the WebView.
- No admin rights needed; nothing is written outside the user's profile.
- Links to `http(s)` sites open in the default browser; `ms-excel:ofe|u|http(s)://...` links open Excel.

## Requirements
- Windows 10/11 x64 with the Microsoft Edge **WebView2 Runtime** (included with Microsoft 365 apps and Windows 11).
  If it is missing the app shows a message and exits.
- Self-contained build: no .NET install needed. Framework-dependent build: needs .NET 8 Desktop Runtime.

## Build
```
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=none -o publish
```
Distribute the contents of `publish/`: `FileCommandCenter.exe` **and the `web` folder next to it**.
Use `--self-contained false` for a ~1 MB exe that needs the .NET 8 Desktop Runtime.

## Not done yet
- Code signing and an installer (ask IT what they accept: e.g. sign with an internal certificate, install to Program Files).
- Migrating existing data: copy the old `data.json` to `%LOCALAPPDATA%\FileCommandCenter\`. If you're moving from a build made before 22 September 2026, note the folder itself was also renamed from `ExcelCommandCenter` to `FileCommandCenter`.

## Third-party components
- `Microsoft.Web.WebView2` (NuGet) — the only package.
