# Wishlist

**Version 7.5** — see [CHANGELOG.md](CHANGELOG.md).

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
| **Amazon data service** (optional) | Bring your own key; free allowances vary and change | API key | A third-party reader for Amazon — Apify, HasData, or any custom endpoint. Buys reliability against Amazon's human checks, not data the page reader cannot get. |
| **Microlink** | Free tier, no key | None | Last-resort fallback for pages that refuse to be read directly; recovers a name and picture. A paid key can be added but is never required. |
| **Assistant** (optional) | Groq free tier, or Claude paid | API key | Reads pages no parser can handle, shortens keyword-stuffed titles, and suggests categories. Off by default. See below. |

**Every service Wishlist uses is free**, and the app is fully functional with no
keys at all. Nothing here bills per request.

For an Amazon link the chain runs **PA‑API → third-party reader → product page → Microlink**, merging
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

## The optional assistant

Some retailers publish no structured data, no Open Graph tags and no markup an
app can recognise — but a person looking at the page can still see the name and
the price. Turning on **Settings ▸ Assistant** lets a language model read those
pages. It is off by default.

Choose **Groq** (free tier, Llama models) or **Claude** (paid; Opus 5, Sonnet 5
or Haiku 4.5, with per-token prices shown next to each). Keys go in the
Keychain like every other credential.

### How it stays honest

The app's first rule is that it never invents product information, and adding a
language model does not get to change that. Three things enforce it:

1. **The model is a locator, not an author.** It is asked for the price *exactly
   as written* — `"£249.00"`, not a number — and for the shop's own words about
   stock, not a verdict. Wishlist's own `PriceParser` and `Availability.parse`
   then interpret those strings, so every judgement stays in code you can read.
2. **Every answer is checked against the page.** A returned price is accepted
   only if its digits appear in the page's text in the same order; a name only
   if its words are there; a brand, a stock phrase and a description only if
   they appear verbatim. Anything that fails is discarded, not shown. A model
   that hallucinates a price therefore changes nothing.
3. **Shortened titles may only ever lose words.** Every word of a shortened
   title must already appear in the retailer's own title, or the original is
   kept. The full title is always preserved and shown on the item's screen.

Categories are the one suggestion rather than a lifted fact — they come from a
fixed list of 26, and are labelled as suggestions in Settings.

### Asking about products

The assistant also answers questions — alternatives, whether a price looks
reasonable, what to check before buying — from an item's menu ("Ask About
This") or the wishlist menu ("Ask the Assistant").

This is a **different contract** from page reading, and the code treats it as
one. Extraction reports facts about a page and every value is verified before
the app believes it. Advice cannot be verified, so instead:

- The model is told plainly that it cannot browse, cannot check a live price
  and must never claim something is in stock or on sale.
- It is grounded in what the app has actually observed for that item — the
  price it saw and when, the price when you added it, the stock status it last
  read — so "is this a good price?" reasons from real data.
- Nothing it says is ever written into an item. The conversation is not saved:
  it is advice, not a record, and keeping it would imply the app stands behind
  it.
- The caveat sits under the compose field on every screen of the conversation.

### What leaves the device

For page reading: only the text of the page being added, and its link — and
only when a parser has already failed, or a title needs shortening. For a
conversation: your question, and the recorded details of the one item you are
asking about. Your wishlist as a whole is never sent. The
assistant never runs during a price refresh, so an item keeps the name you saved
it under.

---

## Architecture

Each layer knows only the one below it, and every boundary is a protocol, so the
network and the store can be replaced or stubbed without touching a view.

```
Views (SwiftUI)
  └─ WishlistRepository        app state + wishlist rules  (@Observable, main actor)
       ├─ WishlistArchive      items + the named wishlists they belong to
       ├─ WishlistPersisting   protocol → FileWishlistStore | InMemoryWishlistStore
       └─ ProductLookupService the API chain
            ├─ URLValidator          validate, de-track, canonicalise, extract ASIN
            ├─ RetailerIdentifier    host → store
            ├─ ProductDataProvider   protocol → Amazon PA-API | Product page | Microlink
            ├─ LanguageModelClient   protocol → Claude | Groq   (optional, off by default)
            ├─ SourceCheck           verifies every model answer against the page
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
| `Persistence/` | `WishlistPersisting` protocol, atomic JSON file store, and the repository. It reads and writes a `WishlistArchive` — items plus the named wishlists — and decodes tolerantly so an older archive still opens. |
| `Images/` | Download coalescing, disk cache with an LRU budget, ImageIO downsampling. |
| `Intelligence/` | The optional model layer: two clients behind one protocol, the extractor, the title/category polisher, and the verification that gates all of it. |
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

`WishlistPersisting` is a two-method protocol over a single `WishlistArchive`,
and every item carries `dateModified` for last-writer-wins merging. Adding sync means writing a second
conformance and injecting it in `AppEnvironment` — no model migration and no
changes to any view.

---

## Adding an item

One field takes either a link or a name; the app decides which it is.

**From a link** — the address is extracted from whatever you paste, including
surrounding text, then read through the provider chain.

**From a name** — there is no dependable free product-search API, so Wishlist
doesn't pretend to have one. It asks your Amazon storefront to search, parses
the results page with the same free reader used elsewhere, and shows you real
results with pictures and prices. Choosing one runs the normal lookup against
that product's own page, so a name-added item is exactly as verified as a
link-added one. Optional **colour** and **size** narrow the search and stay with
the item.

When a store answers with a human check instead of a page, that is reported as
what it is rather than as a missing product.

## Organising and budgeting

**Pinning** floats the things you want most, or soonest, into their own section
at the top, under a "Pinned" heading, with everything else under its own
heading below it — pin from a swipe or the context menu. An item's own screen
says when it is pinned. Marking something obtained
unpins it automatically, since the question a pin asks has been answered. A
count and total sit at the end of the list, after what they summarise.

**Obtained items are struck through**, on the row and on their own screen, so
the state is legible without relying on colour. Marking something obtained — or
putting it back on the wishlist — closes its screen, since the item has left the
list that screen was opened from.


**Wishlists** are lists you create and name — "Tech", "Back to School", a room,
a person, an occasion. Each has a name and an SF Symbol, and exists whether or
not anything is on it yet. Switch between them from the leading toolbar item;
the navigation title is always the list you are looking at, and new items join
it. Move an item from its context menu, its editor or its detail screen.

Deleting a wishlist keeps its items — they stop belonging to a list rather than
disappearing. Collections from earlier versions are migrated into real
wishlists once, on first load.

**Available to spend** is an amount you set in Settings. The wishlist then shows
what is left, offers a "Within Budget" filter, and each item says whether it
fits. Comparisons only happen when currencies match. The figure is never changed
for you — obtaining something does not silently spend it, because quietly moving
someone's money is not a thing an app should do.

**Price drop alerts** post a local notification when a refresh observes a price
lower than the one previously recorded. Permission is asked for when the toggle
is switched on. Alerts currently fire when a refresh runs with the app open;
adding a Background App Refresh capability in Xcode would let them fire on their
own — see below.

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

1. **Share Extension** (recommended next step) — File → New → Target → Share
   Extension would let you add items straight from Safari's share sheet. It
   needs an App Group so the extension and app share the same store; the
   persistence layer is already behind a protocol, so only
   `FileWishlistStore`'s directory would change.
2. **iCloud sync** — add the iCloud capability with CloudKit, then add a
   `CloudKitWishlistStore: WishlistPersisting` alongside the file store.
3. **Background price checks** — the price-drop alerts work from any refresh
   while the app is open. To have them run on their own, add the Background
   Modes capability with *Background fetch*, register a `BGAppRefreshTask`, and
   call `repository.refreshPrices()` from it. Everything else is already in
   place.
4. **Deployment target** — the project is set to iOS 27, which is higher than
   the code needs. The real floor is **iOS 26.0**, set by `.glassEffect` on the
   assistant's composer and send button; below that the next constraint is the
   `Tab` API in `TabView` at iOS 18, and everything else is iOS 17 or earlier.
   Lowering the target to 26.0 costs nothing. Going below 26 does not degrade
   gracefully — `.glassEffect` would fail to compile and would need an
   `#available` guard first. Note that a device running iOS 26.x cannot be used
   as a run destination while the target says 27.

## Requirements

- Xcode 27 or later
- iOS 18 or later (project currently targets iOS 27)

## Version

1.0 (`MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`). Release notes
are in [CHANGELOG.md](CHANGELOG.md).
