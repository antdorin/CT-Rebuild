using System.Windows;
using System.Windows.Controls;
using CTHub.Models;

namespace CTHub;

public partial class BarcodeLinkDialog : Window
{
    private readonly HubServer _hub;
    private readonly string    _barcodeValue;
    private readonly string    _sourceColumnId;
    private readonly string    _sourceTableName;

    public BarcodeLinkDialog(
        Window owner,
        HubServer hub,
        string barcodeValue,
        string sourceColumnId,
        string sourceTableName)
    {
        InitializeComponent();
        Owner = owner;

        _hub             = hub;
        _barcodeValue    = barcodeValue;
        _sourceColumnId  = sourceColumnId;
        _sourceTableName = sourceTableName;

        BarcodeValueText.Text = barcodeValue;
        RefreshList();
    }

    // ── List management ───────────────────────────────────────────────────────

    private void RefreshList()
    {
        var links = _hub.BarcodeLinks.GetAll()
            .Where(l => l.SourceBarcodeValue.Equals(_barcodeValue, StringComparison.OrdinalIgnoreCase)
                     && l.SourceColumnId == _sourceColumnId)
            .OrderBy(l => l.TargetTableName)
            .ThenBy(l => l.TargetEntryLabelSnapshot)
            .ToList();

        LinksPanel.ItemsSource = links.Select(l => new LinkRow(l)).ToList();

        var hasLinks = links.Count > 0;
        LinksPanel.Visibility = hasLinks ? Visibility.Visible : Visibility.Collapsed;
        EmptyText.Visibility  = hasLinks ? Visibility.Collapsed : Visibility.Visible;
    }

    private void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn) return;
        var linkId = btn.Tag as string;
        if (string.IsNullOrEmpty(linkId)) return;

        _ = _hub.BarcodeLinks.DeleteAsync(linkId);
        RefreshList();
    }

    private void AddLink_Click(object sender, RoutedEventArgs e)
    {
        var picker = new BarcodeLinkPickerDialog(this, _hub, _barcodeValue, _sourceColumnId, _sourceTableName);
        if (picker.ShowDialog() == true)
            RefreshList();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    // ── View model ────────────────────────────────────────────────────────────

    private sealed class LinkRow
    {
        public string LinkId             { get; }
        public string TableBadge         { get; }
        public string Label              { get; }
        public string SubLabel           { get; }
        public Visibility SubLabelVisibility { get; }

        public LinkRow(BarcodeLinkEntry l)
        {
            LinkId   = l.Id;
            TableBadge = l.TargetTableName switch
            {
                "chasetactical"   => "CT",
                "toughhooks"      => "TH",
                "shippingsupplys" => "SS",
                _                 => l.TargetTableName.Length > 3
                                        ? l.TargetTableName[..3].ToUpperInvariant()
                                        : l.TargetTableName.ToUpperInvariant()
            };
            Label    = string.IsNullOrWhiteSpace(l.TargetEntryLabelSnapshot)
                ? l.TargetEntryId
                : l.TargetEntryLabelSnapshot;
            SubLabel = $"ID: {l.TargetEntryId[..Math.Min(8, l.TargetEntryId.Length)]}…  ·  Added {ParseDate(l.CreatedAtUtc)}";
            SubLabelVisibility = Visibility.Visible;
        }

        private static string ParseDate(string iso)
        {
            return DateTime.TryParse(iso, out var dt)
                ? dt.ToLocalTime().ToString("yyyy-MM-dd")
                : iso;
        }
    }
}
