# NetSuite Integration Plan (Resume Notes)

## Last Updated
- Date: 2026-03-26
- Workspace: CT-Rebuild-main / CT-Hub
- Purpose: Leave a complete implementation roadmap so work can resume quickly.

## Current Working Baseline
The following is already implemented and working in CT-Hub:

1. Dev Tools CDP connectivity
- Discovers tabs from configured endpoint (default http://127.0.0.1:9222)
- Connects/disconnects to selected tab
- Logs network events in the Dev Tools panel

2. Browser launch automation
- Launch browser for CDP with configurable browser type/path
- Optional local profile usage
- Optional profile snapshot mode for reliability
- Optional direct local profile mode for full fidelity
- Auto-refresh tabs and optional auto-connect first tab

3. Profile usability features
- Detect Profiles scans local User Data directory and lists available profile folders

### Relevant existing files
- Main UI: MainWindow.xaml
- Dev Tools logic: MainWindow.xaml.cs
- CDP transport/service: Services/CdpDevToolsService.cs
- Settings persistence: Services/AppSettings.cs

## Primary Goal (Next Phase)
Implement NetSuite quantity sync pipeline, starting with Tough Hooks, with a safe preview-first workflow:

1. Capture candidate inventory payloads from NetSuite responses
2. Parse into normalized rows (SKU, Qty, optional metadata)
3. Show preview + diff against current CT-Hub data
4. Apply selected updates to CT-Hub stores
5. Record run results and errors for auditability

## Scope and Sequencing
### Phase 1: Dev-mode capture and parsing (fastest path)
Use existing CDP connection to intercept the NetSuite web app traffic while user is logged in.

Deliverables:
1. Capture full response body for matching requests (not just URL/status)
2. Rule-based endpoint filter (contains regex/text)
3. JSON parser templates for common payload shapes
4. Preview grid in Dev Tools tab
5. Manual Apply button to update Tough Hooks quantities

### Phase 2: Hardened sync UX
Deliverables:
1. Dry-run mode default
2. Apply modes: overwrite, non-zero-only, update-missing-only
3. Conflict handling and duplicate SKU reporting
4. Import summary report (counts + failures)
5. Last successful mapping/rule persistence in settings

### Phase 3: Optional production path
Evaluate direct NetSuite API integration (REST/SuiteTalk) to avoid CDP dependency.

Deliverables:
1. API auth flow decision (token/OAuth/service account)
2. Endpoint contract and field mapping
3. Scheduled sync job (manual + periodic)
4. Retry/backoff and resilient error handling

## Data Contract (Internal Normalized Row)
Create an internal model used across parser, preview, and apply:

- Source: NetSuite/CDP
- SKU: string (required)
- Quantity: int (required; parse failure tracked)
- Location: string? (optional)
- Timestamp: DateTime
- RawReference: string? (optional request URL or source id)
- Notes: string? (optional)

Suggested class (new file):
- Models/DevSyncRow.cs

## Proposed File-Level Work Plan
### 1) CDP service enhancements
File: Services/CdpDevToolsService.cs

Add:
1. Method to request body for a response id via CDP command:
- Network.getResponseBody
2. Event that emits enriched network payload object:
- URL, status, mime, requestId, responseBody (when available)
3. Configurable capture limits:
- max body size, include/exclude mime types

### 2) Parsing/mapping service
New file: Services/NetSuiteSyncParser.cs

Add:
1. Parse method that accepts response body + mapping configuration
2. Handles common patterns:
- Array of item objects
- Nested inventory lists
- String quantities needing normalization
3. Returns:
- list of normalized rows
- warnings/errors

### 3) Dev Tools preview state and commands
File: MainWindow.xaml.cs

Add:
1. ObservableCollection for preview rows and parse diagnostics
2. Selected filter rule + parser template state
3. Commands:
- Capture latest matching response
- Parse to preview
- Apply to Tough Hooks
- Clear preview

### 4) Dev Tools UI additions
File: MainWindow.xaml

Add controls:
1. Filter rule editor (text/regex)
2. Template selector (predefined parser templates)
3. Preview DataGrid with columns:
- SKU
- Parsed Qty
- Existing Qty
- Delta
- Action (Update/Skip)
4. Buttons:
- Parse Latest
- Apply Preview
- Export Preview CSV (optional but useful)

### 5) Settings for sync behavior
File: Services/AppSettings.cs

Add persisted settings:
1. NetSuiteFilterRule
2. NetSuiteParserTemplate
3. NetSuiteApplyMode
4. NetSuiteLastRunAt / LastRunSummary (optional)

## Apply Logic (Tough Hooks first)
File: MainWindow.xaml.cs (or dedicated service later)

Algorithm:
1. Build dictionary from ToughHookItems by SKU (trim + case-insensitive)
2. For each parsed row:
- if SKU missing => warning
- if SKU not found => unassigned list
- if found and qty changed => stage update
3. Show summary before write:
- total parsed
- matched
- changed
- unchanged
- missing SKU
- parse errors
4. Commit updates via existing store upsert pipeline

Safety:
- Dry run should be default
- Require explicit confirmation before write

## Recommended Apply Modes
1. OverwriteAlways
- Set Qty exactly to parsed value

2. SkipZeroIncoming
- Ignore updates where parsed qty == 0

3. OnlyIfDifferent
- Update only when existing qty != parsed qty

4. FillMissingOnly
- Update only when existing qty is blank/zero

## Acceptance Criteria (Phase 1 complete)
1. User can connect Dev Tools and capture a NetSuite response body
2. Parser produces a preview with SKU/Qty rows
3. Preview shows row-level match status against Tough Hooks
4. User can apply updates and see successful quantity changes in Tough Hooks grid
5. A run summary is shown and logged

## Testing Checklist
### Manual tests
1. Happy path payload with known SKUs
2. Payload with unknown SKUs
3. Non-numeric qty values
4. Empty payload or malformed JSON
5. Duplicate SKU rows in payload
6. Large payload performance sanity check

### Regression checks
1. Existing Chase/ToughHooks bulk import still works
2. CDP connect/disconnect still works
3. App builds and runs with no binding errors

## Operational Notes / Caveats
1. CDP path depends on browser profile/login/session health
2. Snapshot mode may not always include current authenticated session tokens
3. Direct local profile mode is higher fidelity but can fail if browser already running
4. NetSuite UI/API shape can change; parser templates should be easy to edit

## Open Questions To Confirm When Resuming
1. Target dataset: Tough Hooks only first, then Chase?
2. Authoritative key: SKU only, or SKU + location?
3. Quantity source semantics: available, on-hand, committed, or custom field?
4. Required cadence: manual button only or scheduled sync?
5. Conflict policy preference: overwrite vs conservative updates?

## Immediate Next Coding Task (Resume Point)
When work resumes, start here exactly:

1. Extend Services/CdpDevToolsService.cs to retrieve response bodies for matched requests.
2. Add NetSuiteSyncParser service with one initial JSON template (array of objects with sku/qty fields).
3. Add preview grid + Parse Latest + Apply Preview controls in Dev Tools.
4. Wire apply to ToughHookItems with dry-run summary first.

## Build/Run Commands
From repo root:
- dotnet build .\CT-Hub\CT-Hub.csproj -o .\CT-Hub\bin\_verify_build

From CT-Hub folder:
- dotnet run

## Definition of Done (for first usable release)
1. User can connect, capture, parse, preview, and apply Tough Hooks qty updates from NetSuite traffic in one flow.
2. Errors are visible and non-blocking where possible.
3. No regressions in existing import features.
4. Settings persist between app restarts.
