# 08 — Criterios de éxito (UX funcional)

**Propósito:** checks verificables de usabilidad (shell WhatsApp + rituales de aprendizaje).

**Relacionados:** [Índice](00-indice.md) · [Objetivo](01-objetivo.md) · [Flujos](04-flujos-clave.md) · [User stories](11-user-stories.md)

---

## Criterios principales

### C01 — Abrir Círculo reciente en ≤ 2 taps

Desde home autenticado, entrar al Círculo más reciente y ver el composer en ≤ 2 taps (apertura del ítem cuenta como 1; foco automático en composer).

**MVP:** Sí

### C02 — Abrir coin y marcar objective en pocos taps

Desde el hilo, tocar la **coin** del Assignment y completar un **objective** (por ejemplo tipo `purpose`) con evidencia mínima; máximo 1–2 pasos extra vs mensaje libre.

**MVP:** Sí

### C03 — Preview tipado en lista

El Círculo en home muestra una señal compacta del programa (estado/prefijo del próximo objective o coin) y, opcionalmente, un preview textual.

**MVP:** Sí

### C04 — Claridad de Círculo activo

En el hilo, el nombre del Círculo es inequívoco en la cabecera; no hay duda de contexto.

**MVP:** Sí

### C05 — Feedback de envío / offline

Estados pending / sent / failed visibles; reintento si falla; no bloqueo total sin red.

**MVP:** Sí

### C06 — Admin gestiona roster sin fricción

Crear Círculo + añadir miembros en un flujo continuo (&lt; 1 minuto en prueba con 3 miembros).

**MVP:** Sí

### C07 — Uso con una mano

Lista, composer y FAB/acción admin alcanzables en viewport móvil.

**MVP:** Sí

### C08 — Búsqueda de Círculos

Filtrar home por nombre en dataset pequeño con respuesta percibida inmediata.

**MVP:** Sí (filtro local)

### C09 — Coin rail con monedas y sheet de Assignment

En el hilo, la cabecera muestra coins por Assignment; al tocar una coin se abre el sheet con Objectives y evidencia requerida (estado personal y señal del grupo si aplica).

**MVP:** Sí

### C10 — Marcar objective actualiza la coin y el progreso

Desde el sheet, completar una objective con evidencia mínima recalcula el progreso y actualiza la coin (personal y/o agregado).

**MVP:** Sí

### C11 — Stories y vista Hoy (visión)

Stories TTL usables; la vista “Hoy” resume propósitos/prácticas recientes del círculo.

**MVP:** No (visión)

### C12 — Filtros por tipo en hilo (visión)

Filtrar la conversación por tipo (p. ej. objetivos/evidencias) sin romper el contexto del hilo.

**MVP:** No (visión)

---

## Definición de listo

| Capa | Criterios |
|------|-----------|
| **MVP** | C01–C10 |
| **Visión** | C01–C12 |

## Validación

1. Checklist manual en móvil (PWA/navegador).  
2. Dogfooding con un admin + 3–5 participantes reales.  
3. Registrar fallos contra IDs C0x.
