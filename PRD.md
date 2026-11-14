# Product Requirements Document (PRD): SwipeDeck (iOS Photo Declutterer)

* **Platform:** iOS (iPhone Native, iOS 17.0+)
* **Status:** Ready for Development
* **Target Audience:** iPhone users with large, cluttered local camera rolls and Google Photos libraries seeking a fast, low-friction way to free up storage.

## 1. Executive Summary & Core Vision

Managing tens of thousands of photos in a grid view causes decision fatigue. **SwipeDeck** replaces the standard thumbnail grid with a focused, single-card Tinder-style triage interface. Users process one photo or video at a time using fluid swipe gestures—Keep, Trash, or Skip—supported by smart filtering, burst grouping, and a non-destructive safety net before permanent deletion.

## 2. Critical Architectural Constraint: The Google Photos API Limitation

Before development begins, the engineering team must account for a strict platform constraint: **Google's Photos Library API does not permit third-party apps to delete or move photos to the trash if those photos were not originally uploaded by the app itself.**

To address the user's goal of decluttering both the iPhone Camera Roll and Google Photos, the app will operate under two distinct architectural modes:

1. **Primary Mode (Apple PhotoKit / iCloud Photos):** Full native read/write/delete access. If the user has the official Google Photos app installed on their iPhone, deleting a photo via Apple's native `PHPhotoLibrary` automatically syncs the deletion or allows Google Photos' "Free up space" utility to reconcile the changes.
2. **Secondary Mode (Google Photos Cloud Companion):** For cloud-only Google Photos (already removed from the local iPhone), the app authenticates via Google OAuth 2.0 to pull and swipe through images. Because the API blocks direct deletion, swiping "Delete" on cloud-only assets adds them to an app-generated album in Google Photos called **"To Delete - SwipeDeck"**. The user can then open Google Photos, select all items in that album, and move them to the trash in two taps.

## 3. Core User Experience & Gestures

### 3.1 The Card Stack (Main Triage View)

* **Full-Screen Display:** Displays one asset at a time using an aspect-fit container so the entire image is visible without cropping. Pinch-to-zoom is enabled for inspecting focus/details, automatically snapping back on release.
* **Swipe Right (Keep):** Marks the asset as "Reviewed & Kept" in the app's local database so it never appears in future triage sessions. Visual indicator: Green border glow + checkmark badge.
* **Swipe Left (Stage for Deletion):** Places the asset into the app's **Staging Trash Queue**. Visual indicator: Red border glow + trash icon badge.
* **Swipe Up (Push to Back of Stack):** Moves the current asset to the end of the active session's queue for later decision-making. Visual indicator: Blue/Amber upward arrow + subtle shrink animation.
* **Swipe Down (Undo Last Action):** Instantly recalls the previously swiped card (whether Kept, Trashed, or Skipped) back to the top of the deck.
* **Tap Interaction:** Single-tap toggles metadata overlay (Date, Location, File Size, Resolution, Camera/Lens info). Long-press plays Live Photos or scrubs video previews at 2x speed.

## 4. Expanded Functional Requirements

### 4.1 Source Folder & Smart Deck Setup

Users should not be forced to swipe through 50,000 photos chronologically without structure. The Home Dashboard provides **Deck Generators**:

* **By Source:** All Photos, Favorites, Screenshots, Screen Recordings, WhatsApp/Telegram Saved Media, or specific User Albums.
* **By Timeframe:** "On This Day" (historical cleanup across all years), By Month/Year (e.g., *November 2026*), or Custom Date Range.
* **Smart Storage Sieves:**
  * *Heavy Hitters:* Videos and photos sorted by file size (largest first) to maximize storage recovery rapidly.
  * *Similar & Burst Grouping:* Automatically groups photos taken within 3 seconds of each other into a "Mini-Deck" with a split-screen comparison toggle to pick the sharpest shot and trash the rest in one swipe.
  * *Blurry / Dark Detector:* Uses Apple's local `Vision` framework (`VNDetectFaceCaptureQualityRequest` & laplacian variance) to flag out-of-focus shots and pocket photos.

### 4.2 What "Delete" Really Means (Two-Stage Deletion Pipeline)

To prevent accidental data loss and avoid interrupting the user's swipe rhythm with iOS system pop-ups after every swipe, deletion follows a two-stage pipeline:

1. **Stage 1 — The Staging Trash Bin (In-App):** Swiping left moves the photo's `localIdentifier` into an in-app staging queue. A counter at the top right of the screen displays the running total of staged items and total megabytes/gigabytes to be saved (e.g., `🗑️ 42 items (318 MB)`).
2. **Stage 2 — Batch Commit (System Trash):** When the user finishes a deck, closes a session, or taps the Trash counter, they enter the **Review & Commit Sheet**. Here they see a compact grid of all left-swiped items (allowing them to tap any mistake to rescue it). Tapping **"Delete 42 Items"** triggers a *single* native iOS `PHAssetChangeRequest.deleteAssets` confirmation prompt.
3. **Stage 3 — OS Safety Net:** Confirmed items move to iOS's native "Recently Deleted" album, where Apple retains them for 30 days before permanent eradication.

### 4.3 Session Persistence & State Management

* **Reviewed Ledger:** The app tracks every `localIdentifier` marked as "Keep" in local storage (`SwiftData`). When a user opens a folder or month again, already-kept photos are filtered out automatically (with a toggle to "Include previously kept photos" if desired).
* **Session Checkpoints:** Every swipe writes asynchronously to local storage so force-closing the app never loses the current deck order or staged trash queue.

## 5. Technical Stack

| Layer | Technology Choice | Rationale |
| --- | --- | --- |
| **Language & UI** | Swift 6 + SwiftUI | Native 120Hz ProMotion gesture physics, low memory footprint, modern concurrency (`async/await`). |
| **Media Engine** | Apple `PhotoKit` (`PHCachingImageManager`) | Essential for pre-fetching and decoding the next 5–10 images in the stack for zero-latency swiping. |
| **Local Database** | `SwiftData` (SQLite) | Stores reviewed asset IDs, staged trash queues, deferred queue positions, and lifetime storage saved stats. |
| **On-Device AI** | Apple `Vision` + `CryptoKit` | Detects blurry images, duplicate perceptual hashes, and text-heavy screenshots entirely offline. |
| **Cloud Integration** | `GoogleSignIn-iOS` + REST API | Handles OAuth 2.0 and album staging for cloud-only Google Photos libraries. |

## 6. Design System & UI Specifications

### 6.1 Visual Identity & Theme

* **Color Palette:** Pure OLED Dark Mode (`#000000` background, `#1C1C1E` elevated surfaces) by default. Dark backgrounds prevent color-cast illusions and let photography stand out cleanly without visual fatigue.
* **Semantic Accents:**
  * **Keep (Right):** Emerald Green (`#30D158`)
  * **Delete (Left):** Coral Red (`#FF453A`)
  * **Defer/Back of Stack (Up):** Electric Blue (`#0A84FF`)
  * **Undo (Down):** Amber (`#FFD60A`)
* **Typography:** `SF Pro Rounded` for headers and stats counters; `SF Mono` for technical metadata overlays (file size, dimensions, ISO/shutter speed).

### 6.2 Layout & Ergonomics (One-Handed Thumb Zone)

* **Top Bar (Minimal):** Back button, Deck Progress Bar (e.g., `142 / 300`), and the Interactive Trash Staging Pill (`🗑️ 28 • 145 MB`).
* **Center Canvas (82% Screen Height):** The active card with a subtle 3D depth effect showing the next two cards scaled down slightly behind it (`scale: 0.95` and `0.90`).
* **Bottom Action Dock (10% Screen Height):** Four circular glassmorphic (`UltraThinMaterial`) buttons mirroring the gestures (`Undo`, `Trash`, `Skip`, `Keep`) for users who prefer tapping over swiping during long sessions.

### 6.3 Haptics & Micro-Interactions

* **Threshold Haptic:** Trigger `UIImpactFeedbackGenerator(style: .light)` the exact millisecond a dragged card crosses the 120pt commit threshold (telling the user's thumb that releasing the screen will execute the swipe).
* **Commit Haptic:** Medium impact on Trash; soft impact on Keep; rigid double-tap haptic on Batch Delete execution.
* **Spring Physics:** Card snap-back and fly-off animations must use critically damped spring physics (`response: 0.32, dampingFraction: 0.78`) that inherit the user's gesture velocity (`UIPanGestureRecognizer.velocity`).

## 7. Performance & Edge-Case Requirements (For QA)

* **iCloud Uncached Assets:** If an image is stored in iCloud with "Optimize iPhone Storage" enabled, display the high-res local thumbnail immediately while streaming the full asset in the background (`isNetworkAccessAllowed = true`), showing a subtle cloud spinner in the corner only if the user zooms in or plays a video.
* **Memory Ceiling:** Image pre-fetching (`PHCachingImageManager`) must cap decoded bitmap cache at target screen resolution (`UIScreen.main.bounds.size * scale`), never loading raw 48MP ProRAW buffers into RAM unless the user pinches to zoom past 200%.
* **Live Photos & Videos:** Videos autoplay muted with a visible scrubber bar at the bottom of the card. A floating speaker toggle enables audio for the session.

## 8. Suggested Development Phases (MVP to V1.1)

1. **Milestone 1 (Core Engine - Weeks 1–2):** `PhotoKit` permissions, `PHCachingImageManager` pre-fetch pipeline, SwiftUI 60/120fps swipe physics, and `SwiftData` ledger for Kept/Skipped/Staged states.
2. **Milestone 2 (Source Filtering & Batch Commit - Week 3):** Album/Month/Screenshot deck selectors, staging trash review grid, and storage saved celebration screen.
3. **Milestone 3 (Smart Features & Google Photos - Week 4):** On-device `Vision` blur/burst grouping and Google Photos OAuth album-staging integration.
