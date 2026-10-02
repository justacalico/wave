# Wave

A quiet browser. Vertical tabs, workspaces that tint themselves, and Firefox
Account sign-in — built in Flutter on top of the webview your OS already
ships, the same way Tauri does it.

## Highlights

- **Vertical tab sidebar** with pinned tabs, essentials, and per-workspace
  tab sets. Collapses to a 52px icon rail (Ctrl+Shift+B).
- **Workspaces** — named contexts, each with its own accent colour. Tabs,
  essentials and pins stay in their workspace.
- **Split view** — two pages side by side (tab context menu → split).
- **Omnibox** — search or URL, live history/bookmark suggestions, bangs:
  `!g` `!ddg` `!br` `!b` `!w` `!gh` `!yt` `!mdn`.
- **Reader mode** — distilled article view with adjustable type size.
- **Find in page** (Ctrl+F), tab sleep, per-tab private mode.
- **Password vault** — AES-256-GCM, unlocked by Firefox Account or a master
  password, with form autofill and capture prompts.
- **Firefox Accounts** — real OAuth2 + PKCE sign-in, profile, device record,
  and the sync-1.5 transport (tokenserver + Hawk + encrypted BSOs). When a
  client id holds the `oldsync` scope, Wave syncs with real Firefox profiles.
  Otherwise point it at a self-hosted relay or FxA stack — one setting.
- **Full keyboard** — Ctrl+T/W/L/R/F/B/H/J/D, Ctrl+Tab, Ctrl+1..9,
  Alt+←/→, Ctrl+Shift+P for private.

## Engines

| Platform | Engine | Why |
|---|---|---|
| Linux | WebKitGTK | system webview, docked as a companion window |
| Windows | WebView2 | Edge runtime, already installed |
| macOS / iOS | WKWebView | WebKit, sandboxed by the OS |
| Android | Android WebView | Chromium, updated by Play system |
| Web | — | builds as a landing page only |

## Build

```bash
flutter pub get
flutter run -d linux        # or windows / macos / android / ios
flutter build web           # landing page only
```

Linux needs `webkit2gtk-4.1` dev files (`pacman -S webkit2gtk-4.1`,
`apt install libwebkit2gtk-4.1-dev`).

## Firefox Account setup

Wave needs an OAuth client id to sign in. Mozilla grants these through the
FxA ecosystem partner program; for development or self-hosting, point
Settings → Firefox Accounts at your own `fxa` deployment. Compile-time:

```bash
flutter run --dart-define=FXA_CLIENT_ID=your_client_id
```

## Releases

Binaries for every platform land on the
[GitLab releases page](https://gitlab.com/HttpAnimations/wave/-/releases);
the pipeline builds on GitHub and syncs artifacts back so they never expire.
iOS installs via the
[AltStore source](https://wave-d26c57.gitlab.io/altstore/apps.json).

## License

AGPL-3.0 — see [LICENSE](LICENSE).
