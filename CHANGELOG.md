# Changelog

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
