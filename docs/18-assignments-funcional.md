# 18 — Assignments (functional)

**Purpose:** define **block-based Assignments** authored as a **chat with the system**—same shell as the Hoop thread, not a separate card builder.

**Related:** [Technical](19-assignments-tecnico.md) · [Modules](03-modulos.md) · [Screens](06-mapa-pantallas.md) · [Rules](05-reglas-negocio.md) · [Challenges](16-challenges-funcional.md)

---

## Summary

An **assignment** is an ordered thread of **blocks**. Each block is either:

- **Content** — the student reads or plays it (same message kinds as Hoop chat).
- **Input** — the student must respond after publish.

The facilitator authors the assignment in a **system chat**: familiar composer and message bubbles, peer = the assignment (not Hoop members). Blocks are **not** written to the Hoop `posts` feed.

Progress on the thread rail is derived from **required input answers** and **submission** status.

**Challenges** remain a sibling ([doc 16](16-challenges-funcional.md)).

### Library reuse

Creating an assignment (system chat or Library publish) always keeps a row in the facilitator’s **Content Library** so it can be published into other Hoops. Same rule for resources and challenges: Hoop create **mirrors** into Library; Library → Publish clones into a Hoop without duplicating the catalog row.

---

## System-chat builder (facilitator)

Looks like the Hoop thread: message list + bottom composer.

- **Content** (composer / attach): text, image, video, audio, document/PDF, link — same mental model as existing message types.
- **Needs a response** (assignment-only composer section): question, upload request, single choice, multiple choice. Each has required/optional.
- Sending appends a block to the thread in order (WYSIWYG as the student will see content).
- Draft: reorder/edit/delete while unlocked. Publish: title, opensAt, dueAt, allowLate.
- After **any** student answer: **structure locked**; meta (title, dueAt, allowLate) still editable.
- Create via Assignments list / AppBar — not the Hoop rail `+`.

**Deferred:** rating scale; Preview as student polish; new version on edit (MVP uses lock).

---

## Student

- Same thread layout: content as facilitator-style bubbles; inputs as inline answer cards.
- Progress “N of M” (M = required); autosave; Submit when required filled.
- Edit until dueAt (or later if allowLate). Deadline at top.

Statuses: `notStarted` | `inProgress` | `submitted` | `late`.

---

## Facilitator tracking

- Assignments list → roster (status chip, progress, submittedAt); filters missing / submitted.
- Participant view: student’s answers in the same thread layout.
- Later: Remind, aggregates (choice counts, upload gallery).

---

## Thread rail

Chips = published assignment progress. Challenge-of-the-day remains a non-assignment sibling. No create on the rail.

---

## Deprecation

| Legacy | Replacement |
|--------|-------------|
| Objective checklist | Content + input blocks in system chat |
| ProgressLog per objective | `blockAnswers` + `assignmentSubmissions` |
| Coin = all objectives checked | Chip = required inputs + submit |

---

## MVP vs later

| In MVP | Later |
|--------|--------|
| System-chat authoring + student submit + rail + basic roster | Aggregates, Remind, versioning, rating scale |
| Lock after first answer | New version on structural edit |
