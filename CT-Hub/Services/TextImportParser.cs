using System.Text.RegularExpressions;
using CTHub.Models;

namespace CTHub.Services;

public sealed class ChaseBulkImportRow
{
    public required ChaseTacticalEntry Entry { get; init; }
    public required int SourceLine { get; init; }
    public bool HadUnknownQty { get; init; }

    public string Key => $"{Entry.Bin}|{Entry.Label}";
}

public sealed class ChaseBulkImportParseResult
{
    public List<ChaseBulkImportRow> Rows { get; } = [];
    public List<string> Errors { get; } = [];
}

public sealed class ToughHookBulkImportRow
{
    public required ToughHookEntry Entry { get; init; }
    public required int SourceLine { get; init; }
}

public sealed class ToughHookBulkImportParseResult
{
    public List<ToughHookBulkImportRow> Rows { get; } = [];
    public List<string> Errors { get; } = [];
}

public static class TextImportParser
{
    private static readonly Regex _binPattern = new(
        "^[1-3]-[AB]-[1-6][A-F]$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    private static readonly Regex _binAtEndPattern = new(
        "([1-3]-[AB]-[1-6][A-F])\\s*$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    private static readonly Regex _qtyAtEndPattern = new(
        "(\\?|\\d+)\\s*$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    private static readonly Regex _binTokenPattern = new(
        "^[1-3]-[AB]-[1-6][A-F]$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    private static readonly Regex _qtyTokenPattern = new(
        "^(\\?|\\d+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex _skuTokenPattern = new(
        "^[A-Za-z0-9][A-Za-z0-9._-]{1,}$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static ChaseBulkImportParseResult ParseChaseTacticalTsv(string content)
    {
        var result = new ChaseBulkImportParseResult();

        if (string.IsNullOrWhiteSpace(content))
            return result;

        var lines = content.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

        for (var i = 0; i < lines.Length; i++)
        {
            var rawLine = lines[i];
            if (string.IsNullOrWhiteSpace(rawLine))
                continue;

            var trimmedLine = rawLine.Trim();
            var binMatch = _binAtEndPattern.Match(trimmedLine);
            if (!binMatch.Success)
            {
                result.Errors.Add($"Line {i + 1}: could not find a valid bin token.");
                continue;
            }

            var bin = binMatch.Groups[1].Value.Trim().ToUpperInvariant();
            var beforeBin = trimmedLine[..binMatch.Index].TrimEnd();

            var qtyToken = "?";
            var label = beforeBin;
            var qtyMatch = _qtyAtEndPattern.Match(beforeBin);
            if (qtyMatch.Success)
            {
                qtyToken = qtyMatch.Groups[1].Value.Trim();
                label = beforeBin[..qtyMatch.Index].TrimEnd();
            }

            label = label.Trim();

            if (string.IsNullOrWhiteSpace(label))
            {
                result.Errors.Add($"Line {i + 1}: label is required.");
                continue;
            }

            if (!_binPattern.IsMatch(bin))
            {
                result.Errors.Add($"Line {i + 1}: invalid bin '{bin}'.");
                continue;
            }

            var hadUnknownQty = false;
            var qty = 0;

            if (string.Equals(qtyToken, "?", StringComparison.Ordinal))
            {
                hadUnknownQty = true;
            }
            else if (!int.TryParse(qtyToken, out qty) || qty < 0)
            {
                result.Errors.Add($"Line {i + 1}: qty must be a non-negative number or '?'.");
                continue;
            }

            result.Rows.Add(new ChaseBulkImportRow
            {
                SourceLine = i + 1,
                HadUnknownQty = hadUnknownQty,
                Entry = new ChaseTacticalEntry
                {
                    Bin = bin,
                    Label = label,
                    Qty = qty
                }
            });
        }

        return result;
    }

    public static ToughHookBulkImportParseResult ParseToughHooks(string content)
    {
        var result = new ToughHookBulkImportParseResult();

        if (string.IsNullOrWhiteSpace(content))
            return result;

        var normalized = content.Replace("\r\n", "\n").Replace('\r', '\n');
        var rawLines = normalized.Split('\n');

        var nonEmpty = new List<(int SourceLine, string Text)>();
        var separatorLine = -1;

        for (var i = 0; i < rawLines.Length; i++)
        {
            var text = rawLines[i].Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                if (separatorLine < 0 && nonEmpty.Count > 0)
                    separatorLine = i + 1;
                continue;
            }

            nonEmpty.Add((i + 1, text));
        }

        if (TryParseToughHooksTwoBlock(nonEmpty, separatorLine, result))
            return result;

        foreach (var line in nonEmpty)
        {
            if (!TryParseToughHookLine(line.Text, out var entry, out var error))
            {
                result.Errors.Add($"Line {line.SourceLine}: {error}");
                continue;
            }

            result.Rows.Add(new ToughHookBulkImportRow
            {
                SourceLine = line.SourceLine,
                Entry = entry
            });
        }

        return result;
    }

    private static bool TryParseToughHooksTwoBlock(
        IReadOnlyList<(int SourceLine, string Text)> nonEmpty,
        int separatorLine,
        ToughHookBulkImportParseResult result)
    {
        if (separatorLine < 0)
            return false;

        var descriptions = nonEmpty
            .Where(x => x.SourceLine < separatorLine)
            .ToList();
        var skus = nonEmpty
            .Where(x => x.SourceLine > separatorLine)
            .ToList();

        if (descriptions.Count == 0 || skus.Count == 0 || descriptions.Count != skus.Count)
            return false;

        if (!skus.All(x => IsLikelySku(x.Text)))
            return false;

        for (var i = 0; i < descriptions.Count; i++)
        {
            var desc = descriptions[i].Text.Trim();
            var sku = skus[i].Text.Trim();
            if (string.IsNullOrWhiteSpace(desc) || string.IsNullOrWhiteSpace(sku))
            {
                result.Errors.Add($"Pair {i + 1}: description and SKU are required.");
                continue;
            }

            result.Rows.Add(new ToughHookBulkImportRow
            {
                SourceLine = skus[i].SourceLine,
                Entry = new ToughHookEntry
                {
                    Description = desc,
                    Sku = sku,
                    Bin = "—",
                    Qty = 0
                }
            });
        }

        return true;
    }

    private static bool TryParseToughHookLine(string line, out ToughHookEntry entry, out string error)
    {
        entry = new ToughHookEntry();
        error = string.Empty;

        var columns = SplitToughHookColumns(line);
        if (columns.Count == 0)
        {
            error = "no data found.";
            return false;
        }

        string? bin = null;
        var binIndex = columns.FindIndex(c => _binTokenPattern.IsMatch(c));
        if (binIndex >= 0)
        {
            bin = columns[binIndex].ToUpperInvariant();
            columns.RemoveAt(binIndex);
        }

        int qty = 0;
        var qtyIndex = columns.FindLastIndex(c => _qtyTokenPattern.IsMatch(c));
        if (qtyIndex >= 0)
        {
            var token = columns[qtyIndex];
            columns.RemoveAt(qtyIndex);
            if (!string.Equals(token, "?", StringComparison.Ordinal) && (!int.TryParse(token, out qty) || qty < 0))
            {
                error = "qty must be a non-negative number or '?'.";
                return false;
            }
        }

        if (columns.Count == 0)
        {
            error = "missing SKU/description fields.";
            return false;
        }

        string sku;
        string description;

        if (columns.Count == 1)
        {
            if (!IsLikelySku(columns[0]))
            {
                error = "could not identify SKU.";
                return false;
            }

            sku = columns[0];
            description = string.Empty;
        }
        else if (columns.Count == 2)
        {
            var firstIsSku = IsLikelySku(columns[0]);
            var secondIsSku = IsLikelySku(columns[1]);

            if (firstIsSku && !secondIsSku)
            {
                sku = columns[0];
                description = columns[1];
            }
            else if (!firstIsSku && secondIsSku)
            {
                description = columns[0];
                sku = columns[1];
            }
            else
            {
                description = columns[0];
                sku = columns[1];
            }
        }
        else
        {
            var skuIdx = columns.FindLastIndex(IsLikelySku);
            if (skuIdx < 0)
            {
                error = "could not identify SKU.";
                return false;
            }

            sku = columns[skuIdx];
            columns.RemoveAt(skuIdx);
            description = string.Join(" ", columns).Trim();
        }

        if (string.IsNullOrWhiteSpace(sku))
        {
            error = "SKU is required.";
            return false;
        }

        entry = new ToughHookEntry
        {
            Bin = string.IsNullOrWhiteSpace(bin) ? "—" : bin,
            Sku = sku.Trim(),
            Description = description.Trim(),
            Qty = qty
        };
        return true;
    }

    private static List<string> SplitToughHookColumns(string line)
    {
        if (line.Contains('\t'))
        {
            return line
                .Split('\t')
                .Select(x => x.Trim())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .ToList();
        }

        if (line.Contains(','))
        {
            return line
                .Split(',')
                .Select(x => x.Trim())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .ToList();
        }

        return Regex
            .Split(line.Trim(), @"\s{2,}")
            .Select(x => x.Trim())
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .ToList();
    }

    private static bool IsLikelySku(string token)
        => _skuTokenPattern.IsMatch(token) && (token.Contains('-') || token.Contains('.'));
}
