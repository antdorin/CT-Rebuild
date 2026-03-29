AI Setup Runbook: CT PDF System

Objective

Build a desktop-hosted PDF service that:

Tracks a selected folder of PDF and NL files.

Serves file list and metadata over HTTP.

Serves raw PDF bytes securely by filename.

Hosts a web PDF reader page.

Supports iOS clients that can list, fetch, and merge PDFs.

Ensure persistence:

Last selected PDF folder survives app restarts.

Reader UI preferences survive page reload.

Required runtime facts

Desktop HTTP host port: 5050.

Desktop app must start server on app startup and stop server on app exit.

PDF source extensions allowed: .pdf and .nl.

Metadata format: filename plus modified timestamp in UTC ISO-8601 string.

Implementation checklist with pass/fail gates

Desktop server lifecycle

Ensure startup initializes and starts HTTP listener.

Ensure shutdown cleanly stops listener and background loops.

Pass condition:

App launch makes endpoint reachable.

App close makes endpoint unreachable.

Folder persistence and live watching

Persist selected folder path in app settings in user AppData.

On app startup, restore folder if path exists.

Attach file watcher for create, delete, rename.

Refresh in-memory file list after each watcher event.

Pass condition:

Pick folder, restart app, same folder auto-loads.

Add/remove file in folder, UI/API list updates without restart.

PDF API endpoints

Implement GET /api/pdfs

Return array of filenames only.

Implement GET /api/pdfs/meta

Return array of objects with name and modified.

Implement GET /api/pdfs/{filename}

Decode URL filename.

Reject traversal patterns:

slash, backslash, dot-dot segments.

Allow only .pdf or .nl.

Resolve full path and verify it stays inside selected folder.

Return:

400 for invalid request

404 for missing file

200 with application/pdf for valid file

Pass condition:

Invalid traversal attempts return 400.

Valid file returns 200 and non-empty binary body.

Static web hosting

Serve files from build output wwwroot directory.

Ensure project copies wwwroot content into output every build.

Block static path traversal.

Pass condition:

Reader page loads from desktop host URL.

Missing file returns 404.

Traversal attempt returns forbidden/error.

Desktop PDF operations

Browse action sets current folder.

Scale action:

Read source page size.

Compute scaling from preset or custom x/y percentages.

Write new file beside source with deterministic suffix.

Delete action:

Delete selected files from current folder.

Pass condition:

Scale produces new valid PDF in same folder.

Delete removes file and list updates.

Web reader behavior

Read file query parameter.

Load pdf.js library and worker.

Request PDF from /api/pdfs/{filename}.

Render and provide controls:

page navigation

zoom

text overrides

search

Persist reader settings in localStorage.

Pass condition:

Direct reader URL opens target file.

Reload preserves previous reader settings.

iOS client behavior

Implement fetchPdfMeta using /api/pdfs/meta.

Fallback to fetchPdfList using /api/pdfs if metadata endpoint fails.

Implement fetchPdf(filename) from /api/pdfs/{encoded}.

Merge grouped documents in-memory for grouped view.

Optional: open hosted reader page by URL.

Pass condition:

iOS list loads with metadata when available.

Fallback list still works if metadata unavailable.

Group merge opens combined PDF.

Endpoint consistency fix

Ensure document listing pages call one of:

/api/pdfs/meta preferred

/api/pdfs fallback

Do not call /api/docs/list unless that route is explicitly implemented.

Pass condition:

Documents page list loads without endpoint mismatch errors.

Validation test suite (manual + API)

Health and startup

Launch desktop app.

Request:

GET http://localhost:5050/api/pdfs

Expected:

HTTP 200

JSON array response

Metadata shape

Request:

GET http://localhost:5050/api/pdfs/meta

Expected each item:

name is non-empty string

modified parses as ISO timestamp

Raw PDF fetch

Pick one filename from metadata.

Request:

GET http://localhost:5050/api/pdfs/{URL-encoded-filename}

Expected:

HTTP 200

Content-Type includes application/pdf

Body size greater than 0

Security negative tests

Request:

GET /api/pdfs/../secret.pdf

GET /api/pdfs/folder/evil.pdf

GET /api/pdfs/test.txt

Expected:

HTTP 400 for each invalid request

Persistence

Select folder in desktop UI.

Restart desktop app.

Expected:

Same folder preselected

/api/pdfs returns files immediately

Watcher live update

While app is running, copy a new PDF into selected folder.

Expected:

Desktop PDF grid updates

/api/pdfs includes new file

Reader integration

Open:

http://localhost:5050/reader.html?file={URL-encoded-filename}

Expected:

Document renders

Navigation works

No endpoint errors in browser console

iOS integration

Set active base URL to desktop host.

Open PDF browser in app.

Expected:

Group list appears

Open group succeeds

Download+merge succeeds

Example HTTP calls for Windows PowerShell

List filenames

Invoke-RestMethod -Uri "http://localhost:5050/api/pdfs" -Method Get

List metadata

Invoke-RestMethod -Uri "http://localhost:5050/api/pdfs/meta" -Method Get

Download one PDF

$name = [uri]::EscapeDataString("Example File.pdf")

Invoke-WebRequest -Uri ("http://localhost:5050/api/pdfs/" + $name) -OutFile ".\downloaded.pdf"

Traversal rejection test

Invoke-WebRequest -Uri "http://localhost:5050/api/pdfs/../x.pdf" -Method Get -SkipHttpErrorCheck

Definition of done

All pass conditions above are true.

No endpoint mismatch remains between server routes and web/iOS consumers.

Reader and iOS flows both load documents from the same backend source.

Folder restore and live updates work across app restarts and filesystem changes.


{
"name": "ct_pdf_setup_checklist",
"version": "1.0.0",
"date": "2026-03-29",
"goal": "Set up and verify the CT PDF backend, web reader, and iOS client integration end-to-end.",
"globalPreconditions": [
"Desktop app project builds successfully.",
"Desktop app can run and bind HTTP listener on port 5050.",
"A test folder exists containing at least 2 PDF files."
],
"steps": [
{
"id": "S001",
"phase": "bootstrap",
"title": "Start desktop host",
"action": [
"Launch the desktop app.",
"Wait until startup completes."
],
"expected": [
"HTTP server is reachable on port 5050.",
"No startup exception is shown."
],
"verify": [
"GET /api/pdfs returns HTTP 200 or an empty array when no folder is selected."
],
"rollback": [
"Stop app.",
"Fix startup/server initialization issues.",
"Relaunch app."
],
"blocking": true
},
{
"id": "S002",
"phase": "config",
"title": "Select PDF source folder",
"action": [
"Use the desktop UI Browse action to select the test folder."
],
"expected": [
"Selected folder path is shown in UI.",
"PDF list populates in UI."
],
"verify": [
"GET /api/pdfs returns filenames from selected folder."
],
"rollback": [
"Re-open folder picker and choose a valid folder.",
"Ensure folder path exists and is readable."
],
"blocking": true
},
{
"id": "S003",
"phase": "api",
"title": "Validate filename list endpoint",
"action": [
"Call GET /api/pdfs."
],
"expected": [
"HTTP 200.",
"Body is a JSON array of strings."
],
"verify": [
"All returned names end with .pdf or .nl.",
"No full file system paths are leaked."
],
"rollback": [
"Fix list filtering and serialization logic."
],
"blocking": true
},
{
"id": "S004",
"phase": "api",
"title": "Validate metadata endpoint",
"action": [
"Call GET /api/pdfs/meta."
],
"expected": [
"HTTP 200.",
"Body is JSON array of objects with name and modified."
],
"verify": [
"modified value parses as ISO-8601 UTC timestamp.",
"Name set matches GET /api/pdfs."
],
"rollback": [
"Fix metadata generation and timestamp formatting."
],
"blocking": true
},
{
"id": "S005",
"phase": "security",
"title": "Validate raw PDF download success path",
"action": [
"Pick a filename from metadata.",
"Call GET /api/pdfs/{url-encoded-filename}."
],
"expected": [
"HTTP 200.",
"Content-Type is application/pdf.",
"Response body size > 0."
],
"verify": [
"Saved file opens as a valid PDF."
],
"rollback": [
"Fix path resolution and file read logic."
],
"blocking": true
},
{
"id": "S006",
"phase": "security",
"title": "Validate traversal and extension guards",
"action": [
"Call GET /api/pdfs/../x.pdf.",
"Call GET /api/pdfs/folder/x.pdf.",
"Call GET /api/pdfs/x.txt."
],
"expected": [
"Each invalid request returns HTTP 400."
],
"verify": [
"No file contents are returned for invalid requests."
],
"rollback": [
"Tighten request validation and normalized path containment checks."
],
"blocking": true
},
{
"id": "S007",
"phase": "static",
"title": "Validate static web hosting",
"action": [
"Open the web reader URL in browser.",
"Open the documents page URL in browser."
],
"expected": [
"Pages load from desktop host without 404.",
"Static assets resolve correctly."
],
"verify": [
"No missing asset errors.",
"Reader UI initializes."
],
"rollback": [
"Ensure web assets are copied to output and static route mapping is correct."
],
"blocking": true
},
{
"id": "S008",
"phase": "compat",
"title": "Fix endpoint mismatch in document list page",
"action": [
"Ensure documents page fetches /api/pdfs/meta (preferred) or /api/pdfs.",
"Do not rely on /api/docs/list unless server implements it."
],
"expected": [
"Documents page loads list successfully."
],
"verify": [
"Network calls from documents page hit an implemented endpoint."
],
"rollback": [
"Revert page fetch URL and implement corresponding server endpoint consistently."
],
"blocking": true
},
{
"id": "S009",
"phase": "desktop",
"title": "Validate scale operation",
"action": [
"Select one PDF in UI.",
"Run scale action with known factor (for example 120%)."
],
"expected": [
"A new scaled file is created in same folder.",
"UI status reports save success."
],
"verify": [
"New filename suffix reflects scale setting.",
"New file appears in list endpoint output."
],
"rollback": [
"Fix scaling pipeline and output naming."
],
"blocking": false
},
{
"id": "S010",
"phase": "desktop",
"title": "Validate delete operation",
"action": [
"Select one or more files in UI.",
"Confirm delete action."
],
"expected": [
"Files are removed from disk.",
"UI and API lists update."
],
"verify": [
"Deleted filenames no longer appear in GET /api/pdfs."
],
"rollback": [
"Restore files from backup/test fixtures.",
"Fix delete selection and path handling."
],
"blocking": false
},
{
"id": "S011",
"phase": "persistence",
"title": "Validate selected-folder restore on restart",
"action": [
"Close desktop app.",
"Relaunch desktop app."
],
"expected": [
"Previously selected folder auto-restores.",
"PDF endpoints return data immediately after restart."
],
"verify": [
"No manual folder reselection is required."
],
"rollback": [
"Fix settings save/load logic and path existence checks."
],
"blocking": true
},
{
"id": "S012",
"phase": "watcher",
"title": "Validate live file watcher updates",
"action": [
"While app is running, add one test PDF to folder.",
"Then rename and delete a test PDF."
],
"expected": [
"Each filesystem change refreshes UI list.",
"Each change appears in API list without restart."
],
"verify": [
"Create/delete/rename events all propagate."
],
"rollback": [
"Reattach watcher handlers and refresh logic."
],
"blocking": true
},
{
"id": "S013",
"phase": "reader",
"title": "Validate web reader load and controls",
"action": [
"Open reader URL with a valid file query parameter.",
"Navigate pages and use search/zoom controls.",
"Reload page."
],
"expected": [
"PDF loads successfully.",
"Controls function correctly.",
"Persisted settings restore after reload."
],
"verify": [
"No reader-side fetch errors.",
"State persistence keys behave consistently."
],
"rollback": [
"Fix reader API URL composition and local state persistence."
],
"blocking": true
},
{
"id": "S014",
"phase": "ios",
"title": "Validate iOS metadata-first with fallback behavior",
"action": [
"Configure active base URL to desktop host.",
"Load PDF browser list.",
"Temporarily force metadata failure and confirm fallback to filename list."
],
"expected": [
"Normal path uses metadata endpoint.",
"Fallback path still lists files."
],
"verify": [
"No crash when metadata endpoint unavailable."
],
"rollback": [
"Fix endpoint fallback logic and decoding."
],
"blocking": true
},
{
"id": "S015",
"phase": "ios",
"title": "Validate iOS download and merge",
"action": [
"Open a group with multiple files.",
"Download and merge into one in-memory document."
],
"expected": [
"Merged document opens and paginates.",
"Repeated open uses cache path if implemented."
],
"verify": [
"Page count equals sum of source documents."
],
"rollback": [
"Fix per-file download and merge insertion order."
],
"blocking": false
}
],
"artifacts": {
"capture": [
"HTTP status and body snippets for /api/pdfs, /api/pdfs/meta, /api/pdfs/{file}.",
"One screenshot each: desktop folder tab, reader loaded state, iOS list view.",
"One security test log showing invalid path request blocked."
]
},
"doneCriteria": [
"All blocking steps pass.",
"No endpoint mismatch exists between server routes and consumers.",
"Folder restore and live watcher updates pass.",
"Reader and iOS both consume the same backend contract successfully."
],
"quickCommands": [
{
"name": "list-pdfs",
"cmd": "Invoke-RestMethod -Uri "http://localhost:5050/api/pdfs\" -Method Get"
},
{
"name": "list-pdf-meta",
"cmd": "Invoke-RestMethod -Uri "http://localhost:5050/api/pdfs/meta\" -Method Get"
},
{
"name": "download-one-pdf",
"cmd": "$n=[uri]::EscapeDataString("Example.pdf"); Invoke-WebRequest -Uri ("http://localhost:5050/api/pdfs/\"+$n) -OutFile ".\downloaded.pdf""
},
{
"name": "negative-traversal-test",
"cmd": "Invoke-WebRequest -Uri "http://localhost:5050/api/pdfs/../x.pdf\" -Method Get -SkipHttpErrorCheck"
}
]
}