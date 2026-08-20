# Wishlist

**Version 1.0** — see [CHANGELOG.md](CHANGELOG.md).

A native iOS app for saving things you want to buy. Paste a link, Wishlist finds
the name, price, picture and availability, and keeps it until you get it.

Built entirely with first-party frameworks — SwiftUI, Observation, Foundation,
CryptoKit, Security, Network, ImageIO and OSLog. **There are no third-party
dependencies and nothing to install.** Open `Wishlist/Wishlist.xcodeproj` and
build.

---

## Setting up product lookup

Wishlist works out of the box with no keys at all, and gets better with them.
All configuration lives in **Settings**, and keys are stored in the iOS Keychain,
so they are entered once and never asked for again.

| Provider | Cost | Key needed | What it does |
| --- | --- | --- | --- |
| **Product page** | Free | None | Reads the structured data (schema.org JSON‑LD, Open Graph) that stores already publish, plus Amazon's own page markup. Works for most retailers. |
| **Amazon Product Advertising API** | Free — Amazon charges nothing per request | Access key, secret key, partner tag | Authoritative Amazon prices, stock and images. Requests are signed with AWS Signature V4 on device. Needs an approved [Amazon Associates](https://affiliate-program.amazon.com) account. |
| **Microlink** | Free tier, no key | None | Last-resort fallback for pages that refuse to be read directly; recovers a name and picture. A paid key can be added but is never required. |

**Every service Wishlist uses is free**, and the app is fully functional with no
keys at all. Nothing here bills per request.

For an Amazon link the chain runs **PA‑API → product page → Microlink**, merging
results field by field, and stops as soon as it has everything. For any other
retailer it goes straight to the product page.

The Amazon settings screen has a **Test Connection** button that sends one real
request, so you find out immediately whether the credentials work.

### Do I need to set anything up?

No. Out of the box Wishlist reads product pages directly, including Amazon's,
and that covers most retailers.

The one worthwhile addition is the **Amazon Product Advertising API**. It costs
nothing, and it is the only Amazon source that stays correct when Amazon changes
its page markup or serves a bot check instead of a product page. The catch is
eligibility rather than money: it requires an approved Amazon Associates
account, and Amazon expects qualifying sales to keep API access active. If you
can't get it, the free page reader still handles Amazon — just less reliably.

---

## Architecture

Each layer knows only the one below it, and every boundary is a protocol, so the
network and the store can be replaced or stubbed without touching a view.

```
Views (SwiftUI)
  └─ WishlistRepository        app state + wishlist rules  (@Observable, main actor)
       ├─ WishlistPersisting   protocol → FileWishlistStore | InMemoryWishlistStore
       └─ ProductLookupService the API chain
            ├─ URLValidator          validate, de-track, canonicalise, extract ASIN
            ├─ RetailerIdentifier    host → store
            ├─ ProductDataProvider   protocol → Amazon PA-API | Product page | Microlink
            ├─ StructuredDataParser  JSON-LD + Open Graph → ProductSnapshot
            ├─ AmazonPageParser      Amazon's own markup, for pages without JSON-LD
            └─ ProductSnapshot       normalised model, merged across providers
  └─ ImageLoader               coalesced downloads, downsampled decode, memory + disk cache
  └─ SettingsStore             preferences in defaults, credentials in the Keychain
```

| Folder | Responsibility |
| --- | --- |
| `Models/` | The normalised domain model. Prices are `Decimal`, dates are `Date`, status is an enum — nothing is stored as a string that isn't one. |
| `Networking/` | `HTTPClient` protocol and the one place HTTP status codes become `LookupError`. |
| `Enrichment/` | The lookup pipeline: validation, retailer identification, providers, parsing, merging. |
| `Persistence/` | `WishlistPersisting` protocol, atomic JSON file store, and the repository. |
| `Images/` | Download coalescing, disk cache with an LRU budget, ImageIO downsampling. |
| `Settings/` | Keychain wrapper, observable settings, and the settings UI. |
| `Views/` | SwiftUI only. No view constructs a URLSession or touches the Keychain. |

### Two rules the code holds to

1. **Nothing is invented.** If a provider cannot confidently return a price, a
   currency or an image, the field stays `nil` and the UI says "Not found"
   rather than showing a guess. Price history records only prices that were
   actually observed.
2. **Raw errors never reach the user.** Every failure becomes a `LookupError`
   with a human title, a sentence of guidance and a next step.

### Ready for iCloud

`WishlistPersisting` is a two-method protocol, and every item carries
`dateModified` for last-writer-wins merging. Adding sync means writing a second
conformance and injecting it in `AppEnvironment` — no model migration and no
changes to any view.

---

## Accessibility

- Dynamic Type throughout; list rows re-flow to a stacked layout at
  accessibility text sizes rather than shrinking.
- Status is never colour alone — availability and price changes always pair a
  symbol and a word.
- Rows combine into one sensible VoiceOver sentence ("Sony WH‑1000XM5, from
  Amazon, £249.00, £40.00 less than when you added it"); swipe actions surface
  as VoiceOver custom actions.
- Decorative thumbnails are hidden from assistive technology; the detail image
  carries a real description.
- Reduce Motion removes the banner and image transitions.
- Full Dark Mode via system colours and materials.

---

## Optional things to do in Xcode

None of these are required — the app builds and runs as it is.

1. **App icon** — drop yours into `Assets.xcassets/AppIcon.appiconset`.
2. **Share Extension** (recommended next step) — File → New → Target → Share
   Extension would let you add items straight from Safari's share sheet. It
   needs an App Group so the extension and app share the same store; the
   persistence layer is already behind a protocol, so only
   `FileWishlistStore`'s directory would change.
3. **iCloud sync** — add the iCloud capability with CloudKit, then add a
   `CloudKitWishlistStore: WishlistPersisting` alongside the file store.
4. **Deployment target** — the project is set to iOS 27. The code needs
   **iOS 18 or later** (the `Tab` API in `TabView`); everything else is iOS 17.
   Lowering it to 18.0 in the target's build settings is safe.

## Requirements

- Xcode 27 or later
- iOS 18 or later (project currently targets iOS 27)

## Version

1.0 (`MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`). Release notes
are in [CHANGELOG.md](CHANGELOG.md).
