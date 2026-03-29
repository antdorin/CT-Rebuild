import re

with open("CTRebuild/Views/PdfBrowserView.swift", "r", encoding="utf-8") as f:
    text = f.read()

# Replace the three brackets with just one
bad_brackets = """        }
    }

    }

    }

    private func statusToggle"""

good_brackets = """        }
    }

    private func statusToggle"""

text = text.replace(bad_brackets, good_brackets)

with open("CTRebuild/Views/PdfBrowserView.swift", "w", encoding="utf-8") as f:
    f.write(text)
