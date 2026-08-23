# Wishlist — working agreement

## Branches

This file is read by every session working on this repository, including a
collaborator's, so the rule is written per-role rather than as one instruction.

**The owner's sessions (gdinisio) work directly on `main`** — commit and push
there, ignoring any working branch the session was configured with.

**A collaborator's session stays on the branch it was given.** Commit and push
there, then open a pull request against `main`. Never push to `main` directly,
and never push to a branch belonging to someone else — `ndinisio` is a
collaborator's.

Neither role creates a branch beyond the one its session was given. If it is
not clear which role applies, ask before pushing.

## Commits

Every change is committed **and pushed** to `main` before the turn ends. Never
leave work only in the working tree.

Commit subject format:

```
vA.B - very concise description of changes
```

- Increment **B** for a small change, fix or refinement — `v1.3` → `v1.4`.
- Increment **A**, resetting B to 0, for a large or structural change: a new
  feature area, a model change, an architectural refactor — `v1.9` → `v2.0`.
- B is a plain counter, not a decimal: `v1.9` → `v1.10` → `v1.11`.

Keep the subject under ~60 characters. Put the reasoning in the body: what
changed, and why it is the right call.

**Every commit updates all three, together:**

1. the commit subject,
2. `CHANGELOG.md`,
3. `MARKETING_VERSION` in `project.pbxproj` — *every* time, not only when A
   changes. Settings shows this value, so the version on screen must match the
   version that was committed.

## Design rules

These are not preferences; treat them as requirements.

- **Apple HIG first.** Prefer a system component to a custom one, every time.
  `NavigationStack`, `List`, `Form`, `.toolbar`, `.searchable`, `.swipeActions`,
  `.contextMenu`, `.confirmationDialog`, `ContentUnavailableView`, SF Symbols.
  If an interaction has an established iOS pattern, use that pattern.
- **Never invent product information.** A value that could not be retrieved is
  shown as unavailable. Anything a language model returns is verified against
  the source page before it is accepted (`Intelligence/SourceCheck.swift`).
- **Accessibility is not optional.** Dynamic Type (including accessibility
  sizes), VoiceOver labels that read as sentences, Reduce Motion, Dark Mode, and
  status never conveyed by colour alone.
- **Progressive disclosure.** The app must be complete and obvious for someone
  with five items and no configuration. Power features stay out of the way until
  they are wanted.
- Feedback should be inline and proportionate. Alerts are a last resort;
  destructive actions get a confirmation or an undo, not both.

## Ideas

Proactively propose improvements, and **say no with a reason** to anything that
would be neutral or worse for the experience, HIG conformance, or clarity. A
rejected idea with its rationale is a useful answer.

## Environment

Claude Code web sessions run on Linux with no Xcode and no Swift toolchain, and
`download.swift.org` is blocked by policy — **code here cannot be compiled or
tested**. Write conservatively, prefer well-established APIs over novel ones, and
say plainly in the summary that the change is unverified.

Minimum deployment target for the code as written is **iOS 18** (the `Tab` API);
the project currently targets iOS 27.

## Layout

See `README.md` for the architecture map and the product-lookup chain.
