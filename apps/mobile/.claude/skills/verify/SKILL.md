---
name: verify
description: Build, launch, and drive the Household Helper mobile app in the iOS simulator to verify changes at the UI surface.
---

# Verifying apps/mobile changes

## Launch (mock mode — no Supabase/Docker needed)

```bash
cd apps/mobile
EXPO_PUBLIC_USE_MOCK=1 CI=1 npx expo start --ios --clear > /tmp/expo.log 2>&1 &
```

- `CI=1` disables interactive keys (fine for driving via deep links); drop it if you want `r` to reload.
- Wait for `iOS Bundled` in the log (~1–2 min cold). Mock mode prints a
  `WARN [MOCK MODE]` banner — its presence/absence tells you which client is live.
- Real mode: same without `EXPO_PUBLIC_USE_MOCK`, needs `npx supabase start` first.
  Always pass `--clear` when switching modes (Metro caches inlined `EXPO_PUBLIC_*`).

## Observe

```bash
xcrun simctl io booted screenshot /tmp/shot.png   # then Read the png
```

## Drive (no tap tooling on this machine)

`cliclick`/`idb` are not installed and osascript lacks assistive access, so drive
navigation via deep links into Expo Go (host:port from the expo log):

```bash
xcrun simctl openurl booted 'exp://<LAN-IP>:8081/--/(app)/(tabs)'        # List tab
xcrun simctl openurl booted 'exp://<LAN-IP>:8081/--/shops'               # Shops tab
xcrun simctl openurl booted 'exp://<LAN-IP>:8081/--/settings'            # Settings tab
xcrun simctl openurl booted 'exp://<LAN-IP>:8081/--/shop/<shop-id>'      # shop detail
```

Gotcha: pass route-group parens raw — pre-encoding `%28` gets double-encoded and
lands on Unmatched Route. Seeded mock ids: `mock-shop-tj`, `mock-shop-costco`,
`mock-shop-pharmacy`; invite codes `MOCK1234` / `JOIN5678` (see `lib/mock/seed.ts`).

## Worth checking after a change

- Metro log tail for red errors (component errors surface there as `ERROR`).
- Mock data resets on full reload — reload to get a clean seed state.
- Flows that cover the client surface: add/toggle/delete list items, add shop,
  shop detail → "To list" → item appears on List tab (cross-screen realtime),
  Settings invite code, sign out → sign in.
