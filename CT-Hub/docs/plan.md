## Plan: Chase Scan Linking Flow

Build a Chase Tactical linking workflow in the iOS scanner that lets an unassigned scanned barcode/QR be linked to an existing item from CT-Hub data, with backend as canonical source and lightweight local cache for speed. Unassigned modal will have two distinct paths: Create New Item (current manual form, unchanged) and Link Existing Catalog Item (new DB-backed search/select flow). The link record must explicitly identify source catalog so similarly named products are never ambiguous (for example, Tough Hook sold by Chase Tactical vs Tough Hook sold by Tough Hook catalog). Support many scanned codes linking to one item.

**Steps**
1. Phase 1: Identity contract and API foundation (blocks UI work)
2. Define unified link identity with required fields: sourceCatalog (chase_tactical or tough_hook), sourceItemId, sourceItemLabelSnapshot, scannedCode, and linkCode (x-xxx). depends on 1
3. Add iOS catalog/link models that carry sourceCatalog so same-name items from different catalogs remain distinct. depends on 2
4. Extend HubClient with fetchChaseTactical() and link CRUD methods that include sourceCatalog in request/response payloads. depends on 3
5. Add CT-Hub link model + HubServer routes (GET/POST/DELETE) backed by JsonStore, validating sourceCatalog and permitting many scanned codes to one source item. depends on 4

6. Phase 2: Active ticket context switch (folder-driven company mode)
7. Add backend PDF context metadata endpoint (or extend existing pdf meta response) to include sourceCatalog derived from ticket folder name, e.g. Picking Ticket (Chase Tactical) => chase_tactical, Picking Ticket (Tough Hook) => tough_hook. depends on 4
8. In iOS PDF viewer flow, when a ticket is opened, persist activeTicketCatalog context as the current company switch for scanning/linking. depends on 7
9. Surface active context badge in scan UI so operator can always see current mode (Chase Tactical vs Tough Hook). depends on 8
10. Enforce context-aware linking default: Link Existing results are pre-filtered to activeTicketCatalog, with explicit override control if needed. depends on 8

11. Phase 3: Backend canonical + local cache sync
12. Extend ScanStore with lightweight link cache keyed by scannedCode and storing sourceCatalog + sourceItemId + linkCode. depends on 4
13. On successful backend save, update local cache immediately; on launch/modal open, refresh from backend and fallback to cache offline. depends on 12 and 5
14. Add retry queue for offline link writes; backend wins on reconciliation. depends on 13

15. Phase 4: Unassigned modal split-flow redesign
16. Preserve Create New Item path exactly as-is (manual class/bin/qty/item inputs, current assign behavior unchanged). depends on 3
17. Add separate Link Existing Catalog Item section driven by backend data and default-filtered by activeTicketCatalog. depends on 10
18. Replace only the old local existing-item picker with catalog search results (label-first with metadata subtitle including catalog/source and bin). depends on 17
19. Selecting a catalog result updates link selection state only; it does not touch Create New Item fields. depends on 18
20. Add Link action that saves backend link + local cache and closes with success feedback. depends on 13 and 19

21. Phase 5: Scan resolution and assigned-item read path
22. Update scan routing to resolve links via cache/backend and open linked item details with explicit source catalog badge. depends on 13 and 20
23. Update assigned modal (or add linked modal) to display sourceCatalog, source item label, bin/class context, and relink controls. depends on 22
24. Preserve many-codes-to-one-item behavior for both chase_tactical and tough_hook source catalogs. depends on 23

20. Phase 5: Validation and guardrails
21. Add stale-link handling when source item disappears or moves catalogs; prompt relink instead of silent failure. depends on 17
22. Add instrumentation for link save/fetch/fallback/retry paths.
23. Add search debouncing and list virtualization safeguards for larger catalogs.

**Relevant files**
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CTRebuild/Views/UnassignedItemModal.swift — keep Create New Item path intact, add separate Link Existing Catalog Item section with source-aware results.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CTRebuild/Views/AssignedItemModal.swift — display source catalog identity and relink controls.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CTRebuild/Views/PdfBrowserView.swift — set active ticket catalog context when opening a ticket and persist switch state.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CTRebuild/Views/BottomPanelView.swift — display active context badge and route scanned codes through source-aware resolver.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CTRebuild/Models/ScanStore.swift — add lightweight link cache including sourceCatalog/sourceItemId/linkCode, plus activeTicketCatalog context and retry metadata.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CTRebuild/Network/HubClient.swift — add catalog fetch, PDF context fetch, and source-aware link CRUD calls.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CT-Hub/HubServer.cs — add source-aware link API routes and PDF context metadata route.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CT-Hub/Services/PdfFolderService.cs — expose folder-derived sourceCatalog mapping for active ticket context.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CT-Hub/Models/ChaseTacticalEntry.cs — source catalog item schema reference for chase_tactical.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CT-Hub/Models/ToughHookEntry.cs — source catalog item schema reference for tough_hook.
- d:/VSCode/CT-Rebuild-workversion/CT-Rebuild-main/CT-Hub/Services/JsonStore.cs — reuse persistence/broadcast patterns for new link store.

**Verification**
1. Backend API checks: verify GET/POST/DELETE link endpoints work, persist across restart, and reject missing/invalid sourceCatalog.
2. iOS modal check: open Unassigned modal after scan, Create New Item path remains unchanged, Link Existing Catalog Item path loads Chase results and links successfully.
3. Disambiguation check: link one scanned code to chase_tactical item and another to tough_hook item with same/similar label; verify resolver displays correct source.
4. Linking rule check: create two different scanned codes linked to one item and verify both resolve correctly.
5. Offline check: with hub unavailable, cached links resolve; new links queue and retry when reconnected.
6. Regression check: existing manual Assign and current local Assigned modal actions still work where applicable.

**Decisions**
- Link cardinality: many scanned codes can link to one source item (2+ codes -> one item allowed).
- Source of truth: backend canonical with lightweight local cache for speed/offline fallback.
- Identity requirement: every link row must include sourceCatalog discriminator so Chase vs Tough Hook items are never conflated.
- Unassigned UX split: Create New Item remains manual-only and untouched; Link Existing Catalog Item is independent and source-aware.
- Initial UX scope: Chase Tactical catalog shown first; tough_hook catalog support is schema-ready and can be enabled next without data migration.

**Further Considerations**
1. Chase search key detail: confirm whether we should expose both label and id/bin in search results, or label-first only with metadata subtitle.
2. Link id format: define whether x-xxx should be generated client-side or backend-side to avoid collisions across devices.
3. Device concurrency: if multiple phones link same scanned code simultaneously, decide last-write-wins vs reject-on-conflict behavior.
