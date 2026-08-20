# Changelog

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
2. Rainforest API — Amazon data without Associates credentials
3. The product page's own schema.org JSON-LD and Open Graph data — no key needed
4. Microlink — last resort for pages that refuse to be read directly

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
