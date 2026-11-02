# 16 — Challenges (functional)

**Purpose:** define the **Challenges** product for Circle (Evocative World elearning)—daily practice commitments that sit beside **block Assignments**, not inside them.

**Audience:** product, design, facilitation.

**Related:** [Index](00-indice.md) · [Technical](17-challenges-tecnico.md) · [Modules](03-modulos.md) · [Data model](07-modelo-datos.md) · [Stories](11-user-stories.md)

---

## 1. Purpose and value

A **Challenge** is a multi-day personal commitment inside a Circle: the member chooses a challenge, when to start, and a daily practice time. Each day they open a **session**—either play a prepared audio/video, or complete a reflective **quest** with freeform feedback.

| | Assignments (coins) | Challenges |
|--|---------------------|------------|
| Intent | Shared program checklist | Personal daily practice habit |
| Who defines | Facilitator | Facilitator (catalog) |
| Who starts | Progress is on the assignment rail | Member enrolls and schedules; **today’s session** can open from a non-assignment rail chip |
| Session | Sheet / checkboxes | Media player **or** quest + feedback |
| Duration cues | N/A | Baked into media file when `kind = media` |

Challenges do **not** replace the assignment rail. Both can exist in the same Circle. The rail shows **assignment progress chips** plus at most one **challenge-of-the-day** chip. See [doc 18](18-assignments-funcional.md).

Creating a challenge in a Hoop **mirrors** a row into the facilitator’s Content Library for reuse in other Hoops (same pattern as resources and assignments).

---

## 2. Actors

| Actor | Can |
|-------|-----|
| **Facilitator** (circle admin and/or platform admin who can manage the circle) | Create, edit, archive challenges in that Circle |
| **Member** | Browse challenges, enroll, set start date + daily time, run daily sessions, submit quest feedback, skip a day |
| **Guest / non-member** | Nothing |

There is no separate “system admin” role for Challenges beyond existing facilitator/admin concepts.

---

## 3. Challenge kinds (exactly two)

### 3.1 `media`

- One **audio** or **video** file provided by the facilitator.
- Duration, opening/closing gong, soft music, spoken guidance, etc. are **embedded in that file**.
- The app **plays** the file. It does **not** run a separate timer, layered soundtrack, or app-owned gong assets.
- Day completes when playback **ends naturally**, or the member confirms completion if they finish early (product may allow confirm; default = complete on `ended`).

### 3.2 `quest`

- Facilitator writes **instructions** (text; optional supporting image/link later).
- Member reflects and submits **freeform feedback**: **text and/or image and/or audio** (any combination they choose; at least one artifact required to complete the day).
- No timed practice engine.

---

## 4. Core concepts

| Concept | Meaning |
|---------|---------|
| **Challenge** | Template in a Circle (`durationDays`, kind, content) |
| **Enrollment** | Member’s commitment: start date, daily time, timezone, status |
| **Session** | One day of that enrollment (scheduled → done / skipped / missed) |
| **Day index** | 1…N within `durationDays` |

---

## 5. Flows

### 5.1 Facilitator creates a challenge

1. Open Circle → Challenges (admin entry from thread/info).
2. New challenge: title, description, `durationDays`, kind.
3. If `media`: upload audio **or** video; set optional `preAlarmMinutes` (default 10).
4. If `quest`: write instructions; set optional `preAlarmMinutes`.
5. Publish (status `active`). Members of the Circle can see it.

### 5.2 Member enrolls

1. Open Challenges list in the Circle.
2. Open a challenge → Read details.
3. Choose **start date** and **daily time** (local).
4. Confirm enrollment → status `active`.
5. System materializes upcoming sessions (or creates them day-by-day—see technical doc).

**Rule:** at most **one active enrollment** per `(user, challenge)`.

### 5.3 Daily media session

1. Reminder (phase 3: local notification ~`preAlarmMinutes` before daily time).
2. Member opens today’s session.
3. Sees title + short context → **Play**.
4. Audio/video plays to the end (cues included in file).
5. Session → `completed`; day counts toward N of M.

### 5.4 Daily quest session

1. Reminder as above.
2. Member opens today’s session → reads instructions.
3. Adds feedback: text and/or photo and/or voice note.
4. Submit → session `completed`.

### 5.5 Skip / miss

- **Skip:** member marks day skipped (does not count as completed).
- **Missed:** day window passed without complete/skip (status `missed`).
- Enrollment completes when `durationDays` calendar span ends, or when completed days ≥ target if product later defines that; **v1:** enrollment `completed` when the last scheduled day is past and sessions are closed.

---

## 6. Screen map

| Screen | Who | Purpose |
|--------|-----|---------|
| Challenges list | Members | Catalog + my enrollments status |
| Challenge detail / enroll | Members | Info + start date + daily time |
| Create / edit challenge | Facilitator | Kind, media upload or instructions |
| Today’s session | Member | Media player **or** quest + feedback |
| Enrollment progress | Member | Day N of M, history of sessions |

Entry points:

- Thread **AppBar** Challenges icon (when the Hoop has challenges) → Challenges list / enroll / session.
- Hoop **Info** → Challenges.
- Thread assignment rail: singular **challenge-of-the-day** chip when enrolled with a session today. Must not look like an assignment chip. Omit if none.

---

## 7. Business rules (summary)

| ID | Rule |
|----|------|
| CH-R1 | Only circle facilitators create/edit/archive challenges |
| CH-R2 | Only circle members read challenges and enroll |
| CH-R3 | One active enrollment per user per challenge |
| CH-R4 | Media day complete on playback ended (or explicit confirm) |
| CH-R5 | Quest day complete only with ≥1 feedback channel (text/image/audio) |
| CH-R6 | Challenges never write coin/ProgressLog state |
| CH-R7 | Pre-alarm is best-effort on mobile; web has no reliable ringing alarm |

Full rule IDs in [doc 05](05-reglas-negocio.md).

---

## 8. UX criteria

- Calm Evocative World tone; no neon streaks or loud gamification.
- Media session: player-first, minimal chrome.
- Quest session: instructions readable; feedback composer clear (text / photo / mic).
- Progress shown as simple “Day 3 of 21”, not a second assignment rail.

---

## 9. Acceptance (functional smoke)

- [ ] Facilitator creates a `media` challenge with an audio or video file.
- [ ] Facilitator creates a `quest` challenge with instructions.
- [ ] Member enrolls with start date + daily time.
- [ ] Member completes a media day by playing to the end.
- [ ] Member completes a quest day with text-only, image-only, audio-only, or mixed feedback.
- [ ] Second enrollment on the same challenge while active is blocked.
- [ ] Non-members cannot see or enroll in the Circle’s challenges.

---

## 10. Out of scope (v1)

- App-orchestrated multi-track timer, separate gong assets, or background music layers for `media`
- Live multi-user synchronized sessions
- Social streak leaderboards / public feed of completions
- Apple Watch / wearables
- Replacing Assignments with Challenges

---

## 11. Phases (product)

| Phase | Delivers |
|-------|----------|
| **1** | Catalog, create/edit, enroll, progress UI |
| **2** | Daily session: media player **or** quest + feedback upload |
| **3** | Mobile local notifications / pre-alarms; web soft reminders only |

Technical detail: [doc 17](17-challenges-tecnico.md).
