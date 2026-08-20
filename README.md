# Wishlist

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

| Provider | Key needed | What it does | Where to get it |
| --- | --- | --- | --- |
| **Product page** | None | Reads the structured data (schema.org JSON‑LD, Open Graph) that stores already publish. Works for most retailers. | Built in, on by default |
| **Amazon Product Advertising API** | Access key, secret key, partner tag | Authoritative Amazon prices, stock and images. Requests are signed with AWS Signature V4 on device. | Amazon Associates → Tools → Product Advertising API |
| **Rainforest** | API key | Amazon product data without Associates credentials — the practical option if you can't get PA‑API access. | [rainforestapi.com](https://www.rainforestapi.com) |
| **Microlink** | Optional key | Last-resort fallback for pages that refuse to be read directly; recovers a name and picture. | [microlink.io](https://microlink.io) |

For an Amazon link the chain runs **PA‑API → Rainforest → product page →
Microlink**, merging results field by field, and stops as soon as it has
everything. For any other retailer it goes straight to the product page.

Each provider screen has a **Test Connection** button that sends one real
request, so you find out immediately whether a key works.

### Which one should I start with?

If you buy mostly from Amazon and can get Associates credentials, use the
**Product Advertising API** — it is the only source that stays correct when
Amazon changes its page markup, and it costs nothing. If you can't (it requires
an approved Associates account with qualifying sales), add a **Rainforest** key
instead. With neither, everything still works — Amazon product pages are just
less reliable to read than most other retailers'.

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
            ├─ ProductDataProvider   protocol → Amazon PA-API | Rainforest | Product page | Microlink
            ├─ StructuredDataParser  JSON-LD + Open Graph → ProductSnapshot
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
