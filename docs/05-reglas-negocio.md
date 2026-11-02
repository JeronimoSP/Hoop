# 05 — Reglas de negocio

**Propósito:** reglas con condición, acción y excepción. Etiqueta **Visión** o **MVP**.

**Relacionados:** [Índice](00-indice.md) · [Actores](02-actores.md) · [Modelo de datos](07-modelo-datos.md) · [MVP Firebase](13-diseno-tecnico-mvp-firebase.md)

---

### R01 — Identidad autenticada

| | |
|--|--|
| **Condición** | Un usuario quiere usar el producto |
| **Acción** | Debe autenticarse (MVP: Google; visión: también otras identidades) |
| **Excepción** | Ninguna para leer/escribir en Círculos |
| **Capa** | MVP + Visión |

### R02 — Visibilidad por membresía

| | |
|--|--|
| **Condición** | Lectura o escritura en un Círculo / posts / stories |
| **Acción** | Solo si existe `Membership` activa para ese `circleId` |
| **Excepción** | Ninguna |
| **Capa** | MVP + Visión |

### R03 — Solo admin crea y gestiona Círculo

| | |
|--|--|
| **Condición** | Crear Círculo, editar info, añadir/quitar miembros, eliminar Círculo |
| **Acción** | Requiere rol `admin` en ese Círculo (o admin de plataforma) |
| **Excepción** | Un member puede salir del Círculo por sí mismo (visión) |
| **Capa** | MVP + Visión |

### R04 — Participante no elimina el Círculo

| | |
|--|--|
| **Condición** | Member intenta borrar el Círculo |
| **Acción** | Rechazar; solo admin |
| **Excepción** | Ninguna |
| **Capa** | MVP + Visión |

### R05 — Posts tipados

| | |
|--|--|
| **Condición** | Se crea un Post |
| **Acción** | Debe tener `type` del enum permitido; default `free`. Si `type` ∈ {`instruction`,`resource`} entonces el creador debe ser `admin` del Círculo |
| **Excepción** | Posts de sistema (`system`) sin UI de tipo |
| **Capa** | MVP + Visión |

### R06 — Preview tipado en lista

| | |
|--|--|
| **Condición** | Hay un nuevo last post |
| **Acción** | Home muestra prefijo de tipo + texto truncado |
| **Excepción** | Story no sustituye last post del hilo persistente |
| **Capa** | MVP + Visión |

### R07 — Stories con TTL 24 h

| | |
|--|--|
| **Condición** | Story supera `expiresAt` |
| **Acción** | Deja de ser visible; datos expirados/eliminados |
| **Excepción** | Ninguna para viewers |
| **Capa** | Visión |

### R08 — Media y límites

| | |
|--|--|
| **Condición** | Adjuntos audio/video/foto |
| **Acción** | Comprimir por defecto; rechazar sobre límite de tamaño/duración |
| **Excepción** | Opción calidad original (visión) |
| **Capa** | Visión / fase 2 MVP |

### R09 — Offline y reintentos

| | |
|--|--|
| **Condición** | Sin red al publicar |
| **Acción** | Encolar; pending/failed; reintentar al recuperar |
| **Excepción** | Cancelación explícita del usuario |
| **Capa** | MVP + Visión |

### R10 — Silenciar / fijar sin borrar

| | |
|--|--|
| **Condición** | Mute o pin de un Círculo |
| **Acción** | Afecta lista/notificaciones; no borra historial |
| **Excepción** | Borrado explícito de datos (visión) |
| **Capa** | Visión (pin/mute); MVP puede omitir |

### R11 — Sin E2EE en MVP

| | |
|--|--|
| **Condición** | Tránsito y reposo en MVP |
| **Acción** | TLS + reglas Firestore por membership; sin E2EE de cliente |
| **Excepción** | Visión futura puede introducir E2EE |
| **Capa** | MVP |

---

### R12 — Creación de Assignments y bloques (solo admin)

| | |
|--|--|
| **Condición** | Se crea/edita un `Assignment` o `assignmentBlock` |
| **Acción** | Debe ser `admin` del Círculo |
| **Excepción** | Ninguna |
| **Capa** | MVP + Visión |

### R13 — Respuestas y submit solo miembros

| | |
|--|--|
| **Condición** | Escritura de `blockAnswers` / `assignmentSubmissions` |
| **Acción** | Membership activa; solo propio `userId` |
| **Excepción** | Ninguna |
| **Capa** | MVP + Visión |

### R14 — Validación de inputs requeridos al Submit

| | |
|--|--|
| **Condición** | Estudiante pulsa Submit |
| **Acción** | Todos los input `required` tienen valor válido |
| **Excepción** | Autosave sin submit |
| **Capa** | MVP + Visión |

### R15 — Assignment rail es derivado

| | |
|--|--|
| **Condición** | UI muestra progreso en el rail |
| **Acción** | Chip derivado de submissions / required answers; no se escribe “coin state” |
| **Excepción** | Legacy objectives/ProgressLog legibles hasta migrar |
| **Capa** | MVP + Visión |

### R15b — Estructura bloqueada tras respuestas

| | |
|--|--|
| **Condición** | Existe al menos un `blockAnswer` |
| **Acción** | No add/reorder/edit/delete de bloques (meta sí) |
| **Excepción** | Visión: nueva versión |
| **Capa** | MVP + Visión |

### R16 — Sticky instructions y recursos admin-only

| | |
|--|--|
| **Condición** | Se crea/actualiza contenido `instruction` sticky o `resource` |
| **Acción** | Solo `admin` del Círculo puede crear/editar; miembros pueden leer |
| **Excepción** | Ninguna |
| **Capa** | MVP + Visión (MVP con links mock) |

### R17 — Challenge create/edit (facilitator only)

| | |
|--|--|
| **Condición** | Create/update/archive a Challenge in a Circle |
| **Acción** | Must be circle admin (facilitator); members may only read `active` challenges |
| **Excepción** | None |
| **Capa** | Challenges ([doc 16](16-challenges-funcional.md) / [17](17-challenges-tecnico.md)) |

### R18 — Challenge enrollment (member, one active)

| | |
|--|--|
| **Condición** | Member enrolls in a challenge |
| **Acción** | Requires membership; at most one **active** enrollment per `(userId, challengeId)` |
| **Excepción** | Re-enroll after `completed` / `cancelled` allowed as a new enrollment |
| **Capa** | Challenges |

### R19 — Media session completion

| | |
|--|--|
| **Condición** | `kind == media` daily session |
| **Acción** | Complete when playback ends (or explicit confirm); no app-orchestrated timer/gong required |
| **Excepción** | None |
| **Capa** | Challenges |

### R20 — Quest session evidence

| | |
|--|--|
| **Condición** | `kind == quest` daily session submitted |
| **Acción** | Require ≥1 of text / image / audio evidence; owner-only write on enrollment/session |
| **Excepción** | None |
| **Capa** | Challenges |

### R21 — Challenges do not write assignment progress

| | |
|--|--|
| **Condición** | Challenge session completes |
| **Acción** | Must not mutate Assignment / blocks / answers / submissions (nor legacy Objective / ProgressLog) |
| **Excepción** | None |
| **Capa** | Challenges |

---

## Resumen MVP

Aplicar: **R01–R06**, **R09–R11**, **R12–R16** (con R14 en validación mínima en MVP). **R17–R21** when Challenges ship. Diferir lo que exceda evidencia avanzada, media pesada y cálculos complejos.
