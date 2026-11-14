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
- **App icon:** the lowercase "a" monogram with a small plus in its counter, white on primary (D-12). Source: `branding/logo-06/`.

---

## 3. Design tokens

All values live in `lib/core/theme/`. Widgets must use tokens, never raw values.

### 3.1 Colours

| Token | Hex | Use |
|---|---|---|
| `primary` | `#0F766E` | Buttons, active states, token number |
| `primaryContainer` | `#CCFBF1` | Selected chips, active token banner background |
| `onPrimary` | `#FFFFFF` | Text on primary |
| `secondary` | `#1E3A8A` | Links, secondary actions |
| `surface` | `#FFFFFF` | Cards |
| `background` | `#F6F8F7` | Screen background |
| `textPrimary` | `#0F172A` | Headings, body |
| `textSecondary` | `#475569` | Captions, labels |
| `border` | `#E2E8F0` | Card borders, dividers |
| `success` | `#15803D` | Completed, Available |
| `warning` | `#B45309` | On hold, Not started, Grace |
| `danger` | `#B91C1C` | Cancelled, errors, On leave |
| `info` | `#0369A1` | Called / Your turn (with animation) |

All text/background pairs must meet **WCAG AA** (4.5:1 for body text).

### 3.2 Typography

Font: **Inter** (via `google_fonts`, bundled for offline).

| Style | Size / Weight | Use |
|---|---|---|
| `tokenDisplay` | 72 / 800 | Token number on live screen |
| `displaySmall` | 32 / 700 | "Now serving #7" |
| `titleLarge` | 22 / 700 | Screen titles |
| `titleMedium` | 18 / 600 | Card titles (clinic, doctor names) |
| `bodyLarge` | 16 / 400 | Body text (minimum body size) |
| `bodyMedium` | 14 / 400 | Secondary text |
| `labelLarge` | 16 / 600 | Buttons |
| `labelSmall` | 12 / 500 | Chips, badges |

Support system text scale up to **1.3×** without overflow.

### 3.3 Spacing, radius, elevation

- Spacing scale: `4, 8, 12, 16, 24, 32, 48`. Screen padding: `16`.
- Radius: cards `16`, buttons `12`, chips `999` (pill), bottom sheets `24` top corners.
- Elevation: cards use a 1px `border` + no shadow; only bottom sheets and the active token banner use soft shadow.
- Minimum tap target: **48 × 48 dp**.

### 3.4 Icons

Material Symbols (Rounded). Always paired with a text label in navigation and status chips.

---

## 4. Navigation

Bottom navigation with 4 tabs:

| Tab | Icon | Screen |
|---|---|---|
| **Home** | `home` | Search, active token, recent clinics, clinics list, upcoming follow-ups |
| **Tokens** | `confirmation_number` | Active / Past tokens |
| **Family** | `group` | Patient profiles, each with history and follow-ups |
| **Account** | `person` | Settings |

Booking is a full-screen flow pushed on top of the tabs (no bottom bar), with a back arrow on each step.

```
Splash → (not logged in) Phone → OTP → Name & Consent → Home   (no intro pages, D-28)
Splash → (logged in) Home

Home ─┬─ Search results ─┐
      ├─ Recent clinic ──┼─→ Clinic page ─→ [Book flow] ─→ Token live screen
      └─ Active banner ──────────────────────────────────→ Token live screen

[Book flow] = Who is the patient? → Pick date → Confirm
```

Routes (go_router):

| Route | Screen |
|---|---|
| `/splash` | Splash |
| `/login/phone`, `/login/otp`, `/login/profile` | Auth |
| `/home` | Home tab |
| `/search?q=` | Search results |
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

### S-00 Intro pages (removed, PRD D-28)
Three swipeable pages on `surface`, shown once before S-02 (D-16): "Find your clinic", "Skip the waiting room",
"We'll tell you when to go". Each page: large icon in `primaryContainer` circles, title, one line of body text.
Logo top-left, **Skip** top-right (hidden on the last page), page dots, primary button **Next** / **Get started**.
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
- Full name, Age (years, 0–120), Gender (Male / Female / Other) — D-15.
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

### S-06 Search results
- Search field auto-focused; results filter as the user types (debounce 250 ms).
- Empty result: "No clinic found for 'xyz'. Check the spelling or try the area name."

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
- Privacy Policy · Terms · Contact support · App version.
- Log out · **Delete account** (danger, double confirmation: type "DELETE").

### S-17 Notification permission primer
Shown once before booking the first token (not at app launch):
"Get notified when your turn is near. We'll send at most 4 alerts per token." → [Allow notifications] / [Not now].
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
| Follow-up (day before) | Follow-up visit tomorrow | {patient} · {doctor}, {clinic}. Tap to book. |
| Follow-up (same day) | Follow-up visit today | {patient} · {doctor}. Tap to book your token. |

Android notification channels: `queue_alerts` (high importance, sound + vibration), `follow_ups` (default importance).

---

## 9. Motion

- Page transitions: platform default.
- Queue number changes: count-up/down animation 300 ms.
- "Your turn" pulse: 1.2 s loop, disabled when the OS "reduce motion" setting is on.

## 10. Out of scope (Phase 1)

Dark mode (pending Q-07), tablet layouts, Urdu, illustrations beyond simple empty-state icons.
