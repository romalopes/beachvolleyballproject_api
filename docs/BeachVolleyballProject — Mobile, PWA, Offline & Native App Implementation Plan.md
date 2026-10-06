# BeachVolleyballProject — Mobile, PWA, Offline & Native App Implementation Plan

## Version 1.0 (Architecture Roadmap)

---

# 1. Vision

Transform **BeachVolleyballProject** into a **mobile-first coaching platform** that works equally well on desktop, tablet and mobile, with full offline capability for beach environments.

The application must support three operational domains:

- **Training**
- **Assessment**
- **Tournament**

The same React application should power:

- Desktop web
- Mobile browser
- Progressive Web App (PWA)
- Android (Capacitor)
- iOS (Capacitor)

Rails remains the only backend and PostgreSQL (Neon) remains the source of truth.

---

# 2. Target Architecture

```text
                        Users
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
   Desktop Browser                    Mobile Device
        │                                   │
        └──────────────┬────────────────────┘
                       │
                React + Vite + TS
                       │
          ┌────────────┴────────────┐
          │                         │
      Online API              IndexedDB
          │                  Offline Store
          │                         │
          └────────────┬────────────┘
                       │
                 Sync Engine
                       │
                 Rails 8 API
                       │
                 Neon PostgreSQL
```

**Principles**

- One React codebase
- One Rails API
- Offline is explicit
- Server is always authoritative
- Local data is temporary and synchronized

---

# 3. Product Modules

## Core modules

- Authentication
- Accounts & People
- Player Profiles
- Coach Profiles
- Groups
- Schedule
- Training
- Drills
- Skills
- Assessments
- Media
- Tournament
- Notifications (future)

## Offline-capable modules

| Module | Offline |
|---|---|
| Training | ✅ Full |
| Drills | ✅ Full |
| Assessments | ✅ Full |
| Tournament | ✅ Full |
| Schedule | ✅ Downloaded events |
| Player profiles | ✅ Downloaded players |
| Media images | ✅ Selected |
| Videos | ⚠ Optional download |

---

# Phase 0 — Architecture Audit

## Objective

Understand the current project before changing anything.

### Frontend audit

Inspect:

- package.json
- vite.config.ts
- tsconfig
- routing
- authentication
- API client
- forms
- state management
- drag/drop system
- drill editor
- current responsive behavior

### Backend audit

Inspect:

- Routes
- Controllers
- Models
- Serializers
- Service Objects
- Authentication
- Authorization
- CORS

### Deliverable

Create:

```text
docs/MOBILE_PWA_ARCHITECTURE.md
```

Include:

- Current architecture
- Data flow
- API endpoints
- Authentication flow
- Offline strategy
- Sync strategy
- Risks

---

# Phase 1 — Mobile First UI

## Goal

Make every screen usable on a phone before introducing offline functionality.

---

## 1.1 Responsive Layout

Target widths:

| Device | Width |
|---|---:|
| Small phone | 375 |
| iPhone | 390 |
| Large phone | 430 |
| Tablet | 768 |
| Desktop | 1024+ |

Use CSS responsive layouts instead of device detection.

---

## 1.2 Navigation

### Desktop

- Top navigation
- Sidebar (optional)

### Mobile

- Compact header
- Hamburger menu
- Quick access to operational screens

Main menu:

- Home
- Schedule
- Training
- Tournament
- Players
- Assessments
- Drills
- Profile

---

## 1.3 Schedule

Schedule becomes the operational home.

Display:

- Upcoming trainings
- Tournaments
- Personal events
- Group events

Mobile cards:

```text
Today
6:00 PM

BBB Mixed

Maroubra Beach

8 Players
```

---

## 1.4 Training UI

Optimize:

- Training list
- Details
- Edit
- Run session

Workflow:

```text
Schedule
   ↓
Training
   ↓
Warm-up
   ↓
Drills
   ↓
Assessment
```

Large touch targets.

Minimal typing.

---

## 1.5 Drill Viewer

Display:

- Court diagram
- Steps
- Players
- Equipment
- Difficulty
- Stage
- Annotation layer

The court should occupy most of the screen.

---

## 1.6 Drill Visual Editor

Support touch interaction for:

- Players
- Ball
- Arrows
- Cones
- Text annotations

Replace mouse-only logic with Pointer Events where possible.

Objects should be draggable with finger or mouse.

---

## 1.7 Player Screens

Display:

- Photo
- Name
- Level
- Groups
- Recent assessments
- Upcoming trainings

Avoid desktop tables.

Use cards.

---

## 1.8 Assessment UI

Workflow:

```text
Player
 ↓
Area
 ↓
Criterion
 ↓
Score
 ↓
Next
```

Features:

- Swipe next player
- Large score buttons
- Optional comments
- Progress indicator

Example:

```text
Attack

Technique

8

[ - ]      [ + ]

Next →
```

---

## 1.9 Tournament UI

Main dashboard:

```text
Summer Tournament

16 Teams

4 Courts

Match 12
Court 2

Team A
vs
Team B
```

Sections:

- Matches
- Courts
- Teams
- Standings
- Schedule

Everything optimized for live operation.

---

# Phase 2 — Progressive Web App

## Goal

Install the application like a native app.

Install:

```bash
npm install -D vite-plugin-pwa
```

---

## 2.1 Manifest

Configure:

- Name
- Short name
- Description
- Icons
- Theme color
- Standalone display

Icons:

- 192×192
- 512×512
- Apple Touch Icon
- Maskable Icon

---

## 2.2 Service Worker

Cache:

- JS
- CSS
- Fonts
- Icons
- Static assets

Do **not** cache authenticated API responses automatically.

---

## 2.3 Connectivity

Show:

- 🟢 Online
- 🟠 Offline

And:

- Synced
- Pending
- Failed

The coach always knows the current state.

---

## 2.4 Updates

When a new deployment exists:

```text
New version available

[Update]
```

Never interrupt an active training or tournament.

---

# Phase 3 — Offline Data Layer

Install:

```bash
npm install dexie
```

## Architecture

```text
React Components
        │
 Repository Layer
        │
 ┌──────┴──────┐
 │             │
Rails API   IndexedDB
        │
   Sync Manager
```

React components never access IndexedDB directly.

---

## Local Stores

Create stores for:

- trainings
- drills
- players
- groups
- assessments
- assessment_results
- tournaments
- teams
- matches
- courts
- standings
- sync_operations

---

## Download Packages

Instead of downloading everything:

### Training Package

Contains:

- Training
- Players
- Drills
- Skills
- Assessment config

### Tournament Package

Contains:

- Tournament
- Teams
- Players
- Courts
- Matches
- Standings

Explicit download button:

```text
Download for Offline Use
```

---

# Phase 4 — Offline Training

## Goal

Run an entire training session without Internet.

---

## Download Training

Downloads:

- Players
- Drills
- Court diagrams
- Assessment structure
- Notes

Show progress.

---

## Run Training

Coach can:

- View drills
- Navigate steps
- Read annotations
- Mark completed drills
- Record notes

Everything saved locally.

---

## Observations

Example:

```text
John

Blocking timing improved.

✓ Saved locally
```

Notes synchronize later.

---

## Training Completion

At the end:

```text
Training Finished

12 Notes

48 Scores

Waiting to Sync
```

---

# Phase 5 — Offline Assessments

## Download

Include:

- Players
- Areas
- Criteria
- Scale
- Weights

---

## Assessment Flow

```text
Player

Attack

Technique

8

Comment

Next
```

Autosave every score.

No Save button required.

---

## Local State

Each result stores:

- Local ID
- Server ID
- Player
- Criterion
- Score
- Comment
- Sync status

Statuses:

- Pending
- Synced
- Failed

---

# Phase 6 — Offline Tournament

## Goal

Operate a complete tournament offline.

This is the biggest operational feature.

---

## Tournament Package

Downloads:

- Teams
- Players
- Courts
- Schedule
- Matches
- Standings
- Rules

---

## Offline Dashboard

```text
Tournament

Court 1

Match 4

21 - 18

Set 2

LIVE
```

---

## Match Screen

Display:

- Court
- Teams
- Sets
- Current score
- Time
- Status

Large score controls.

---

## Live Scoring

Workflow:

```text
Start Match
 ↓
Point
 ↓
Point
 ↓
Finish Set
 ↓
Next Set
 ↓
Finish Match
```

Every point saved locally.

---

## Standings

Standings update immediately after match completion.

Calculated locally.

Server validates later.

---

## Court Management

Organizer can move matches between courts offline.

Changes synchronize later.

---

## Recovery

If phone closes:

- Match resumes
- Score preserved
- Timer restored where possible

---

# Phase 7 — Synchronization Engine

A single engine serves every module.

```text
Training
Assessment
Tournament
       │
       ▼
 Sync Operations
       │
       ▼
 Rails API
```

---

## Sync Queue

Each operation stores:

- Entity
- Action
- Payload
- Attempts
- Status
- Error

Example:

```text
Match Score

Pending
```

---

## Retry Strategy

Automatic retry:

- Network restored
- Temporary server errors
- Background sync when app opens

Permanent validation errors require user review.

---

## Conflict Handling

Example:

```text
Server

21–19

Local

21–18
```

User chooses:

- Keep local
- Keep server
- Review

Never overwrite silently.

---

# Phase 8 — Security

## User Isolation

If User A logs out:

- Offline data removed
- Tokens removed
- Cache cleared

User B never sees User A's data.

---

## Logout Protection

If pending changes exist:

```text
3 unsynchronized changes.

Sync before logout?
```

Prevent accidental data loss.

---

## Sensitive Data

Never cache:

- Passwords
- Tokens in plain text
- Private admin data

Only authorized downloaded data remains locally.

---

# Phase 9 — Real Device Testing

## Android

Test:

- Install
- Offline
- Training
- Tournament
- Assessment
- Rotation
- Sleep/Wake

## iPhone

Test:

- Add to Home Screen
- Offline startup
- Safari behavior
- Storage
- Synchronization

---

# Phase 10 — Capacitor

Only after PWA is stable.

Install:

```bash
npm install @capacitor/core
npm install -D @capacitor/cli
npm install @capacitor/android
npm install @capacitor/ios
```

The same React UI becomes:

- Android App
- iOS App

No duplicated frontend.

---

## Native Features (Later)

Potential plugins:

| Feature | Purpose |
|---|---|
| Camera | Player & drill photos |
| Filesystem | Offline media |
| Share | Share drills & tournaments |
| Push | Training reminders |
| Geolocation | Beach locations |

Only implement when needed.

---

# Phase 11 — App Store Distribution

## Android

- Google Play Console
- Icons
- Screenshots
- Privacy policy
- Signed build

## iOS

- Apple Developer
- TestFlight
- App Store Connect
- Privacy declarations

---

# Phase 12 — Monitoring

Track:

- Sync failures
- API failures
- Offline usage
- Tournament conflicts
- Assessment sync errors
- Client crashes

Important KPI:

```text
Offline → Successful Sync %
```

This is more valuable than simple API uptime.

---

# Priority Matrix

| Feature | Priority |
|---|---|
| Mobile UI | 🔴 Essential |
| Schedule | 🔴 Essential |
| Training | 🔴 Essential |
| Drills | 🔴 Essential |
| Assessments | 🔴 Essential |
| Tournament | 🔴 Essential |
| PWA | 🔴 Essential |
| Offline Training | 🔴 Very High |
| Offline Assessments | 🔴 Very High |
| Offline Tournament | 🔴 Very High |
| Shared Sync Engine | 🔴 Very High |
| Conflict Resolution | 🔴 Very High |
| Camera | 🟡 Later |
| Push Notifications | 🟡 Later |
| Video Download | 🟡 Later |
| Capacitor | 🟡 Later |
| React Native | 🟢 Only if required |

---

# Final User Experience

A coach's day should look like this:

```text
Morning
   ↓
Open Schedule
   ↓
Download Training
   ↓
Travel to Beach
   ↓
OFFLINE
   ↓
Run Training
   ↓
View Drills
   ↓
Assess Players
   ↓
Record Notes
   ↓
Finish Session
   ↓
Leave Beach
   ↓
Internet Returns
   ↓
Automatic Synchronization
   ↓
✓ Everything Saved
```

A tournament organizer should have the same experience:

```text
Download Tournament
        ↓
Operate Courts
        ↓
Live Scoring
        ↓
Standings Update
        ↓
Finish Tournament
        ↓
Reconnect
        ↓
Automatic Sync
        ↓
Official Results Published
```

The end goal is not simply having a mobile app—it is providing a **reliable offline coaching and tournament platform** where Training, Assessments, and Tournaments are first-class citizens built on one React frontend and one Rails backend.