using System.Collections.Concurrent;
using System.IO;
using System.Text.Json;
using UglyToad.PdfPig;
using UglyToad.PdfPig.Content;

namespace CTHub.Services;

/// <summary>
/// Extracts per-word bounding boxes from PDF files using PdfPig.
/// Results are cached in-memory and optionally written to a sidecar .words.json
/// file so subsequent requests are near-instant.
/// 
/// Coordinate system: PdfPig returns PDF-space coordinates
/// (origin at bottom-left, Y increases upward) — exactly what iOS expects.
/// </summary>
public static class PdfWordExtractor
{
    // In-memory cache: filename → serialised JSON bytes
    private static readonly ConcurrentDictionary<string, byte[]> _cache = new();

    // ── Public API ────────────────────────────────────────────────────────────

    /// <summary>
    /// Returns the word layout JSON for <paramref name="pdfPath"/>.
    /// Cache-hit is a fast dictionary lookup; cache-miss parses the PDF once then caches.
    /// </summary>
    public static byte[] GetWordLayoutJson(string pdfPath)
    {
        // Use path as cache key; invalidate if the file has been modified since we cached.
        var cacheKey = pdfPath;

        // Try disk sidecar first (survives Hub restarts)
        var sidecarPath = pdfPath + ".words.json";
        if (!_cache.ContainsKey(cacheKey) && File.Exists(sidecarPath))
        {
            try
            {
                var sidecarInfo = new FileInfo(sidecarPath);
                var pdfInfo     = new FileInfo(pdfPath);
                if (sidecarInfo.LastWriteTimeUtc >= pdfInfo.LastWriteTimeUtc)
                {
                    var sidecarBytes = File.ReadAllBytes(sidecarPath);
                    _cache[cacheKey] = sidecarBytes;
                    return sidecarBytes;
                }
            }
            catch { /* fall through to re-extract */ }
        }

        if (_cache.TryGetValue(cacheKey, out var cached))
            return cached;

        var json = ExtractAndSerialize(pdfPath);
        _cache[cacheKey] = json;

        // Write sidecar asynchronously so the response is not delayed.
        _ = Task.Run(() =>
        {
            try { File.WriteAllBytes(sidecarPath, json); }
            catch { /* non-critical */ }
        });

        return json;
    }

    /// <summary>Removes a cached entry (call when a PDF file is replaced on disk).</summary>
    public static void Invalidate(string pdfPath) => _cache.TryRemove(pdfPath, out _);

    // ── Extraction ────────────────────────────────────────────────────────────

    private static byte[] ExtractAndSerialize(string pdfPath)
    {
        var pages = new List<PageWordLayout>();

        try
        {
            using var pdf = PdfDocument.Open(pdfPath);
            foreach (var page in pdf.GetPages())
            {
                var words = new List<WordBox>();

                foreach (var word in page.GetWords())
                {
                    var text = word.Text?.Trim();
                    if (string.IsNullOrEmpty(text)) continue;

                    // PdfPig BoundingBox: bottom-left origin, matches iOS PDF-space.
                    var bb = word.BoundingBox;
                    if (bb.Width <= 0 || bb.Height <= 0) continue;

                    words.Add(new WordBox(
                        text,
                        Math.Round(bb.Left,   4),
                        Math.Round(bb.Bottom, 4),
                        Math.Round(bb.Right,  4),
                        Math.Round(bb.Top,    4)
                    ));
                }

                // Sort: top→bottom (descending Y), then left→right.
                words.Sort((a, b) =>
                {
                    var midA = (a.Y0 + a.Y1) / 2.0;
                    var midB = (b.Y0 + b.Y1) / 2.0;
                    var dy   = midB - midA;
                    if (Math.Abs(dy) > 2.0) return dy.CompareTo(0) < 0 ? -1 : 1;
                    return a.X0.CompareTo(b.X0);
                });

                pages.Add(new PageWordLayout(
                    page.Number,
                    Math.Round(page.Width,  4),
                    Math.Round(page.Height, 4),
                    words
                ));
            }
        }
        catch
        {
            // Return empty layout rather than a 500 — iOS falls back to PDFKit.
        }

        return JsonSerializer.SerializeToUtf8Bytes(
            new PdfWordDocument(pages),
            _opts);
    }

    private static readonly JsonSerializerOptions _opts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    // ── DTOs ──────────────────────────────────────────────────────────────────

    private record PdfWordDocument(List<PageWordLayout> Pages);

    private record PageWordLayout(int Page, double Width, double Height, List<WordBox> Words);

    private record WordBox(string Text, double X0, double Y0, double X1, double Y1);
}
