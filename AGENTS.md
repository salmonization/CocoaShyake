# AGENTS.md

Guidance for AI coding agents working on CocoaShyake.

## Project

CocoaShyake is the macOS client for Shyake, an end-to-end encrypted
mail system (ML-KEM-768, ML-DSA-65, ChaCha20-Poly1305). It is an
AppKit GUI in Objective-C, linking upstream libshyake unmodified from
the `shyake` git submodule. Read PLAN.md before design decisions; the
protocol contract is `shyake/docs/SPEC.md`.

## Build and test

No Xcode project and no XIB/storyboard: clang + make only, all UI
built in code.

```
make          # build/CocoaShyake.app, ad-hoc signed
make run      # build and launch
make test     # upstream test_crypto + tests/test_profile.m (headless)
make format   # clang-format src/ (never touches the submodule)
make clean
```

Testing note: `CFFIXED_USER_HOME` redirects Application Support
(profiles) but NOT NSUserDefaults, which cfprefsd keeps in the real
`io.github.salmonization.CocoaShyake` domain; clean it after
scratch GUI runs.

Prerequisites: Xcode Command Line Tools, Homebrew `liboqs` and
`openssl@3` (linked statically; the app needs neither at run time).
After cloning: `git submodule update --init`.

## Hard constraints

1. Never modify the `shyake` submodule; bump it to take upstream
   changes. Upstream lib sources are picked up by wildcard, plus
   upstream's `client/src/cli/drafts.c` compiled unmodified: drafts
   are never reimplemented here, so the format matches the CLI.
   Design baseline: upstream v0.4.0 (protocol level 3).
2. A profile is a directory. The CLI's own `~/.config/shyake` is
   used in place as the first profile; profiles created here live
   under `~/Library/Application Support/CocoaShyake/profiles/<name>/`.
   All stay byte-compatible with upstream; GUI state goes to
   NSUserDefaults only.
3. Data model follows Unix shyake semantics: Inbox/Sent are
   in-memory views refreshed manually (⇧⌘N); fetch decrypts into
   memory only; Save (ciphertext), Export (the ONLY plaintext-to-disk
   path) and Burn are explicit user actions.
4. Every window sets `restorable = NO`; text views that hold mail
   disable smart quotes/dashes, text replacement, spell checking and
   data detectors (PLAN §5).
5. All libshyake calls run on one serial dispatch queue; UI updates
   hop back to the main queue.
6. No Keychain, no notarization, no installer, no auto-update.
7. User-facing strings go through `NSLocalizedString`; en, zh-Hans
   and ja `.strings` are kept in sync.

## Code style

Objective-C/C per `.clang-format` (4-space indent, 80 columns,
Linux braces). Comments explain why; a short phrase may label a major
block. Commits: Conventional Commits, imperative, lowercase.
