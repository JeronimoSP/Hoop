# 19 — Assignments (technical)

**Purpose:** Firestore shapes, rules, routes, and client mapping for block-based Assignments authored as a **system chat**.

**Related:** [Functional](18-assignments-funcional.md) · [Data model](07-modelo-datos.md) · [Rules](05-reglas-negocio.md) · App [repo root](../)

---

## UI mapping

- Screen: `AssignmentSystemThreadScreen` — composer + bubbles patterned after [`thread_screen.dart`](../lib/features/thread/thread_screen.dart).
- Content blocks reuse post-like payloads (`body`, media fields, link).
- Input blocks are assignment-only composer actions; not available on the Hoop composer.
- Blocks live in `assignmentBlocks`, **not** in Hoop `posts`.

**Library mirror:** on draft create, write `libraryItems` (`kind: assignment`, `meta.circleId` / `assignmentId` / `source: hoop`). On publish, sync title + `meta.blocks` snapshot for re-publish. `publishToCircle` sets instance links on the **same** library row (`skipLibraryMirror`).

**List-query rule:** every collection query that uses `isMember(resource.data.circleId)` must include an equality filter on `circleId` (otherwise Firestore returns `permission-denied`).

---

## Collections

Top-level docs with denormalized `circleId`.

### `assignments/{assignmentId}`

| Field | Type | Notes |
|-------|------|--------|
| `circleId` | string | |
| `createdBy` | string | Admin uid |
| `title` | string | |
| `description` | string? | |
| `createdAt` | Timestamp | |
| `status` | string | `draft` \| `published` \| `archived` |
| `opensAt` | Timestamp? | |
| `dueAt` | Timestamp? | |
| `allowLate` | bool | default false |
| `publishedAt` | Timestamp? | set on publish |

Members list/rail: `status == published` (legacy `active` treated as published). Admins also see `draft`.

### `assignmentBlocks/{blockId}`

| Field | Type | Notes |
|-------|------|--------|
| `circleId` | string | **Required on list queries** |
| `assignmentId` | string | |
| `order` | int | 0-based |
| `kind` | string | `content` \| `input` |
| `type` | string | see below |
| `required` | bool | input only |
| `payload` | map | type-specific |

**Content `type`:** `text`, `media` (subtype in payload: image/video/audio/pdf), `link`  
**Input `type`:** `question`, `upload`, `singleChoice`, `multipleChoice`

**Payload sketches**

- text: `{ body }`
- media: `{ mediaKind, storagePath?, downloadUrl?, mime?, fileName? }`
- link: `{ url, label? }`
- question: `{ prompt, longAnswer: bool }`
- upload: `{ prompt?, allowedMime: string[], maxBytes: number, maxFiles: number }`
- singleChoice / multipleChoice: `{ prompt, options: [{ id, label }] }`

### `blockAnswers/{id}`

Doc id: `{assignmentId}_{blockId}_{userId}`.

| Field | Type |
|-------|------|
| `circleId`, `assignmentId`, `blockId`, `userId` | string |
| `value` | map — text / `selectedOptionIds` / `files: [...]` |
| `updatedAt` | Timestamp |

### `assignmentSubmissions/{id}`

Doc id: `{assignmentId}_{userId}`.

| Field | Type |
|-------|------|
| `circleId`, `assignmentId`, `userId` | string |
| `status` | `notStarted` \| `inProgress` \| `submitted` \| `late` |
| `answeredRequiredCount`, `requiredCount` | int |
| `submittedAt` | Timestamp? |
| `updatedAt` | Timestamp |

---

## Legacy (read-only path)

| Collection | Status |
|------------|--------|
| `objectives` | No new writes from create UI |
| `progressLogs` | No new writes from mark-complete UI |

---

## Rules sketch

- **assignments / assignmentBlocks:** member read; circle admin create/update/delete.
- **blockAnswers / assignmentSubmissions:** member read; owner create/update own; admin may delete.
- Structure lock: client MVP.

---

## Storage

`circles/{circleId}/assignments/{assignmentId}/blocks/{blockId}/…`  
`circles/{circleId}/assignments/{assignmentId}/answers/{userId}/{blockId}/…`

---

## Routes (Flutter)

| Path | Screen |
|------|--------|
| `/circles/:circleId/assignments` | List |
| `/circles/:circleId/assignments/new` | System thread (new draft) |
| `/circles/:circleId/assignments/:assignmentId` | System thread (student / view) |
| `/circles/:circleId/assignments/:assignmentId/edit` | System thread (admin draft/edit) |
| `/circles/:circleId/assignments/:assignmentId/roster` | Facilitator roster |
| `.../participant/:userId` | Read-only answers |

---

## Rail mapping

Chips = published assignments + member `assignmentSubmission`. Challenge-of-day unchanged ([doc 17](17-challenges-tecnico.md)).

---

## Indexes

- `assignmentBlocks`: `circleId` + `assignmentId`
- `blockAnswers`: `circleId` + `assignmentId` + `userId`
- `blockAnswers`: `circleId` + `assignmentId`
- `assignmentSubmissions`: `circleId` + `assignmentId`; `circleId` + `userId`
- `assignments`: `circleId` + `status` (+ `createdAt`)
