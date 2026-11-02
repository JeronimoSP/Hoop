# 14 — Plan de implementación: paso 1 (wireframe HTML interactivo ampliado)

**Propósito:** prototipo HTML clicable que demuestra flujos entre pantallas y acciones de **Círculos de aprendizaje**. Sin Firebase, sin backend, sin diseño final.

**Fuentes:** [06 Mapa](06-mapa-pantallas.md) · [09 Wireframes](09-wireframes.md) · [13 MVP](13-diseno-tecnico-mvp-firebase.md)

**Prototipo:** [`../wireframe/`](../wireframe/)

**Siguiente paso:** app Flutter + Firebase — [doc 15](15-plan-flutter-mvp.md) · contrato [doc 13](13-diseno-tecnico-mvp-firebase.md) · código [repo root](../).

---

## Objetivo

1. Recorrer pantallas MVP + ampliación A
2. Validar roles de sesión, reunión, sticky y recursos
3. Demo usable en &lt; 5 minutos sin setup

---

## Alcance incluido

### Núcleo (W1–W8)

Auth mock, Home Círculos, Hilo con **coin rail** + **assignment sheet** (Objectives) y marcado de progreso (mock), Nuevo Círculo (admin), Info/roster, Ajustes, búsqueda, toggle Admin/Member.

### Ampliación (requisitos nuevos + lote A)

| Feature | Detalle |
|---------|---------|
| **Coin rail (Assignments)** | Tap en la coin abre assignment sheet con Objectives; estados pending/en progreso/completado; progreso personal y mock agregado |
| **Marcar progreso (Objectives)** | Desde el sheet, marcar completado de objectives (mock de evidencia) y actualizar coin |
| **Pointer / Time keeper** | Asignables por admin entre miembros; visibles en Info, hilo y home |
| **Próxima reunión** | `nextMeetingAt` en Info (admin), hilo y preview home |
| **Instrucciones sticky** | `type: instruction`; solo admin; fijadas arriba del hilo |
| **Recursos** | `type: resource` + kind `pdf` \| `video` \| `drive`; título + URL |
| **Tab Hoy** | Atajos propósito/práctica + posts del día |
| **Filtros de hilo** | Chips por tipo |
| **Stories** | Carril + viewer mock |
| **Mute / pin** | Preferencias por círculo (usuario demo) |
| **Empty states** | Home / hilo / Hoy con CTAs |

### Datos

- Estado en memoria + `sessionStorage`
- Sin Auth real ni Firestore

### Fuera de alcance

Firebase, OAuth Drive, upload real, Google Calendar sync, diseño visual doc 10, DM.

---

## Enfoque técnico

| Decisión | Elección |
|----------|----------|
| Stack | `index.html` + `styles.css` + `app.js` |
| Ubicación | [`wireframe/`](../wireframe/) |
| Rol demo | Admin / Member en Auth y Ajustes |
| Idioma | Español |

---

## Modelo de estado (extensión)

```js
{
  role: "admin" | "member",
  screen: "auth" | "home" | "hoy" | "thread" | "new-circle" | "info" | "settings",
  threadFilter: "all" | postType,
  circles: [{
    id, name, description, memberIds, adminIds,
    pointerId, timeKeeperId, nextMeetingAt,
    pinned, muted,
    stories: [{ id, authorName, body, viewers }],
    lastPost, updatedAt
  }],
  postsByCircle: {
    [circleId]: [{
      id, type, body, authorName, createdAt, mine,
      resourceKind?, url?, title?,  // resource
      sticky?                       // instruction
    }]
  }
}
```

Tipos de post: `purpose`, `progress`, `curriculum`, `morning_practice`, `media`, `free`, `instruction`, `resource`.

---

## Checklist de aceptación

| ID | Flujo |
|----|-------|
| W1–W8 | Núcleo original |
| W9 | Admin asigna Pointer y Time keeper en Info |
| W10 | Admin define próxima reunión; se ve en hilo y home |
| W11 | Admin publica instrucción sticky arriba del hilo |
| W12 | Admin publica recurso PDF/video/Drive con link |
| W13 | Filtros de hilo por tipo |
| W14 | Tab Hoy: atajos + resumen del día |
| W15 | Stories: abrir carril → viewer → cerrar |
| W16 | Mute / pin desde Info; reflejo en home |
| W17 | Coin rail visible en el header del hilo |
| W18 | Tocar coin → abre assignment sheet con Objectives |
| W19 | Admin crea Assignment + Objectives (mock) y se refleja en la coin rail |
| W20 | Member marca Objective completada (mock) y la coin actualiza |
| W21 | (Mock) Señal de progreso agregado del grupo en la coin rail |
| W22 | Assignment sheet convive con sticky/recurso mientras se completa |

---

## Criterios de done

- [x] `wireframe/` abre sin build
- [ ] Checklist W1–W22 en README
- [ ] Doc 14 alineado con el prototipo
- [ ] Sin dependencias npm obligatorias
