# Emberdeck

A native iOS flashcard app: Anki's spaced repetition with Duolingo's streak loop
on top. Imports real `.apkg` decks, schedules with SM-2, and nags you with
genuine iOS notifications.

Everything stays on the device. No account, no server, no analytics.

---

## Getting it onto your phone

The repo builds an app; getting an app onto an iPhone always means signing it
with an Apple ID. Three routes, cheapest first.

### 1. You have a Mac

```bash
open Emberdeck.xcodeproj
```

In Xcode: select the **Emberdeck** target → **Signing & Capabilities** → tick
*Automatically manage signing* → pick your personal team (a free Apple ID works)
→ change the bundle identifier to something unique to you, e.g.
`com.sadaf.emberdeck` → plug the phone in and hit Run.

A free Apple ID gives a **7-day** provisioning profile and a limit of three
sideloaded apps. Re-run from Xcode once a week, or pay the $99/year Developer
Program for a one-year profile.

### 2. You don't have a Mac — build the IPA in CI

Push this folder to a GitHub repository. `.github/workflows/build-ipa.yml`
builds it on a macOS runner and uploads **`Emberdeck-unsigned.ipa`** as a
workflow artifact (Actions tab → the run → Artifacts).

```bash
git init && git add . && git commit -m "Emberdeck"
gh repo create emberdeck --private --source=. --push
gh run watch          # then download the artifact from the Actions tab
```

That `.ipa` is unsigned, so iOS won't install it directly. Sign it on-device
with **[SideStore](https://sidestore.io)** or **AltStore**: both take an
unsigned `.ipa`, sign it with your own Apple ID, and refresh it before the
7-day profile expires. Install the AltServer/SideStore pairing once, then
feed it the `.ipa`.

The workflow also builds for the iPhone 16 Pro Max simulator on every push,
which is a cheap check that the thing still compiles.

### 3. Someone else's Mac, once

`xcodebuild archive` + `ExportOptions.plist` (already in the repo) produces a
signed `.ipa` in one command if you have a certificate:

```bash
xcodebuild -project Emberdeck.xcodeproj -scheme Emberdeck \
  -configuration Release -archivePath Emberdeck.xcarchive archive
xcodebuild -exportArchive -archivePath Emberdeck.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath dist
```

---

## Requirements

- iOS 17.0 or later (SwiftData and `@Observable` are the floor)
- Xcode 16 or later — the project uses file-system synchronised groups, so
  **new files are picked up just by dropping them in `Emberdeck/`**; there is no
  file list to maintain in the project.
- On older Xcode: `brew install xcodegen && xcodegen generate` regenerates the
  project from `project.yml`.

No third-party packages. ZIP, SQLite and the scheduler are all first-party code
or system frameworks.

---

## How it's laid out

```
Emberdeck/
├─ EmberdeckApp.swift          app entry, model container, scene phase
├─ Models/
│  ├─ Models.swift             Deck + Card (SwiftData), day arithmetic
│  └─ Scheduler.swift          SM-2: answering, previews, fuzz
├─ Store/
│  ├─ Profile.swift            XP, streak, freezes, achievements, settings
│  ├─ AppModel.swift           owns profile/settings, builds the study queue
│  ├─ StudySession.swift       one run through a queue
│  ├─ Notifications.swift      the rolling fortnight of local reminders
│  └─ Backup.swift             JSON export/restore of everything
├─ Importers/
│  ├─ ZipArchive.swift         read-only ZIP over Apple's Compression framework
│  ├─ SQLiteDatabase.swift     thin wrapper on system SQLite
│  ├─ Importers.swift          .apkg reader + CSV/TSV reader
│  └─ MediaStore.swift         images extracted from decks, on disk
│  ├─ AudioEngine.swift        chimes, card audio, text-to-speech
│  └─ WidgetBridge.swift       writes the snapshot the widget reads
├─ Views/                      Theme, Today, Study, Decks, Progress, Settings
└─ Resources/
   ├─ SeedDecks.swift          two starter decks for a fresh install
   ├─ Sounds/                  six synthesised .wav effects
   └─ Assets.xcassets          app icon, accent colour
EmberdeckWidget/               WidgetKit extension (its own target)
```

### Scheduling

`Scheduler` is pure functions over a `Card` — nothing in it touches SwiftData or
the UI, so it's the easy piece to test or replace. It implements the SM-2
variant Anki ships:

- learning steps 1m → 10m, graduating at 1 day, Easy straight to 4 days
- ease factor in permille, starting at 2500, moving −200/−150/+150 per answer
  and clamped to 1300…5000
- a lapse drops the interval to the minimum, sends the card to relearning, and
  costs 200 ease
- half the overdue time counts as extra study value on a Good answer
- intervals are fuzzed ±5–25% so cards learned together don't stay clumped

Swap in FSRS by rewriting `Scheduler.answer` and `Scheduler.preview`; the fields
on `Card` (`interval`, `ease`, `reps`, `lapses`, `state`) are a superset of what
FSRS needs apart from difficulty/stability, which would be two more properties.

### The streak layer

`AppModel.award` is the single place XP is granted. A day counts once
`todayStat.xp` reaches `settings.dailyGoal`. Miss a day and `reconcileStreak`
spends a **streak freeze** to bridge it — one earned every seventh day, two
maximum. Days roll over at 4am local time (`DayMath`), the same convention Anki
uses, so a 1am session still counts for the previous day.

### Notifications

iOS can't decide at fire time whether a notification is still wanted. So instead
of one repeating trigger, `NotificationManager` lays down 14 days of one-shot
notifications and rewrites the whole set every time the app opens or the goal is
met — today's is dropped the moment you hit your target. There's a second,
time-sensitive "streak at risk" series at 21:30 that only appears once a streak
is worth saving.

### Both directions

A deck's **Study both directions** switch creates a reverse twin for every
card (`Deck.ensureReverseCards`), sharing a `noteKey` but scheduled
independently — exactly what Anki's *Basic (and reversed card)* note type does.
`AppModel.spaceSiblings` keeps the two directions of one note from appearing
back to back in a session. Switching it off hides the reverse cards without
losing their progress.

### Sound

`AudioEngine` handles three things through the ambient audio session (silent
switch respected, music keeps playing):

- **Effects** — six short chimes in `Resources/Sounds/`, synthesised rather
  than sampled, so they're tiny and licence-free: correct, wrong, flip, combo,
  session complete, streak advanced.
- **Card audio** — `[sound:file.mp3]` tags survive import (`MediaStore` keeps
  mp3/m4a/wav/aac/flac; `.ogg` is skipped because iOS can't decode it) and
  play automatically when the side they're on is shown.
- **Speech** — for cards with no recording, `AVSpeechSynthesizer` reads the
  foreign side in the language set on the deck. Free, offline, and the
  starter decks come with German and Spanish preset.

### Undo, leeches, multiple choice

- **Undo** (`StudySession.undo`) is one level deep and restores everything the
  answer touched: the card's scheduling, the XP/streak bookkeeping (the whole
  `Profile` is snapshotted — it's small), and the session counters. The card
  comes back with its answer showing so it can be regraded.
- **Leeches** follow Anki's rule in `applyLeechRule`: a card that lapses
  `leechThreshold` times (default 8) is tagged `leech` and suspended, then again
  every half-threshold. Suspended cards drop out of `Deck.activeCards`; the deck
  screen lists them and can bring them back in one tap.
- **Multiple choice** appears only for a card's very first showing
  (`state == .new && reps == 0`). Three distractors are drawn from the same
  deck and direction; picking auto-grades Good or Again. It needs at least
  four distinct answers in the deck, otherwise the card falls back to a plain
  reveal. Off switch in Settings.

### Widget

`EmberdeckWidget/` is a second target: a WidgetKit extension with small,
medium, and Lock Screen (circular, rectangular) families showing the streak,
today's goal and the due count. The app writes a `WidgetSnapshot` into the
**App Group** `group.com.emberdeck.shared` after every session and on launch
(`WidgetBridge.publish`), then asks WidgetKit to reload.

The widget reads its data through that App Group, which is an entitlement.
Building from Xcode with your own team sets it up automatically (free
personal teams support App Groups). **Sideloading the unsigned CI build** is
the one place it can bite: AltStore/SideStore re-sign with their own
entitlements and may rename or drop the group. If the widget shows "Open
Emberdeck once" forever, that's why — the app itself is unaffected.

### Importing

`.apkg` is a ZIP holding a SQLite database. `ZipArchive` reads the central
directory and inflates entries through `COMPRESSION_ZLIB`, which is raw DEFLATE
— exactly what ZIP stores — so there's no dependency. `ApkgImporter` then reads
`notes`, `cards` and the deck names, coping with both the modern `decks` table
and the older JSON blob on `col`.

**Known limits, by design:**

- Emberdeck doesn't run Anki's card templates. A note becomes **one** card:
  front = first field, back = the rest joined. A note that generates recognition
  + recall + cloze cards in Anki arrives here as one card.
- Cloze deletions are shown in bold rather than blanked out.
- `collection.anki21b` (Anki's newer zstd-compressed export) is rejected with a
  message telling you to re-export with *Support older Anki versions* ticked.
  Adding zstd would mean a dependency; see "Ideas" below.
- Images and playable audio import from classic-format decks; `.ogg` is skipped.

---

## Ideas, roughly in order of value

1. **Typed answers**, with a diff of what was wrong. Duolingo's core mechanic;
   fixes "I *thought* I knew it". Slots in beside the multiple-choice footer.
2. **FSRS instead of SM-2.** Measurably better retention per review. Contained
   to `Scheduler`.
3. **zstd, for modern `.apkg`.** Add a zstd package via SPM and decompress
   `collection.anki21b` in `ApkgImporter.parse` — the branch that currently
   throws `.zstdUnsupported` is where it plugs in.
4. **`.ogg` audio.** Many shared decks use it; iOS won't decode it. Either
   transcode on import with a small Vorbis decoder package, or convert on the
   desktop before exporting.
5. **Card templates**, so a note can generate several cards properly. This is
   the biggest change: it needs the `notetypes`/`templates` tables and a
   `{{Field}}` renderer.
6. **iCloud sync.** `ModelConfiguration` takes a CloudKit container; the models
   are already CloudKit-shaped (every property has a default, no uniqueness
   constraints). Needs a paid developer account.
7. **Tests.** There is no test target yet. `Scheduler`, `DayMath`, `ZipArchive`
   and `DelimitedImporter.splitRow` are all pure and worth pinning down first.

---

## Notes for future you

- `Card.id` and `Deck.id` are your own UUIDs, kept separate from SwiftData's
  `persistentModelID` so backups survive a store rebuild.
- `Profile` and `Settings` live in `UserDefaults` as JSON, not SwiftData —
  they're single values that every view reads, and putting them in the store
  would mean a fetch on every render.
- `AppModel.buildQueue` is where study order is decided: learning cards first,
  then reviews with the day's new cards spread evenly through them rather than
  bunched at the front.
- The bundle identifier in the project is `com.emberdeck.Emberdeck`. Change it
  before signing — it has to be unique to your Apple ID.
