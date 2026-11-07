# Add Item scanner (modal)
> **What:** the three-step Add Item sheet: barcode (or typed name), expiration date, review, then Adding and Added; one large form sheet. **Read when:** you change ScanItemSheet, ScanItemModel or the camera controller.
- Mockup: [scan-item-sheet.html](scan-item-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{ScanItemSheet,ScanCamera,ScanProductHeader,CameraStatusPill}.swift`, `HassCore/Inventory/ScanItemModel.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: modal-sheet, floating-actions
- States covered: default (camera), loading (processing), barcode-found, barcode-notfound, error (camera unavailable), camera-denied, camera-starting, offline (lookup failed), simulated, expiry-camera, expiry-manual, expiry-read, expiry-notfound, expiry-failed, review (+errors, fallback), adding, added, large, closed, ax5
- Motion: camera pill arc, step cut (none), quantity roll. Transitions: present, dismiss, step cut
- Devices: iPhone, Duo folded and unfolded, iPad (540 pt form sheet)
- Open notes: always the large detent (medium and fitted do not exist); the pill texts "Looking Up Product" and "Reading Expiration Date" look unreachable; the catalog hint "step pages cross-fade" is not in the code; camera picture is a stand-in.
