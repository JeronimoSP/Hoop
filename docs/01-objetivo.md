# 01 — Objetivo

**Propósito:** definir qué hace el producto, para quién y con qué principios, sin entrar en píxeles ni implementación.

**Alcance:** visión completa (aprendizaje colaborativo). El MVP técnico está en [doc 13](13-diseno-tecnico-mvp-firebase.md).

**Relacionados:** [Índice](00-indice.md) · [Actores](02-actores.md) · [Módulos](03-modulos.md) · [Criterios de éxito UX](08-criterios-exito-ux.md)

---

## Marca

**Evocative World** is the company / community. **Circle** is the elearning product (this app) for that community. See [doc 10](10-diseno-visual.md).

## Propuesta de valor

Espacio de **grupos de aprendizaje** con usabilidad tipo mensajería (lista → hilo → composer): los participantes viven en **Círculos** para cumplir un programa diario/semana.

La mecánica es **gamificada**: el progreso se hace visible mediante un **rail** sobre el composer: **chips de assignment** (hilo system-chat de bloques content + input; ver [doc 18](18-assignments-funcional.md)) y un chip de **challenge del día**. Crear assignments/challenges/resources es desde AppBar / listas admin, no desde el rail.

El Círculo conserva la flexibilidad del chat: además del progreso, los miembros publican mensajes libres y contenido distribuido por el admin (por ejemplo **instrucciones sticky** y **recursos**).

**Challenges** (sibling to assignments): multi-day personal practice—member picks a challenge, start date, and daily time; each day is either a **media** session or a **quest**. See [doc 16](16-challenges-funcional.md).

## Problemas que resuelve

| Problema | Cómo lo aborda el producto |
|----------|----------------------------|
| Estudiar o practicar en aislamiento | Círculos con compañeros visibles y activos |
| El progreso no se comparte ni se celebra | Rail de assignments + respuestas a bloques input |
| Conversaciones de estudio perdidas en chats genéricos | Hilo del Círculo + previews tipados en la lista |
| Falta de hábito matutino / intención diaria | Challenges + assignments con bloques de reflexión |
| Inspiración efímera sin contexto de grupo | Stories y recursos anclados al Círculo y al programa de learning |
| Redes intermitentes en el día a día | Cola offline, reintentos, media comprimida (visión) |

## Principios de diseño del producto

1. **Shell familiar:** lista de Círculos, hilo y composer inferior — navegación tipo WhatsApp.
2. **Intención pedagógica:** el corazón son **Assignments (system chat)** y **Challenges**.
3. **Gamificación visible:** el rail de assignments reduce la fricción de “¿en qué vamos?”.
4. **Círculo primero:** la home son Círculos; el 1:1 es secundario.
5. **Admin como diseñador del programa:** crea assignments (composer system-chat), challenges, roles.
6. **Claridad de contexto:** el usuario entiende qué falta por responder y el siguiente paso.
7. **Tolerancia a red débil:** redactar, encolar y marcar avance sin bloquear la UI.

## Para quién

- Facilitadores / admins que organizan cohortes o grupos de práctica.
- Participantes de cursos, retiros, masterminds o cohorts de hábito.
- Uso principal en móvil nativo (Flutter iOS/Android); web/PWA como visión diferida.

## Fuera de alcance

- Red social abierta o descubrimiento público de Círculos.
- Marketplace, pagos o LMS completo (calificaciones formales, SCORM, etc.).
- Clonar pixel a pixel otra marca de mensajería.
- Llamadas y E2EE como núcleo del producto de aprendizaje (visión diferida).

## Relación con el MVP

El MVP ([doc 13](13-diseno-tecnico-mvp-firebase.md), [doc 15](15-plan-flutter-mvp.md), [doc 18](18-assignments-funcional.md)) entrega Auth Google, home de Círculos, membership, hilo tipado y **Assignments system-chat + rail** sobre Firestore, con cliente Flutter.
