# 15 — Plan de implementación: MVP Flutter + Firebase

**Propósito:** app Flutter (iOS/Android) que implementa el contrato de [doc 13](13-diseno-tecnico-mvp-firebase.md).

**Fuentes:** [13 MVP](13-diseno-tecnico-mvp-firebase.md) · [11 Stories](11-user-stories.md) · [10 Visual](10-diseno-visual.md) · wireframe [`../wireframe/`](../wireframe/) (referencia UX).

**Código:** [repo root](../)

---

## Objetivo

1. Entregar épicas E1–E5 (Auth, Home, Admin, Hilo, Coins) sobre Firestore realtime.
2. Reutilizar el modelo y rules del doc 13 sin cambiar collections.
3. UI alineada a tokens de [doc 10](10-diseno-visual.md).

---

## Stack fijo

| Pieza | Elección |
|-------|----------|
| Cliente | Flutter iOS + Android |
| Estado | `flutter_riverpod` |
| Rutas | `go_router` |
| Firebase | `firebase_core`, `firebase_auth`, `google_sign_in`, `cloud_firestore`, `firebase_storage`, `firebase_messaging` |

Fuera de alcance pendiente: Stories, Hoy, DM. Storage (Fase 2a) y FCM (Fase 2b) **incluidos**.

---

## Estructura del proyecto

```
circulo/
  lib/
    main.dart
    firebase_options.dart
    app.dart
    core/          # theme, errores
    data/          # repos Firestore + Storage
    domain/        # modelos
    features/      # auth, home, thread, coins, admin, settings
    router/
  firestore.rules
  firestore.indexes.json
  storage.rules
  functions/       # generatePdfCover + notifyOnNewPost (Node 20)
  firebase.json
```

---

## Épicas (orden)

| Épica | Entrega |
|-------|---------|
| E1 Auth | Google Sign-In, upsert `users/{uid}`, gate de rutas, logout |
| E2 Home | memberships → circles, preview `lastPost`, búsqueda, empty state |
| E3 Admin | crear círculo + roster, Info, FAB solo admin/platform |
| E4 Hilo | posts realtime, composer tipado, sticky/recursos, pending→sent |
| E5 Coins | assignments + objectives + progressLogs, coin rail, sheet |
| E8 Media | Imágenes, PDF, audio (voz) y video vía Storage; covers PDF/video por CF |
| E9 Push | FCM: tokens en `users/{uid}/fcmTokens`; CF `notifyOnNewPost`; deep link al hilo |
| E10 Challenges | Sibling to coins: `media` (play file) or `quest` (freeform feedback); enroll + daily time; phases in [doc 16](16-challenges-funcional.md) / [doc 17](17-challenges-tecnico.md) |

---

## Setup Firebase (operador)

1. Crear proyecto Firebase; habilitar Auth Google y Firestore.
2. `flutterfire configure` → genera `lib/firebase_options.dart`.
3. Añadir SHA-1 (Android) / URL schemes (iOS) para Google Sign-In.
4. Desplegar `firestore.rules`, índices, `storage.rules` y (Blaze) `functions`.
5. Marcar `isPlatformAdmin: true` en el usuario facilitador.

Hasta que exista un proyecto real, la app usa placeholders en `firebase_options.dart` y no arranca Auth/Firestore contra producción.

---

## Criterios de aceptación (smoke)

- Login Google crea/lee `users/{uid}` y muestra home.
- Member no crea círculo; admin/platform sí.
- 2 clientes: post `free` y progreso de objective visibles en realtime.
- Coin rail refleja objectives + progressLogs.
- Imagen adjunta en hilo visible en realtime; preview home “Imagen” o caption.
- PDF adjunto: burbuja con portada (tras CF) y descarga; preview home “PDF” o caption.
- Nota de voz (mantener mic) y video ≤60 s reproducibles en el hilo.
- Rules bloquean lectura de posts sin membership.
- FCM: dos usuarios en un círculo; A en background; B publica; A recibe push; tap abre el hilo; el autor no se notifica a sí mismo.
- Challenges (when implemented): facilitator creates media + quest; member enrolls; media day completes on playback end; quest day accepts text/image/audio feedback.

---

## Relación con el wireframe

El HTML en [`../wireframe/`](../wireframe/) permanece como prototipo clicable ([doc 14](14-plan-wireframe-html.md)). Este plan es el siguiente paso: app real.
