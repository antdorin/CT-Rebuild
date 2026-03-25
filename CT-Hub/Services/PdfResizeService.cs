using System.IO;
using PdfSharp.Drawing;
using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;

namespace CTHub.Services;

/// <summary>Parameters passed from the scale dialog to PdfResizeService.</summary>
public record PdfScaleOptions(
    double ScaleX,
    double ScaleY,
    int    Dpi
);

public static class PdfResizeService
{
    // Standard page sizes in points (1 pt = 1/72 inch)
    public static readonly IReadOnlyDictionary<string, (double W, double H)> Presets =
        new Dictionary<string, (double, double)>
        {
            ["Letter"]  = (612,  792),
            ["Legal"]   = (612, 1008),
            ["A4"]      = (595.28, 841.89),
            ["A3"]      = (841.89, 1190.55),
            ["Tabloid"] = (792, 1224),
        };

    /// <summary>
    /// Scales all pages of <paramref name="inputPath"/> using <paramref name="opts"/>
    /// and saves the result alongside the original. Returns the output file path.
    /// </summary>
    public static string Scale(string inputPath, PdfScaleOptions opts)
    {
        var dir     = Path.GetDirectoryName(inputPath)!;
        var name    = Path.GetFileNameWithoutExtension(inputPath);
        var xPct    = (int)Math.Round(opts.ScaleX * 100);
        var yPct    = (int)Math.Round(opts.ScaleY * 100);
        var suffix  = xPct == yPct ? $"{xPct}pct" : $"x{xPct}_y{yPct}";
        var outPath = Path.Combine(dir, $"{name}_scaled_{suffix}.pdf");

        using var outDoc = new PdfDocument();
        using var form   = XPdfForm.FromFile(inputPath);

        for (int i = 0; i < form.PageCount; i++)
        {
            form.PageIndex = i;

            var newW = form.PointWidth  * opts.ScaleX;
            var newH = form.PointHeight * opts.ScaleY;

            var page    = outDoc.AddPage();
            page.Width  = XUnit.FromPoint(newW);
            page.Height = XUnit.FromPoint(newH);

            using var gfx = XGraphics.FromPdfPage(page);
            gfx.DrawImage(form, new XRect(0, 0, newW, newH));
        }

        outDoc.Save(outPath);
        return outPath;
    }

    /// <summary>
    /// Calculates X/Y scale factors to fit source page dimensions to a named preset.
    /// </summary>
    public static (double sx, double sy) ScaleForPreset(
        string presetName, double srcW, double srcH)
    {
        var (pw, ph) = Presets[presetName];
        return (pw / srcW, ph / srcH);
    }
}
