# 10 — Diseño visual

**Purpose:** visual direction for **Circle** (product) under the **Evocative World** company / community brand.

**Alcance:** visión + subset MVP.

**Relacionados:** [Índice](00-indice.md) · [Wireframes](09-wireframes.md) · [Criterios UX](08-criterios-exito-ux.md)

---

## Arquitectura de marca

| Rol | Nombre | Dónde se ve |
|-----|--------|-------------|
| Compañía / comunidad | **Evocative World** | Auth (logo + pie), descripción PWA |
| Product | **Circle** | Daily chrome (Home, threads, Settings), app title |

Valores de marca (del logo): continuidad, colectivo, craft / naturaleza ↔ futuro. El producto traduce eso en círculos de aprendizaje calmados, no LMS ni gamificación ruidosa.

## Principios

1. Home = one clear composition (list of Circles), not an LMS dashboard.
2. Parent brand on Auth; product name (“Circles”) in daily chrome.
3. Tipografía expresiva (serif) para marca y títulos; UI sans legible en móvil.
4. Atmósfera calmada (enfoque / práctica): teal profundo, oro escaso, sin purple glow.
5. Filas de lista planas (estilo chat), no cards con sombra.
6. Badges de **tipo de post** discretos y escaneables.
7. Motion mínimo: lista→hilo, aparición de post, cambio de tick.

## Voice (UI in English)

Warm, clear, adult-learning. Short sentences. Prefer *your circle*, *facilitator*, *together / community*. Avoid *platform*, *dashboard*, *power-ups*, SaaS jargon.

## Evitar

Temas púrpura genéricos, cream+serif+terracotta genérico, broadsheet denso, glow, pills excesivas, dark-only, oro como color de botón primario.

## Tokens

```css
:root {
  --bg-app: #f2f4f1;
  --bg-elevated: #fbfcf9;
  --bg-auth-gradient: linear-gradient(165deg, #0d4a5b 0%, #1a3d6d 45%, #12151a 100%);
  --hairline: color-mix(in srgb, #1c1814 12%, transparent);
  --text-primary: #1c1814;
  --text-secondary: #5c574f;
  --text-inverse: #f7f4ef;
  --accent: #0d4a5b;
  --accent-pressed: #0a3a47;
  --accent-soft: color-mix(in srgb, #0d4a5b 14%, transparent);
  --gold: #b59344;
  --moss: #5a6b3a;
  --navy: #1a3d6d;
  --bubble-out: #d4e6e8;
  --bubble-in: #fbfcf9;
  --type-purpose: #0d4a5b;
  --type-progress: #1a3d6d;
  --type-practice: #8a5a00;
  --type-media: #5a6b3a;
  --coin-pending: #9aa39b;
  --coin-inprogress: #8fb0b8;
  --coin-completed: #0d4a5b;
  --danger: #b42318;
  --font-display: "Cormorant Garamond", Georgia, serif;
  --font-ui: "Source Sans 3", "Segoe UI", sans-serif;
  --radius-bubble: 18px;
  --space-4: 16px;
}
```

Implementación: [`circulo/lib/core/theme/app_colors.dart`](../lib/core/theme/app_colors.dart), [`app_theme.dart`](../lib/core/theme/app_theme.dart). Full lockup (Auth): `circulo/assets/brand/evocative_world_logo.png`.  
Mark only (app chrome, top-left): `circulo/assets/brand/ew_mark.jpg` via `brandAppBar` / `EwBrandMark`.

## Badges de tipo

Etiqueta corta sobre la burbuja o en el preview de lista: Propósito / Progreso / Currículo / Práctica / Media. Color de acento suave por tipo; no depender solo del color (texto visible).

## Coins (rail de Assignments)

- Forma: micro-círculos/cápsulas con etiqueta discreta.
- `pending`: gris neutro; `en progreso`: teal suave; `completado`: teal de producto + check en oro.
- Hint de grupo discreto (ej. “3/5”) sin competir con el chat.

## Estados de envío

| Estado | Señal |
|--------|--------|
| pending | tick/reloj neutro |
| sent / delivered | doble tick neutro |
| read | doble tick accent (visión) |
| failed | danger + Reintentar |

## Auth

Full-bleed EW gradient (teal → navy → near-black); Evocative World logo; product name **Circle**; line *Learning in community*; Google CTA. No feature cards.

## Subset MVP

Tokens, Auth lockup, home, coin rail, assignment sheet, hilo, badges de tipo, ticks pending/sent/failed, motion lista→hilo. Sin dark mode ni tab Hoy estilizada.
