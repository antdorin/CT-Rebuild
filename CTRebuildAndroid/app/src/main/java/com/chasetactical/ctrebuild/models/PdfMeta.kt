package com.chasetactical.ctrebuild.models

data class PdfMeta(
    val name: String,
    val modified: String,
    val pageCount: Int = 0
) {
    /** Filename without extension, for display */
    val displayName: String
        get() = name.removeSuffix(".pdf").removeSuffix(".nl")

    /** ISO date prefix (YYYY-MM-DD) extracted from the modified timestamp */
    val dateLabel: String
        get() = if (modified.length >= 10) modified.substring(0, 10) else ""
}
