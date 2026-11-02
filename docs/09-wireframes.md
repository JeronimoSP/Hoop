# 09 — Wireframes

**Propósito:** baja fidelidad del shell WhatsApp adaptado a Círculos y composer tipado.

**Alcance:** visión; subset MVP al final.

**Relacionados:** [Índice](00-indice.md) · [Mapa](06-mapa-pantallas.md) · [Diseño visual](10-diseno-visual.md)

---

## 1. Auth

```
┌─────────────────────────────┐
│                             │
│         [Marca]             │
│   Círculos de aprendizaje   │
│                             │
│  ┌───────────────────────┐  │
│  │  Continuar con Google │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

## 2. Home — Mis Círculos

```
┌─────────────────────────────┐
│  [Marca]             🔍  ⋮  │
│  Círculos   Hoy   Ajustes   │
├─────────────────────────────┤
│  🔍 Buscar círculo          │
├─────────────────────────────┤
│  📌 Cohorte Marzo   14:02   │
│  Propósito · Enfocarme…     │
├─────────────────────────────┤
│  Práctica AM         ayer   │
│  Progreso · Módulo 2 80%    │
├─────────────────────────────┤
│  Lecturas             lun   │
│  Ana: ¿duda del temario?    │
├─────────────────────────────┤
│                      ┌───┐  │
│                      │ + │  │  ← Admin: Nuevo Círculo
│                      └───┘  │
└─────────────────────────────┘
```

## 3. Hilo del Círculo

```
┌─────────────────────────────┐
│ ← Cohorte Marzo      ℹ️  ⋮  │
│   12 miembros               │
│  [○ Coin rail de Assign.] →tap│
│  Assignment 1: ○ ○ ✓         │
├─────────────────────────────┤
│ [Todo] Propósito Progreso … │  ← filtros (visión)
├─────────────────────────────┤
│ ┌─────────────────────┐     │
│ │ Propósito           │     │
│ │ Hoy termino la lec. │ 10:01│
│ └─────────────────────┘     │
│     ┌─────────────────┐     │
│     │ Progreso        │     │
│     │ Módulo 2 · 80%  │ 10:05│
│     └─────────────────┘     │
│ ┌─────────────────────┐     │
│ │ (libre) Gracias Ana │ ✓   │
│ └─────────────────────┘     │
├─────────────────────────────┤
│ [Tipo ▾] Escribe…      │📎│🎤│
└─────────────────────────────┘
```

## 4. Assignment sheet (objectives)

```
┌─────────────────────────────┐
│ ← Coin rail            ℹ️  │
│ Assignment: Semana 1       │
│                              │
│ Objectives                    │
│  ☐ purpose                 ✓  │
│  ☐ morning_practice           │
│  ☐ curriculum / doc read     │
│                              │
│ Evidence (mínimo)           │
│  - check / nota / tiempo    │
│  - (visión) link a recurso  │
├─────────────────────────────┤
│ [Marcar completado]         │
│ [Cerrar]                    │
└─────────────────────────────┘
```

## 5. Selector de tipo (sheet)

```
┌─────────────────────────────┐
│  Tipo de publicación        │
│  ○ Propósito del día        │
│  ○ Progreso                 │
│  ○ Currículo / duda         │
│  ○ Práctica de mañana       │
│  ○ Media inspiracional      │
│  ● Mensaje libre            │
└─────────────────────────────┘
```

## 5. Nuevo Círculo (admin)

```
┌─────────────────────────────┐
│ ✕  Nuevo Círculo            │
│ Nombre [ ................ ] │
│ Descripción (opcional)      │
│ Participantes               │
│ ☑ Ana  ☑ Luis  ☐ María      │
│           [ Crear círculo ] │
└─────────────────────────────┘
```

## 6. Info / roster

```
┌─────────────────────────────┐
│ ←  Info del Círculo         │
│      [Avatar] Nombre        │
│  Miembros                   │
│  Ana (admin)                │
│  Luis                       │
│  [ + Añadir ]  (si admin)   │
│  Silenciar · Salir          │
└─────────────────────────────┘
```

## 7. Stories del Círculo (visión)

```
┌─────────────────────────────┐
│  Stories · Cohorte Marzo    │
│  [fullscreen media/texto]   │
│  vistas · cerrar            │
└─────────────────────────────┘
```

## 8. Hoy / Práctica (visión)

```
┌─────────────────────────────┐
│  Hoy                        │
│  [ Publicar propósito ]     │
│  [ Registrar práctica AM ]  │
│  En tus círculos hoy:       │
│  · Cohorte · 4 propósitos   │
└─────────────────────────────┘
```

## Subset MVP

Auth, Home Círculos, Hilo + selector de tipo, Nuevo Círculo, Info básica, Ajustes. Sin Stories, Hoy ni filtros.
