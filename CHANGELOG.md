# Changelog

## 2.3 — Fix the Groq connection test, and say why things fail

- **The connection test rejected working Groq keys.** It required the model to
  reply with the exact string `"ready"`. Claude's tool calling enforces a schema
  server-side so it always did; Groq's JSON mode guarantees *valid JSON* and
  nothing about its contents, so a perfectly good `{"status":"Ready"}` was
  reported as a failure. The test now checks what it was actually meant to
  check — that a well-formed object came back at all.
- **Failures now repeat the service's own explanation.** Model clients read the
  error body instead of collapsing every non-2xx into a generic message, via a
  new `HTTPClient.sendAllowingHTTPError` and a `LookupError.providerRejected`
  case. A retired Groq model previously surfaced as "Product not found — this
  product may have been removed", which is nonsense under an API key field. It
  now says what Groq said.
- The Groq settings footer notes that Groq retires model IDs periodically, since
  a stale ID is the most likely reason a valid key appears not to work.

## 2.2 — App icon

- iOS 27 app icon (added directly in Xcode).

## 5.3 — Assistant replies render properly

- **Markdown is now rendered instead of shown.** SwiftUI only parses markdown
  in string *literals*, so a reply held in a variable arrived with its asterisks
  visible — `**Aa**` rather than **Aa**. Assistant replies are now parsed into
  an `AttributedString`: bold, italic, code and links render, line breaks
  survive, headings become plain lines and `-` bullets become real ones. What
  the user typed is still shown exactly as typed.
- VoiceOver reads the resolved text rather than spelling out the punctuation
  around every bold word.
- **The compose field is Liquid Glass** — a floating rounded capsule that
  content scrolls beneath, rather than a flat bar pinned across the bottom.

## 5.2 — Prices know what currency they are in

Three gaps meant a price could be saved as a bare number, or in the wrong money.

- **A country domain now sets the currency.** It was only ever derived from an
  Amazon marketplace, so a price from johnlewis.com or argos.co.uk arrived with
  no currency at all and displayed as a plain number. Any country domain now
  implies its currency — `.co.uk` is pounds, `.de` is euros, and so on.
- **An Amazon marketplace is now decisive, not a hint.** Each Amazon storefront
  trades in exactly one currency, so a price read from amazon.co.uk is in
  pounds whatever symbol was scraped beside it. A stray "$" in a comparison
  table on the page can no longer make a price dollars.
- **One currency setting**, in Settings, used both for the budget and as the
  last resort when neither the page nor the domain says. It defaults to your
  region's currency, so a UK device starts in GBP.

Settled in one place for every provider, so the Amazon API, the third-party
reader, the page reader and the assistant all agree. None of it invents a
price — it only names one already found.

## 5.1 — Correct request shape for junglee/Amazon-crawler

The default Apify actor's request body was a guess (`startUrls` / `maxItems`)
made without access to the actor's own documentation, and it was wrong — the
actor rejected it outright. Corrected against the actor's real input schema:

- `startUrls` → `categoryOrProductUrls`
- `maxItems` → `maxItemsPerStartUrl`
- adds the actor's required `countryCode`, taken from the item's marketplace
- adds `scrapeProductDetails: true` and bounds `maxSearchPagesPerStartUrl` to 1,
  since a direct product link never needs to page through search results

`AmazonMarketplace` gains a `countryCode` (ISO 3166-1 alpha-2) alongside its
existing `currencyCode`, for readers that key on country rather than domain.

## 5.0 — Third-party Amazon readers

An optional middle path between Amazon's own API (free, but gated behind an
Associates account with tax identity and qualifying sales) and reading the
product page (free and keyless, but Amazon shows a human check often enough to
be annoying).

**No single service is hard-coded.** Three are offered — Apify, HasData, and a
Custom address for anything else — because their free allowances and response
shapes both change without notice, and this app has already been broken once by
a provider retiring something out from under it.

- **Every field is read through a list of candidate paths**, not one fixed
  shape, so a service returning `price.value` and one returning
  `product.price.raw` both work. Anything not found stays unavailable, exactly
  as elsewhere.
- **It sits second in the chain** — after Amazon's own API, before the free page
  reader — so the most authoritative configured source wins.
- **"Use for Price Refreshes" can be turned off.** Refreshing every item is what
  actually burns a metered allowance; with it off, adding items still uses the
  service and refreshes fall back to the page reader.
- **A local monthly request count** is shown in Settings, because these
  allowances fail quietly and nothing else in the app would tell you.
- Settings says plainly that this buys reliability rather than new data, and
  that free tiers change.

## 4.0 — Add by name, and a tougher link reader

### One field instead of two
The Add sheet had a Link field and a Name field, and asked the user to decide
which they were using. It now has one field that works out for itself whether
what you typed is an address or a description. The button reads **Fetch** or
**Search** accordingly.

### Adding by name, for free
There is no dependable, keyless product-search API — so Wishlist does not
pretend to have one. It asks the storefront you already shop at to search, and
reads the results page with the same free reader it uses everywhere else.

You get a list of real results with pictures and prices to choose from. Picking
one then runs the **ordinary lookup against that product's own page**, so an
item added by name is exactly as verified as one added from a link. If Amazon
answers with a human check instead of results, the app says so rather than
implying the product doesn't exist.

### Colour and size
Optional fields shown only when you are typing a name — a link already points
at one exact variant, so asking would be asking twice. They narrow the search
*and* are kept on the item, appearing in the list, on its screen, and in what
the assistant is told. Your wording always survives whatever the lookup returns.

### The link reader is harder to break
- **Pasting messy text now works.** "Look at this 👀 https://…" used to be
  rejected outright. Links are extracted with `NSDataDetector` — the same
  detector iOS uses to make links tappable — so share-sheet text, messages and
  quoted URLs all resolve.
- A bot-check page on a product URL is reported as what it is, instead of
  surfacing as "no details found" and blaming the product.

## 3.2 — Interface refinements

- **The decimal keyboard can be dismissed.** The price field in the item editor
  and the budget field in Settings use a decimal pad, which has no return key —
  so there was no obvious way out of the keyboard. Both now show a Done button
  in the keyboard toolbar, and only while that field is focused.
- **Edits are no longer lost to a stray swipe.** The item editor blocks
  interactive dismissal while there are unsaved changes, and Cancel asks before
  discarding — the standard iOS pattern, and the same one Contacts and Calendar
  use.
- **"Refresh Price" became "Update from Store"** and now fetches whatever the
  item is actually missing: a full lookup when headline details are absent, a
  price check when only the price needs re-reading. One action that does the
  right thing rather than two the user has to choose between.

## 3.1 — A leaner, fresher lookup chain

The chain now knows *why* it is running. Adding an item wants everything;
re-checking one already saved wants a price and nothing else.

- **Price checks skip providers that cannot price.** Microlink structurally
  never returns a price, so refreshing twenty items no longer makes twenty
  calls to it. Expressed as a `canProvidePrice` capability on the provider
  contract rather than a name check.
- **Refreshes bypass the HTTP cache.** A cached page reports the price you
  already have — which is precisely what a refresh exists to discover has
  changed. This was a correctness bug, not just a slow path.
- **Availability no longer gates completeness.** Plenty of legitimate product
  pages never state stock, and requiring it meant the chain ran every remaining
  provider on almost every *successful* lookup.
- **The whole chain has a deadline** — 20s adding, 12s refreshing — so four
  providers with a 15s timeout each can no longer add up to a minute of
  waiting. It returns what it has instead.
- The language model is never spent on a price check.

## 3.0 — Ask the assistant about products

A conversation with the assistant, from an item's menu ("Ask About This") or the
wishlist menu ("Ask the Assistant"): alternatives, whether a price looks
reasonable, what to check before buying, what people complain about.

- Grounded in what the app has **actually observed** for that item — the price
  it saw and when, the price when you added it, the availability it last read,
  your own note — so "is this a good price?" reasons from real data rather than
  from the product's name.
- The model is told plainly that it cannot browse, cannot check a live price,
  and must never claim something is in stock, discounted or discontinued.
- Nothing it says is written into an item, and the conversation is not saved.
  It is advice, not a record.
- One-tap opening questions when there is an item to discuss, because a blank
  box is a worse question than a specific one.
- Opening it without a key configured offers setup **inline** — pushed within
  the sheet rather than throwing the user at another tab, so they come straight
  back to the question they had.

## 2.2 — Groq models read from the provider

The shipped default Groq model, `llama-3.3-70b-versatile`, was deprecated by
Groq on 17 June 2026 and stopped being served in August 2026, so every request
failed with "model not available" even with a perfectly good key.

- The model list in Settings is now **read from your key** via Groq's models
  endpoint, rather than being a fixed string in the app. Non-chat models
  (speech, guard, embeddings) are filtered out. A text field remains as a
  fallback if the list can't be fetched, so a working key is never blocked.
- A stored model identifier that Groq has since retired is migrated to a
  current one on launch instead of failing on first use.
- The default moved to `openai/gpt-oss-120b`, one of Groq's own recommended
  replacements — but it is now a starting point rather than a promise.

## 2.1 — First build fixes

- `AppEnvironment`'s injectable dependencies are optional parameters resolved in
  the initialiser body rather than default parameter values. A default value is
  evaluated in a *nonisolated* context, so `SettingsStore()` and
  `NetworkMonitor()` — both main-actor isolated — could not legally be
  constructed there. Call sites are unchanged.
- Dropped a redundant `nonisolated(unsafe)` on `NetworkMonitor.monitor`;
  `NWPathMonitor` is already `Sendable`, so a nonisolated `deinit` can cancel it
  unaided.

## 2.0 — Collections, budget, price alerts

### Collections
Optional grouping — a room, a person, an occasion. Assigned in the item editor
or from an item's context menu, filtered from the wishlist's existing menu.
Collections are derived from the items themselves, so one stops existing the
moment nothing is in it, and there is no empty-folder housekeeping.

### Available to spend
Set an amount in Settings and the wishlist shows what you have left, gains a
"Within Budget" filter, and each item says where it stands against it. Only
compared when the currencies match. **Wishlist never changes the figure for
you** — marking something obtained does not silently spend it.

### Price drop alerts
A local notification when a refresh finds something cheaper than the last price
recorded for it. Only for drops actually observed, never a prediction.
Permission is requested when the toggle is turned on, not at launch, and a
denied permission is explained rather than silently ignored.

### Product photos
Tap the image on an item to open it full screen — double tap to zoom, drag to
move, share from the toolbar.

Also: the wishlist's summary line now reflects what is actually on screen, and a
filter that hides everything says so instead of pretending the wishlist is
empty.

## 1.1 — Navigation and clarity fixes

- **Navigating out of the Add sheet no longer races the dismissal.** "View
  Saved Item" and "Open Settings" used to push or switch tabs while the sheet
  was still animating away, which drops the transition. The sheet now records
  what it wants to happen and the presenting screen acts once it has closed.
- **An item deleted while its screen is open now leaves that screen.** The
  handler also used to be attached to the view being torn down, so it could
  never have run; it now lives on the container that outlives the item, and
  covers deletion from anywhere — including a swipe on the list behind.
- Obtained gains a running total in the list footer, matching the wishlist's.
- The Add sheet's name field is labelled "Name (Optional)" when a link is
  present, since that is exactly when it is optional.

## Unreleased

### Optional language-model assistant

Off by default. Adds a third stage to the lookup chain for pages no parser can
read, plus title tidying and category suggestions.

- Two providers behind one `LanguageModelClient` protocol — **Groq** (free tier)
  and **Claude** (paid; Opus 5, Sonnet 5 or Haiku 4.5, with per-token prices
  shown in Settings). Swift has no official Anthropic SDK, so Claude is reached
  over the Messages API through the app's own `HTTPClient`, as a forced tool
  call so the reply is structured by construction.
- **The no-fabrication rule is enforced in code, not in the prompt.** The model
  is asked for the price *as written* and the shop's *own words* about stock;
  `PriceParser` and `Availability.parse` do the interpreting. `SourceCheck` then
  verifies every returned value against the page's text — a price must have its
  digits present in the same order, a name its words, a brand and description
  verbatim — and discards whatever fails.
- Shortened titles may only lose words, never gain them; the retailer's full
  title is preserved on the item's screen as `fullName`.
- Categories come from a fixed list of 26 and are labelled as suggestions.
- Never runs during a price refresh, so saved items keep their names.
- A model failure never fails a lookup — the assistant is strictly additive.

## 1.0

First release. Save things you want to buy, let the app enrich them from the
retailer, and mark them obtained when they arrive.

Marketing version `1.0`, build `1`.

### Screens

- **Wishlist** — list with thumbnail, name, store, price, and price-change or
  stock status. Search, sort, pull-to-refresh, leading swipe to mark obtained,
  trailing swipe to delete or edit, context menus, and an undo banner after
  every reversible change.
- **Obtained** — history grouped by month, with move-back-to-wishlist and
  permanent delete.
- **Item detail** — large image, full metadata, notes, data provenance, and an
  always-visible primary action.
- **Add** — paste a link or type a name, watch honest per-stage progress, review
  what was found, then save.
- **Settings** — per-provider setup with live connection tests, preferences,
  image-cache control, JSON export, and destructive actions.

### Product lookup

Validate and canonicalise the URL (tracking parameters stripped, Amazon links
reduced to their ASIN), identify the retailer, then run a provider chain that
merges results field by field and stops once the snapshot is complete:

1. Amazon Product Advertising API v5 — AWS SigV4 signed on device, 21 storefronts
2. The product page itself — schema.org JSON-LD and Open Graph, plus Amazon's
   own markup for the pages that publish neither
3. Microlink — last resort for pages that refuse to be read directly

Every provider is free to use, and the app works with no keys configured at all.
The Amazon API is free of charge but needs an approved Associates account; the
other two need no key.

Every failure becomes a `LookupError` with a human title, a sentence of guidance
and a next step. Raw API errors never reach the user, and no field is ever
invented — anything that could not be retrieved is labelled as unavailable.

### Foundations

- Views depend on an observable repository; the repository depends on the
  `WishlistPersisting` and `ProductDataProvider` protocols.
- Persistence is an atomic JSON document with debounced writes and a
  `dateModified` field, so a CloudKit store can be added without a migration.
- API keys are stored in the Keychain; preferences in user defaults.
- Images are coalesced, downsampled with ImageIO, and cached in memory and on
  disk under an LRU budget.
- Dynamic Type with a stacked layout at accessibility sizes, VoiceOver labels
  that read as sentences, status never conveyed by colour alone, Reduce Motion
  support, and full Dark Mode.

### Known state

This release has not yet been compiled — it was written in an environment
without Xcode or a Swift toolchain. Build it before shipping.
