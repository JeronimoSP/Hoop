# 11 — User stories y criterios de aceptación

**Propósito:** historias Given/When/Then. Etiqueta **Visión** o **MVP**.

**Relacionados:** [Índice](00-indice.md) · [Módulos](03-modulos.md) · [Flujos](04-flujos-clave.md) · [MVP](13-diseno-tecnico-mvp-firebase.md)

### US-E5-05 Sticky instrucciones y recursos (admin) · **MVP**

**Given** soy miembro del Círculo **When** el admin publica un `instruction` sticky y un `resource` con link **Then** ambos se muestran arriba del hilo y se pueden consultar durante el cumplimiento.

---

## Épicas

| Épica | Prioridad MVP |
|-------|---------------|
| E1 Auth y perfil | Alta |
| E2 Home de Círculos | Alta |
| E3 Admin: crear Círculo y roster | Alta |
| E4 Hilo y composer tipado | Alta |
| E5 Assignments/Objectives y coin rail (progreso en grupo) | Alta |
| E6 Stories del Círculo | Fuera MVP |
| E7 Hoy / Práctica | Fuera MVP |
| E8 Media archivos | Fase 2 |
| E9 DM | Fuera MVP |
| E10 Challenges (media / quest) | Documentado; implementación por fases ([16](16-challenges-funcional.md)/[17](17-challenges-tecnico.md)) |

---

## E1 — Auth

### US-E1-01 Login Google · **MVP**

**Given** sin sesión **When** completo Google Auth **Then** veo home de Círculos y mi `users/{uid}` existe.

### US-E1-02 Logout · **MVP**

**Given** sesión activa **When** cierro sesión **Then** vuelvo a Auth.

---

## E2 — Home

### US-E2-01 Lista de Círculos · **MVP**

**Given** tengo memberships **When** abro home **Then** veo Círculos ordenados por actividad con preview tipado.

### US-E2-02 Buscar · **MVP**

**Given** varios Círculos **When** filtro por nombre **Then** la lista se reduce.

### US-E2-03 Empty state · **MVP**

**Given** sin Círculos **When** abro home **Then** veo mensaje claro; si soy admin, CTA crear.

---

## E3 — Admin

### US-E3-01 Crear Círculo · **MVP**

**Given** soy admin **When** creo Círculo con nombre y miembros **Then** existen Circle + Memberships y aparece en homes.

### US-E3-02 Añadir miembro · **MVP**

**Given** Círculo existente **When** admin añade un user **Then** ese user ve el Círculo.

### US-E3-03 Member no crea · **MVP**

**Given** soy solo member **When** busco crear Círculo **Then** no tengo la acción (o es rechazada).

---

## E4 — Hilo

### US-E4-01 Abrir hilo · **MVP**

**Given** home **When** tap en Círculo **Then** veo hilo + composer + nombre en cabecera.

### US-E4-02 Mensaje libre · **MVP**

**Given** hilo abierto **When** envío tipo `free` **Then** el post aparece para miembros (realtime).

### US-E4-03 Offline · **MVP**

**Given** sin red **When** envío **Then** pending/failed y sync al recuperar.

---

## E5 — Assignments, Objectives y progreso (coin rail)

### US-E5-01 Admin crea Assignment y Objectives · **MVP**

**Given** soy admin del Círculo **When** creo un `Assignment` y agrego `Objectives` con reglas de completitud **Then** el Assignment aparece en el coin rail y el members puede abrir el assignment sheet.

### US-E5-02 Coin rail muestra objectives · **MVP**

**Given** estoy en el Hilo del Círculo **When** toco la coin de un Assignment **Then** veo la lista de `Objectives` con su evidencia mínima y su estado (pendiente/completado).

### US-E5-03 Marcar objective actualiza coin · **MVP**

**Given** el assignment sheet está abierto **When** marco una objective como completada (según su regla) **Then** la coin se actualiza y el progreso queda consistente en la UI.

### US-E5-04 Evidencia por tipo de objective · **Visión**

**Given** una objective requiere evidencia específica (p. ej. `listen_audio`, `practice_minutes`, `read_doc`) **When** completo siguiendo esa regla **Then** el sistema registra la evidencia asociada y refleja el cumplimiento.

---

## E6 — Stories · **Visión**

### US-E6-01 Publicar y ver story del círculo

**Given** membership **When** publico story **Then** miembros la ven 24 h y puedo ver viewers.

---

## E7 — Hoy · **Visión**

### US-E7-01 Atajos del día

**Given** autenticado **When** abro Hoy **Then** puedo lanzar propósito/práctica y ver resumen del día.

---

## E8 — Media · **Fase 2**

### US-E8-01 Adjunto inspiracional

**Given** Storage habilitado **When** publico tipo `media` **Then** miembros reproducen/abre el archivo.

---

## E10 — Challenges · **Phased**

### US-E10-01 Facilitator creates media challenge

**Given** I am a circle facilitator **When** I create a `media` challenge with an audio or video file and `durationDays` **Then** members of the Circle can see it in the Challenges list.

### US-E10-02 Facilitator creates quest challenge

**Given** I am a circle facilitator **When** I create a `quest` challenge with instructions **Then** members can open it and enroll.

### US-E10-03 Member enrolls

**Given** an active challenge **When** I set start date and daily time and confirm **Then** I have one active enrollment and see Day 1…N progress.

### US-E10-04 Media session completes on playback end

**Given** today’s media session **When** I play the file to the end **Then** the session is `completed` (no separate app timer/gong).

### US-E10-05 Quest session with freeform feedback

**Given** today’s quest session **When** I submit text and/or image and/or audio **Then** the session is `completed`; empty submit is rejected.

### US-E10-06 No double active enrollment

**Given** I already have an active enrollment for a challenge **When** I try to enroll again **Then** the app blocks or opens the existing enrollment.

---

## Backlog MVP ordenado

1. E1  
2. E2  
3. E3  
4. E4 + E5 (coin rail + marking)  
5. E10 Challenges (after media/FCM baseline; see docs 16/17)  

