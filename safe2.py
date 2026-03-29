import re

with open("CTRebuild/Views/PdfBrowserView.swift", "r", encoding="utf-8") as f:
    text = f.read()

# I see it in the file as:
#                     Divider().frame(height: 20).opacity(0.2)
#
#                     modeSegment(label: "PDF", active: viewMode == .pdf) {

bad_ui_pattern = r'modeSegment\(label: "PDF", active: viewMode == \.pdf\) \{.*?case \.reader:\s*EmptyView\(\)\s*\}'
text = re.sub(bad_ui_pattern, '', text, flags=re.DOTALL)

# Delete loadPdfOverrides
funcs_pattern = r'private func loadPdfOverrides\(\) async \{.*?\}'
text = re.sub(funcs_pattern, '', text, flags=re.DOTALL)

# Delete modeSegment 
mode_pattern = r'private func modeSegment.*?\.buttonStyle\(\.plain\)\s*\}'
text = re.sub(mode_pattern, '', text, flags=re.DOTALL)

# Let me fix the empty spaces where bad_ui_pattern was.
with open("CTRebuild/Views/PdfBrowserView.swift", "w", encoding="utf-8") as f:
    f.write(text)

