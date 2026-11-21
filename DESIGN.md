# DESIGN — Asani Patient App

UI/UX specification for the patient app (Android + iOS). Behaviour rules live in PRD.md; this document defines **how it looks and feels**.

---

## 1. Design principles

1. **Calm, not clinical.** Waiting is stressful; the app should feel reassuring.
2. **One big answer per screen.** The token screen answers "when is my turn?" in one glance.
3. **Built for parents and grandparents too.** Large text, high contrast, few steps, no hidden gestures.
4. **Never leave the user guessing.** Every state (loading, empty, offline, error, closed clinic) has a clear message and a next action.
5. **Fast for repeat users.** Recent clinics on Home; booking a returning visit should take 4 taps.

---

## 2. Brand

- **Name:** Asani (Urdu: "ease"). Wordmark: "asani" in lowercase, bold.
- **Tone of copy:** short, polite, direct. "Your turn now", not "It is now your turn to be seen by the doctor."
- **Logo (2026-11-17):** a one-colour lowercase "a" (open bowl, stem, tail swinging up) + "asani" wordmark, in forest
  green `#004741` on cream `#F0EDE4`, or cream on green. No plus in the bowl any more. In the app it is drawn by
  `AsaniMark` (`packages/asani_ui`). The launcher icon and Android system splash still use the old mark and teal:
  they need new image files (open item).

---

## 3. Design tokens

All values live in `lib/core/theme/`. Widgets must use tokens, never raw values.

### 3.1 Colours

| Token | Hex | Use |
|---|---|---|
Palette **6 · Monochrome green** (2026-11-17): only shades of the logo green, plus red/amber/blue kept for
status meaning. Dark mode values are agreed (mockups, D-30) and get their own tokens when dark mode is built.

| `primary` | `#004741` | Logo green: headers, buttons, active states, token number |
| `primaryContainer` | `#D2E8E1` | Selected chips, active token banner background |
| `onPrimary` | `#FFFFFF` | Text on primary |
| `secondary` | `#0B5C55` | Links, secondary actions |
| `surface` | `#FFFFFF` | Cards |
| `background` | `#F2F7F5` | Screen background (soft green-white) |
| `textPrimary` | `#0C2522` | Headings, body |
| `textSecondary` | `#4F6662` | Captions, labels |
| `border` | `#D9E7E2` | Card borders, dividers |
| `muted` | `#E4EFEB` | Quiet fills (segmented track, disabled chips) |
| `success` | `#00754F` | Completed, Available |
| `warning` | `#B45309` | On hold, Not started, Grace |
| `danger` | `#B91C1C` | Cancelled, errors, On leave |
| `info` | `#0369A1` | Called / Your turn (with animation) |
| `primaryMid` | `#0B5C55` | Second green of the header (`primary` → `primaryMid`) |
| `slate` | `#66807A` | Light end of the finished-token header (`textSecondary` → `slate`) |
| `headerChip` | `#0B5C55` | Chips and switches with white text on the green header (city pill, Active/Past, date chip) |
| `textMuted` | `#8FA39E` | Decoration only (chevrons). **Never for text** (fails 4.5:1) |

Dark mode (agreed, not built yet): page `#071A18`, card `#0D2522`, line `#173632`, text `#E3F1ED`, muted text
`#8FB0A8`, header `#00332E`, accent and buttons mint `#6BD1B5` with `#02211C` text.

All text/background pairs must meet **WCAG AA** (4.5:1 for body text). Placeholders use `textSecondary`.

**Status bar (2026-11-16):** light icons on teal / coloured headers, dark icons on white screens (OTP, Tell us
about you, primer, booking success, search). Screens whose header scrolls away paint a solid strip behind the
status bar (`StatusBarScrim`) so content never runs under the clock.

### 3.2 Typography

Font: **Inter** (via `google_fonts`, bundled for offline).

| Style | Size / Weight | Use |
|---|---|---|
| `tokenDisplay` | 72 / 800 | Token number on live screen |
| `displayLarge` | 46 / 800 | Intro pages: one word per line ("Book / your / token.") |
| `tokenDisplayMedium` | 64 / 800 | Token number on the full slip |
| `tokenDisplaySmall` | 48 / 800 | Token number on the compact slip (booking success) |
| `displaySmall` | 32 / 700 | "Now serving #7" |
| `headline` | 28 / 700 | Big page titles ("Enter the code", "Pick a date", "My tokens") |
| `titleLarge` | 22 / 700 | Screen titles |
| `titleMedium` | 18 / 600 | Card titles (clinic, doctor names) |
| `titleSmall` | 16 / 600 | Names inside list rows (patient, token rows) |
| `bodyLarge` | 16 / 400 | Body text (minimum body size) |
| `bodyMedium` | 14 / 400 | Secondary text |
| `labelLarge` | 16 / 600 | Buttons |
| `labelSmall` | 12 / 500 | Chips, badges |

Support system text scale up to **1.3×** without overflow. Widgets never set `fontSize` directly; add a style
here instead. Nothing smaller than `labelSmall` (12).

### 3.3 Spacing, radius, elevation

- Spacing scale: `4, 8, 12, 16, 24, 32, 48`. Screen padding: `16`.
- Radius: cards `16`, buttons `12`, chips `999` (pill), bottom sheets `24` top corners.
- Elevation: cards use a 1px `border` + no shadow; only bottom sheets and the active token banner use soft shadow.
- Minimum tap target: **48 × 48 dp**.

### 3.4 Icons

Material Symbols (Rounded). Always paired with a text label in navigation and status chips. Exception: the
bottom bar shows the label only on the selected tab (§4); the other tabs name themselves on long-press and to
screen readers.

Speciality icons (PRD F-13 table) use Material Symbols names such as `cardiology`, `dentistry`, `orthopedics`.
Most of them are **not** in Flutter's built-in `Icons` set, so they need the Material Symbols icon font package
(a new dependency, to be approved). Until then each chip falls back to `medical_services`.

---

## 4. Navigation

Bottom navigation with 4 tabs:

| Tab | Icon | Screen |
|---|---|---|
| **Home** | `home` | Search, active token, recent clinics, clinics list, upcoming follow-ups |
| **Tokens** | `confirmation_number` | Active / Past tokens |
| **Family** | `group` | Patient profiles, each with history and follow-ups |
| **Account** | `person` | Settings |

Look (2026-11-16): a floating teal pill bar (`AppColors.primary`) above the bottom edge. The selected tab grows into a white pill showing its icon and label in `primary` (5.5:1); the other tabs show the icon only (white at 85 %), with the label kept for screen readers and shown as a tooltip on long-press.

Booking is a full-screen flow pushed on top of the tabs (no bottom bar), with a back arrow on each step.

```
Splash → (first launch) Intro pages → Phone → OTP → Name & Consent → Home   (D-29)
Splash → (not logged in, intro seen) Phone → OTP → Name & Consent → Home
Splash → (logged in) Home

Home ─┬─ Search: Clinics tab ─┐
      ├─ Recent clinic ───────┼─→ Clinic page ─→ [Book flow] ─→ Token live screen
      ├─ Search: Doctors tab ─→ (first time: Location primer S-18) → speciality → doctor card ─→ [Book flow]
      └─ Active banner ───────────────────────────────────────→ Token live screen

[Book flow] = Who is the patient? → Pick date → Confirm
```

Routes (go_router):

| Route | Screen |
|---|---|
| `/splash` | Splash |
| `/login/phone`, `/login/otp`, `/login/profile` | Auth |
| `/home` | Home tab |
| `/search?q=` | Search, Clinics tab |
| `/search?tab=doctors&speciality=` | Search, Doctors tab (D-31); `speciality` = key from PRD F-13 |
| `/location` | Location permission primer (S-18), `?next=` like `/notifications` |
| `/clinic/:clinicId` | Clinic page (also deep link `/c/:clinicId`) |
| `/book/:clinicId/:doctorId` | Booking flow (steps as sub-routes `patient`, `date`, `confirm`) |
| `/token/:tokenId` | Live token screen (notification target) |
| `/tokens` | Tokens tab |
| `/family`, `/family/:patientId`, `/family/new`, `/family/:patientId/edit` | Profiles |
| `/account` | Account tab |

---

## 5. Screens

Wireframes are layout guides, not pixel specs.

### S-01 Splash
Logo tile, "asani" and the tagline "Book your clinic token without the long wait." centred on the teal header
gradient. Shown **about 1.5 s on every launch** (PRD D-25), longer only while the auth state still loads (then a
small spinner; after 10 s "Still connecting… Please check your internet."). Before Flutter starts, the Android
system splash is the same teal with the white "a" mark (Android 12+: `values-v31` theme; older: `launch_background`).
A notification tap that opens a token skips the wait.

### S-00 Intro pages ("Bold type", PRD D-29)
Three swipeable pages on `background`, shown once on the first launch, before S-02. Big words, one idea per page
(`displayLarge`, one word per line, the last word in `primary`), then one line of body text:
"Book / your / token." · "Wait / at / home." · "Go / when / called." On each page the words rise in one after
another (fade + slide up), then the body; off when the OS asks for reduced motion. Logo top-left, **Skip**
top-right (hidden on the last page), stretching page dots, primary button **Next** / **Get started**.
Skip or Get started → S-02. Not shown again after sign-out.

### S-02 Phone entry
```
┌──────────────────────────────┐
│  asani                       │
│                              │
│  Book your clinic token      │
│  without the long wait.      │
│                              │
│  Mobile number               │
│  ┌──────┬─────────────────┐  │
│  │ +92  │ 300 1234567     │  │
│  └──────┴─────────────────┘  │
│                              │
│  [        Send code        ] │
│                              │
│  We'll send a 6-digit code   │
│  by SMS.                     │
└──────────────────────────────┘
```
- Numeric keyboard, auto-format `3XX XXXXXXX`. Button enabled only for valid numbers.

### S-03 OTP
- 6 separate boxes, auto-advance, auto-fill on Android (SMS retriever).
- "Didn't get it? Resend in 0:59", then a "Resend code" link.
- "Wrong number? Change" link back to S-02.

### S-04 Tell us about you (first login only)
Design "Live slip preview" (2026-11-17): green header ("Last step" chip, "This is how clinics will see you."), and a
token-slip card overlapping it that fills in as the user types (initials avatar, name, "Self · age · gender").
- Full name (person icon), Age (years, 0–120) with round − / + buttons either side of the field, Gender as three big
  icon tiles (Male / Female / Other) — D-15.
- Consent and **Continue** stay pinned at the bottom; the form scrolls above them.
- "Use another number" text button signs out.
- Checkbox: "I agree to the **Terms** and **Privacy Policy**" (links open in-app browser).
- [Continue] enabled when name ≥ 2 chars and checkbox ticked.

### S-05 Home
```
┌──────────────────────────────┐
│ Hi, Ali                Lahore▾│
│ ┌──────────────────────────┐ │
│ │ 🔍 Search clinic or area │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │  ← Active token banner
│ │ TOKEN #11 · Dr. Ayesha   │ │    (primaryContainer)
│ │ Now serving #7 · 4 ahead │ │
│ │ ~ 40 min        View  →  │ │
│ └──────────────────────────┘ │
│ Upcoming follow-up           │
│ ┌──────────────────────────┐ │
│ │ Shazia · Dr. Ayesha      │ │
│ │ Due Tue, 12 Nov  [Book]  │ │
│ └──────────────────────────┘ │
│ Recent clinics               │
│ [Al-Shifa ▸] [City Care ▸]   │  ← horizontal cards
│ All clinics in Lahore        │
│ ┌──────────────────────────┐ │
│ │ Al-Shifa Clinic          │ │
│ │ Johar Town · 3 doctors   │ │
│ │ 🟢 Open today            │ │
│ └──────────────────────────┘ │
│ ...                          │
├──────────────────────────────┤
│ Home  Tokens  Family  Account│
└──────────────────────────────┘
```
- Multiple active tokens → banner becomes a horizontal carousel.

**Design "ticket stack" (2026-11-17), replaces the wireframe above:**
- Green header (`primary`, rounded bottom): initials avatar, greeting ("Good evening,") over the first name, city pill.
- Active tokens sit inside the header as paper slips (`TokenTicket`): clinic + status chip (Live / Your turn /
  Paused / Not started / the date for a later day), a dashed tear line, then "patient · doctor" and the big token
  code on the left and "3 ahead" + "~ 25 min · serving A-8" on the right. With more than one token, two paler
  slips peek out behind (`primaryLight`, `primarySoft`) and the slips swipe sideways, with stretching dots.
- No active token → **"How Asani works"** in the same place: three step tiles (1 Find a clinic · 2 Book a token ·
  3 Come when called, white icon circle with a number badge); no button (the search bar right below is the way in).
  Animation: the tiles rise in one after another, then a
  highlight walks 1 → 2 → 3 (2.2 s each; the lit tile turns `primaryLight` and its icon hops), the arrows light up
  and a three-part bar fills underneath; it loops. Static (no highlight, bar full) with reduced motion. As soon as
  any token is active, today or a later date, the ticket cards replace it.
- Below the header: search pill, follow-up cards (green tint, **Book**), **Recent clinics** as one card of rows
  (clinic initials, name, area, Open/Closed), then **All clinics**.
- **Clinic cards are tickets** (`ClinicCard`, also in search results): the stub colour shows the status, **green**
  when open (`successContainer` / `success`), **red** when closed (`dangerContainer` / `danger`), grey when online
  booking is paused; with the clinic initials and "● Open" (solid dot) / "○ Closed" (hollow ring), so it is not
  colour alone. A thin outline (1.2 px, following the notches) in the same status colour goes round the whole ticket.
  The Recent clinics initials follow the same colours. a dashed tear line with half-circle notches top and bottom
  (`TicketBorder`), then the name, "area · N doctors" and today's hours or "Opens Wed, 18 Nov".

### S-06 Search results
- Two tabs under the header (D-31): **Clinics** | **Doctors** (segmented control, `primary` fill on the selected
  one). Both use the selected city. The Home search pill opens the Clinics tab; the last-used tab is not remembered.
- **Clinics tab** (unchanged): search field auto-focused; results filter as the user types (debounce 250 ms).
- Empty result: "No clinic found for 'xyz'. Check the spelling or try the area name."

### S-06b Search: Doctors tab (PRD F-13, F-14)
```
┌──────────────────────────────┐
│ ←  Search            Lahore▾ │
│ [ Clinics ][■ Doctors ■]     │
│ (🩺 General) (👶 Child)  →   │  ← speciality chips, wrap in a grid
│ (❤ Heart)  (🦷 Teeth) ...    │     before one is picked
│                              │
│ Heart (Cardiologist) · 4     │
│ ┌──────────────────────────┐ │
│ │ (AK) Dr. Asif Khan    [B]│ │
│ │ Heart (Cardiologist)     │ │
│ │ City Care · DHA · 2.4 km │ │
│ │ ● Available · 5–9 PM     │ │
│ │ [Serving B-7][18/40][~25m]│ │
│ │ Also sits at:            │ │
│ │  Al-Shifa · Mon Wed 10–1 ›│ │
│ │ [      Book token      ] │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```
- **No speciality picked yet:** the chips fill the page as a 2-column grid of tiles (icon in a `primaryContainer`
  circle + the patient label, e.g. "Heart" over "Cardiologist" in `textSecondary`). After a pick they collapse into
  one horizontally scrolling row with the picked chip selected, and the list appears below.
- List title: "{label} · {count}". Order (D-33): bookable today, nearest first → clinics without a location
  (no km) → **not available today**, greyed (`textMuted` text, no tiles), with an outlined **Book another day**
  that opens booking on the date step. Sorted nearest first; without location, a small note "Turn on location to see
  the nearest first" [Turn on] above the list.
- **Doctor card** reuses the S-07 doctor card (initials avatar, name + letter badge, availability pill, the three
  tiles, full-width **Book token**), plus a line with the clinic name, area and distance (`textSecondary`;
  distance hidden without location). The middle tile shows **"18 of 40"** (booked / max) instead of "Waiting".
  Tap the card body → clinic page; **Book token** → booking for that clinic + doctor.
- **"Also sits at"** (only for linked doctors, F-14): a divider, the label "Also sits at" (`labelSmall`,
  `textSecondary`), then one row per other **same-city** clinic (D-33): clinic name · area · days and timing, chevron. Tap → booking
  for that clinic + doctor. Max 2 rows, then "+1 more".
- Loading: 3 skeleton doctor cards. Empty: icon + "No {label} doctors on Asani in {city} yet." [Search clinics]
  (switches to the Clinics tab). Offline: standard banner, cached list stays.

### S-18 Location permission primer (D-31)
Shown once, the first time the Doctors tab is opened (before the system prompt, like S-17):
icon `location_on` in a `primaryContainer` circle, title "Find doctors near you", body "We use your location
only to show the nearest clinics first. It is never saved or shared." → [Allow location] / [Not now].
The phone's own permission popup uses the approved text (D-33): "Asani uses your location to show clinics and
doctors near you." (Android has no custom text; iOS `NSLocationWhenInUseUsageDescription`.) Foreground only.
"Not now" or a refusal → the list shows same area first, then the rest of the city; the "Turn on location" note
stays above the list (opens the phone's settings if the phone already refused).

### S-07 Clinic page
```
┌──────────────────────────────┐
│ ←  Al-Shifa Clinic           │
│ Main Blvd, Johar Town        │
│ [📞 Call]  [📍 Directions]   │
│                              │
│ Choose a doctor              │
│ ┌──────────────────────────┐ │
│ │ Dr. Ayesha Malik         │ │
│ │ General Physician        │ │
│ │ 🟢 Available · 5–9 PM    │ │
│ │ Now serving #7           │ │
│ │ 12 waiting · ~45 min     │ │
│ │              [Book token]│ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ Dr. Kamran               │ │  ← greyed
│ │ Child Specialist         │ │
│ │ 🔴 On leave today        │ │
│ │       [Book another day] │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```
- Suspended clinic: banner "Online booking is not available for this clinic right now." All book buttons hidden.
- Look (2026-11-17): flat green header with rounded bottom, clinic initials on a white tile, address in the green
  tint, white **Call** / **Directions** pills. Doctor cards: initials avatar, name + letter badge, speciality,
  availability pill, then three equal-height tiles (Now serving · Waiting · Est. wait; labels never wrap) and a
  full-width **Book token** button; doctors who can't be booked today get an outlined **Book another day**.
  The speciality shows its patient label ("Heart (Cardiologist)", PRD F-13). A linked doctor (F-14) shows the
  same **"Also sits at"** rows as S-06b above the button.
  No all-caps "LIVE QUEUE" label; a paused queue shows "Queue is paused for a moment".

### S-08 Booking: Who is the patient?
- Title: "Who is the patient?"
- Radio-style list cards: name, relation, age/gender. "Self" first.
- "+ Add family member" opens a bottom sheet with the profile form (S-14).
- Profiles that already have an active token for this doctor on the chosen date are disabled with "Already has token #9 today" (checked again at confirm).

### S-09 Booking: Pick date
- Horizontal list of date chips: "Today", "Tomorrow", "Mon 10 Nov" …
- Disabled chips show the reason under them: "On leave", "Full", "No clinic".
- Below: doctor's timing for the selected day and current tokens booked (e.g. "18 of 40 booked").

### S-10 Booking: Confirm
- Summary card: clinic, doctor, patient (name · relation · age), date, timing.
- Note: "Your token number is given when you confirm."
- [Confirm booking] (primary, full-width). Shows a loader; double-tap protected.
- Errors from `bookToken` are shown in plain words (see §7).

### S-11 Token live screen
```
┌──────────────────────────────┐
│ ←  Your token                │
│                              │
│          TOKEN               │
│           11                 │  ← tokenDisplay, primary
│     Shazia Begum (Mother)    │
│  Dr. Ayesha Malik · Al-Shifa │
│      Today, 7 Nov            │
│                              │
│ ┌──────────┬───────────────┐ │
│ │ Now      │ Ahead of you  │ │
│ │ serving  │               │ │
│ │   #7     │      3        │ │
│ └──────────┴───────────────┘ │
│   Estimated wait ~ 30 min    │
│   [ Booked ]  status chip    │
│                              │
│   ┌────────┐                 │
│   │  QR    │ Show this at    │
│   └────────┘ reception       │
│                              │
│ [📞 Call clinic] [📍 Map]    │
│        Cancel token          │  ← text button, danger
└──────────────────────────────┘
```
State variations:
- **Called:** whole header area turns `info`, large text "Your turn now. Please go to Dr. Ayesha Malik.", gentle pulse animation (respect "reduce motion").
- **Not started:** "Doctor hasn't started yet. Session starts at 5:00 PM."
- **Paused:** "Queue is paused for a moment."
- **Completed / Cancelled / No-show:** muted card, no live numbers, "Book again" button.
- **Offline:** banner "Offline, last updated 4:32 PM".

### S-12 Tokens tab
- Segmented control: **Active** | **Past**.
- Token list cards: number, patient, doctor, clinic, date, status chip.

### S-13 Family tab
- List of profiles: avatar initials, name, relation, age/gender, "4 visits".
- FAB / button: "+ Add family member".

### S-14 Profile form (add/edit)
Fields: Full name · Age (years, numeric) · Gender (Male / Female / Other segmented) · Relation (dropdown) · Phone (optional, "if they have their own number").
- Duplicate-name warning shown inline before saving.
- Edit mode has "Remove profile" (not for Self).

### S-15 Profile detail
- Header: name, relation, age/gender.
- Sections: **Upcoming follow-ups**, **Visit history** (date, clinic, doctor, token #, status, wait time).

### S-16 Account
- Name (editable), phone (read-only).
- Notifications: status + "Open settings" if denied.
- "Using a Xiaomi/Redmi phone?" Autostart tip: shown **only** on Xiaomi / Redmi / POCO phones.
- Privacy Policy · Terms · Contact support · App version.
- Log out · **Delete account** (danger, double confirmation: type "DELETE").

### S-17 Notification permission primer
Shown once before booking the first token (not at app launch):
"Get notified when your turn is near. We'll send at most 4 alerts per token." → [Allow notifications] / [Not now].
The list on the page shows all four steps: 3 ahead, 2 ahead, 1 ahead (you're next), your turn.
On iOS this precedes the system prompt; on Android 13+ it precedes `POST_NOTIFICATIONS`.

---

## 6. Standard states (every data screen)

| State | Pattern |
|---|---|
| Loading | Skeleton cards (not spinners) for lists; small spinner inside buttons |
| Empty | Icon + one-line message + one action. E.g. Tokens/Active: "No active tokens. Find a clinic to book one." [Find clinic] |
| Error | "Something went wrong. Please try again." + [Retry]. Never show raw exception text. |
| Offline | Top banner, cached data stays visible, booking button disabled with "Needs internet" |
| Permission denied (notifications) | Inline card on token screen: "Notifications are off. You might miss your turn." [Turn on] |

---

## 7. Copy: errors from `bookToken`

| Error code | Message shown |
|---|---|
| `clinic-unavailable` | "This clinic isn't taking online bookings right now." |
| `doctor-unavailable` | "The doctor isn't available on this day. Please pick another date." |
| `session-ended` | "Today's session has ended. Please pick another date." |
| `tokens-full` | "All tokens for this day are booked. Please pick another date." |
| `duplicate-token` | "{name} already has token #{n} with this doctor on this day." |
| `too-many-active` | "You already have 5 active tokens. Cancel one to book another." |
| `network` | "No internet connection. Your booking was not made." |
| other | "Booking failed. Please try again." |

## 8. Copy: notifications

Fixed by PRD F-06. Keep titles under 40 characters, bodies under 90.

| Step | Title | Body |
|---|---|---|
| 3 ahead | 3 patients ahead of you | Token #{n} · {doctor}. Please start heading to the clinic. |
| 2 ahead | 2 patients ahead of you | Token #{n} · {doctor} |
| 1 ahead | You're next | Token #{n} · Please be at the reception. |
| Called | Your turn now | Token #{n} · Please go to {doctor}. |
| Skipped (D-34, outside the 4) | You missed your turn | Token #{n} · Go to reception to be called next. |
| Follow-up (day before) | Follow-up visit tomorrow | {patient} · {doctor}, {clinic}. Tap to book. |
| Follow-up (same day) | Follow-up visit today | {patient} · {doctor}. Tap to book your token. |

Android notification channels: `queue_alerts` (high importance, sound + vibration), `follow_ups` (default importance).

---

## 9. Motion

- Page transitions: platform default.
- Queue number changes: count-up/down animation 300 ms.
- "Your turn" pulse: 1.2 s loop, disabled when the OS "reduce motion" setting is on.

## 10. Out of scope (Phase 1)

Tablet layouts, Urdu, illustrations beyond simple empty-state icons. (Dark mode is approved, D-30, and built screen by screen.)
