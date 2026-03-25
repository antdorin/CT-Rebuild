using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CTHub.Models;
using CTHub.Services;
using Microsoft.Win32;

namespace CTHub;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly HubServer _hub = App.Hub;

    // ── Bindable properties ───────────────────────────────────────────────────

    public System.Collections.ObjectModel.ObservableCollection<ChaseTacticalEntry> ChaseTacticalItems
        => _hub.ChaseTactical.Items;

    public System.Collections.ObjectModel.ObservableCollection<ToughHookEntry> ToughHookItems
        => _hub.ToughHooks.Items;

    public System.Collections.ObjectModel.ObservableCollection<QrClassMapping> QrMappingItems
        => _hub.QrMappings.Items;

    private string _statusText = $"http://localhost:{HubServer.Port}";
    public string StatusText
    {
        get => _statusText;
        set { _statusText = value; OnPropertyChanged(); }
    }

    private string _clientCountText = "0 connected";
    public string ClientCountText
    {
        get => _clientCountText;
        set { _clientCountText = value; OnPropertyChanged(); }
    }

    private string _lastBroadcast = "No broadcasts yet";
    public string LastBroadcast
    {
        get => _lastBroadcast;
        set { _lastBroadcast = value; OnPropertyChanged(); }
    }

    private string _lastConnectedDevice = "No devices yet";
    public string LastConnectedDevice
    {
        get => _lastConnectedDevice;
        set { _lastConnectedDevice = value; OnPropertyChanged(); }
    }

    private bool _isBroadcastingNow;
    public bool IsBroadcastingNow
    {
        get => _isBroadcastingNow;
        set
        {
            _isBroadcastingNow = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(BroadcastDotColor));
            OnPropertyChanged(nameof(BroadcastTextColor));
        }
    }

    private static readonly Brush _dotGreen  = Freeze(new SolidColorBrush(Color.FromRgb(0x4E, 0xC9, 0xA0)));
    private static readonly Brush _dotGray   = Freeze(new SolidColorBrush(Color.FromRgb(0x3C, 0x3C, 0x3C)));
    private static readonly Brush _textMuted = Freeze(new SolidColorBrush(Color.FromRgb(0x85, 0x85, 0x85)));
    private static Brush Freeze(Brush b) { b.Freeze(); return b; }

    public Brush BroadcastDotColor  => IsBroadcastingNow ? _dotGreen : _dotGray;
    public Brush BroadcastTextColor => IsBroadcastingNow ? _dotGreen : _textMuted;

    private string _broadcastStatusText = "Off";
    public string BroadcastStatusText
    {
        get => _broadcastStatusText;
        set { _broadcastStatusText = value; OnPropertyChanged(); }
    }

    private string _broadcastButtonText = "\u25b6  Start Broadcasting";
    public string BroadcastButtonText
    {
        get => _broadcastButtonText;
        set { _broadcastButtonText = value; OnPropertyChanged(); }
    }

    private string _lastBeaconText = "No beacons sent yet";
    public string LastBeaconText
    {
        get => _lastBeaconText;
        set { _lastBeaconText = value; OnPropertyChanged(); }
    }

    private string _localAddresses = "Scanning...";
    public string LocalAddresses
    {
        get => _localAddresses;
        set { _localAddresses = value; OnPropertyChanged(); }
    }

    private string _hubUrl = "Scanning...";
    public string HubUrl
    {
        get => _hubUrl;
        set { _hubUrl = value; OnPropertyChanged(); }
    }

    // ── Constructor ───────────────────────────────────────────────────────────

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;

        // Refresh client count and beacon timestamp every 2 s
        var timer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        timer.Tick += (_, _) =>
        {
            var n = _hub.WsManager.ConnectedCount;
            ClientCountText = n == 1 ? "1 client connected" : $"{n} clients connected";
            if (_hub.LastBeaconTime.HasValue)
                LastBeaconText = $"Last beacon sent: {_hub.LastBeaconTime.Value:HH:mm:ss}";
        };
        timer.Start();

        // Notify when a device connects
        _hub.ClientConnected += ip => Dispatcher.InvokeAsync(() =>
        {
            LastConnectedDevice = $"{ip}  \u00b7  {DateTime.Now:HH:mm:ss}";
            StatusText = $"Device connected: {ip}";
            var restore = $"http://localhost:{HubServer.Port}";
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            t.Tick += (_, _) => { StatusText = restore; t.Stop(); };
            t.Start();
        });

        // Sync broadcast state to UI
        _hub.BroadcastStateChanged += isOn => Dispatcher.InvokeAsync(() =>
        {
            IsBroadcastingNow   = isOn;
            BroadcastStatusText = isOn ? "Broadcasting" : "Off";
            BroadcastButtonText = isOn ? "\u25a0  Stop Broadcasting" : "\u25b6  Start Broadcasting";
        });

        // Load PDF folder and bind list
        PdfFileList.ItemsSource = _hub.PdfFolder.FileNames;
        if (!string.IsNullOrEmpty(_hub.PdfFolder.CurrentFolder))
            PdfFolderPathText.Text = _hub.PdfFolder.CurrentFolder;

        // Populate server info panel
        RefreshServerInfo();
    }

    // Updates the last-broadcast timestamp shown in the status bar.
    private void Touch() => LastBroadcast = $"Last write: {DateTime.Now:HH:mm:ss}";

    // ── Chase Tactical handlers ───────────────────────────────────────────────

    private void ChaseTactical_Add(object sender, RoutedEventArgs e)
    {
        var entry = new ChaseTacticalEntry { Bin = "—", Label = "New item" };
        _ = _hub.ChaseTactical.UpsertAsync(entry);
        Touch();
        ChaseTacticalGrid.ScrollIntoView(entry);
    }

    private void ChaseTactical_Delete(object sender, RoutedEventArgs e)
    {
        if (ChaseTacticalGrid.SelectedItem is ChaseTacticalEntry item)
        {
            _ = _hub.ChaseTactical.DeleteAsync(item.Id);
            Touch();
        }
    }

    private void ChaseTactical_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is ChaseTacticalEntry item)
        {
            // Let the DataGrid commit the binding first, then persist
            Dispatcher.InvokeAsync(() =>
            {
                _ = _hub.ChaseTactical.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── Tough Hooks handlers ──────────────────────────────────────────────────

    private void ToughHooks_Add(object sender, RoutedEventArgs e)
    {
        var entry = new ToughHookEntry { Bin = "—", Sku = "NEW" };
        _ = _hub.ToughHooks.UpsertAsync(entry);
        Touch();
        ToughHooksGrid.ScrollIntoView(entry);
    }

    private void ToughHooks_Delete(object sender, RoutedEventArgs e)
    {
        if (ToughHooksGrid.SelectedItem is ToughHookEntry item)
        {
            _ = _hub.ToughHooks.DeleteAsync(item.Id);
            Touch();
        }
    }

    private void ToughHooks_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is ToughHookEntry item)
        {
            Dispatcher.InvokeAsync(() =>
            {
                _ = _hub.ToughHooks.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── QR Mappings handlers ──────────────────────────────────────────────────

    private void QrMappings_Add(object sender, RoutedEventArgs e)
    {
        var entry = new QrClassMapping { QrValue = "SCAN_ME", Classification = "Unclassified" };
        _ = _hub.QrMappings.UpsertAsync(entry);
        Touch();
        QrMappingsGrid.ScrollIntoView(entry);
    }

    private void QrMappings_Delete(object sender, RoutedEventArgs e)
    {
        if (QrMappingsGrid.SelectedItem is QrClassMapping item)
        {
            _ = _hub.QrMappings.DeleteAsync(item.Id);
            Touch();
        }
    }

    private void QrMappings_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is QrClassMapping item)
        {
            Dispatcher.InvokeAsync(() =>
            {
                _ = _hub.QrMappings.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── Broadcast toggle ──────────────────────────────────────────────────────

    private void Broadcast_Toggle(object sender, RoutedEventArgs e)
    {
        if (_hub.IsBroadcasting)
            _hub.StopBroadcast();
        else
            _hub.StartBroadcast();
    }

    // ── Server info ───────────────────────────────────────────────────────────

    private void RefreshServerInfo()
    {
        var ips = System.Net.NetworkInformation.NetworkInterface
            .GetAllNetworkInterfaces()
            .Where(ni =>
                ni.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up &&
                ni.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback)
            .SelectMany(ni => ni.GetIPProperties().UnicastAddresses)
            .Where(ua => ua.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
            .Select(ua => ua.Address.ToString())
            .ToList();

        LocalAddresses = ips.Count > 0 ? string.Join(",  ", ips) : "Not found";
        HubUrl = ips.Count > 0
            ? $"ws://{ips[0]}:{HubServer.Port}/ws"
            : $"ws://localhost:{HubServer.Port}/ws";
    }

    // ── INotifyPropertyChanged ────────────────────────────────────────────────

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    // ── PDF Folder handlers ───────────────────────────────────────────────────

    private void PdfFolder_Browse(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select PDF folder",
            Multiselect = false
        };

        if (dialog.ShowDialog() == true)
        {
            var folder = dialog.FolderName;
            _hub.PdfFolder.SetFolder(folder);
            PdfFolderPathText.Text = folder;
            Touch();
        }
    }

    private void PdfDelete_Click(object sender, RoutedEventArgs e)
    {
        if (PdfFileList.SelectedItem is not string selected) return;

        var folder = _hub.PdfFolder.CurrentFolder;
        if (string.IsNullOrEmpty(folder)) return;

        var fullPath = Path.Combine(folder, selected);

        var confirm = MessageBox.Show(
            $"Permanently delete '{selected}'?",
            "Delete PDF",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes) return;

        try
        {
            File.Delete(fullPath);
            StatusText = $"Deleted: {selected}";
        }
        catch (Exception ex)
        {
            StatusText = $"Delete failed: {ex.Message}";
        }
    }

    private async void PdfScale_Click(object sender, RoutedEventArgs e)
    {
        if (PdfFileList.SelectedItem is not string selected)
        {
            StatusText = "Select a PDF in the list first.";
            return;
        }

        var folder = _hub.PdfFolder.CurrentFolder;
        if (string.IsNullOrEmpty(folder)) return;

        var inputPath = Path.Combine(folder, selected);

        // Read source page size so presets can compute exact scales
        double srcW = 612, srcH = 792; // fallback: Letter
        try
        {
            using var probe = PdfSharp.Pdf.IO.PdfReader.Open(inputPath, PdfSharp.Pdf.IO.PdfDocumentOpenMode.Import);
            if (probe.PageCount > 0)
            {
                srcW = probe.Pages[0].Width.Point;
                srcH = probe.Pages[0].Height.Point;
            }
        }
        catch { /* use fallback */ }

        var opts = ShowScaleDialog(srcW, srcH);
        if (opts is null) return;

        StatusText = $"Scaling {selected}…";
        try
        {
            var outputPath = await Task.Run(() => PdfResizeService.Scale(inputPath, opts));
            StatusText = $"Saved: {Path.GetFileName(outputPath)}";
        }
        catch (Exception ex)
        {
            StatusText = $"Scale failed: {ex.Message}";
        }
    }

    private PdfScaleOptions? ShowScaleDialog(double srcW, double srcH)
    {
        PdfScaleOptions? result = null;

        // ── Helpers ───────────────────────────────────────────────────────────
        Brush Fg(byte r, byte g, byte b) =>
            new SolidColorBrush(Color.FromRgb(r, g, b));

        TextBox MakeInput(string text) => new TextBox
        {
            Text            = text,
            FontFamily      = new System.Windows.Media.FontFamily("Consolas"),
            FontSize        = 13,
            Width           = 72,
            Background      = Fg(0x3C, 0x3C, 0x3C),
            Foreground      = Fg(0xD4, 0xD4, 0xD4),
            CaretBrush      = new SolidColorBrush(Colors.White),
            BorderBrush     = Fg(0x55, 0x55, 0x55),
            BorderThickness = new Thickness(1),
            Padding         = new Thickness(6, 3, 6, 3),
            TextAlignment   = TextAlignment.Center
        };

        TextBlock MakeLabel(string text, bool muted = false) => new TextBlock
        {
            Text              = text,
            Foreground        = muted ? Fg(0x85, 0x85, 0x85) : Fg(0xD4, 0xD4, 0xD4),
            FontFamily        = new System.Windows.Media.FontFamily("Segoe UI"),
            FontSize          = 12,
            VerticalAlignment = VerticalAlignment.Center
        };

        Button MakeBtn(string text, bool primary = false) => new Button
        {
            Content         = text,
            Padding         = new Thickness(primary ? 20 : 14, 6, primary ? 20 : 14, 6),
            Margin          = new Thickness(0, 0, 6, 0),
            Background      = primary ? Fg(0x00, 0x7A, 0xCC) : Fg(0x3C, 0x3C, 0x3C),
            Foreground      = primary ? new SolidColorBrush(Colors.White) : Fg(0xD4, 0xD4, 0xD4),
            BorderBrush     = primary ? Fg(0x00, 0x7A, 0xCC) : Fg(0x55, 0x55, 0x55),
            BorderThickness = new Thickness(1),
            FontFamily      = new System.Windows.Media.FontFamily("Segoe UI"),
            FontSize        = 12,
            Cursor          = System.Windows.Input.Cursors.Hand
        };

        Separator MakeSep() => new Separator
        {
            Background = Fg(0x3C, 0x3C, 0x3C),
            Margin     = new Thickness(0, 10, 0, 10)
        };

        // ── Dialog ────────────────────────────────────────────────────────────
        var dlg = new Window
        {
            Title                 = "Scale PDF",
            Width                 = 420,
            SizeToContent         = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode            = ResizeMode.NoResize,
            WindowStyle           = WindowStyle.ToolWindow,
            Background            = Fg(0x25, 0x25, 0x26),
            ShowInTaskbar         = false,
            Owner                 = this
        };

        var root = new StackPanel { Margin = new Thickness(20) };

        // ── Presets ───────────────────────────────────────────────────────────
        root.Children.Add(MakeLabel("Preset page size"));
        var presetPanel = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        foreach (var kv in PdfResizeService.Presets)
        {
            var pb = MakeBtn(kv.Key);
            pb.Margin = new Thickness(0, 0, 6, 6);
            presetPanel.Children.Add(pb);
        }
        root.Children.Add(presetPanel);
        root.Children.Add(MakeSep());

        // ── Lock aspect ratio ─────────────────────────────────────────────────
        var lockRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };
        var lockChk = new CheckBox { IsChecked = true, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
        lockRow.Children.Add(lockChk);
        lockRow.Children.Add(MakeLabel("Lock aspect ratio"));
        root.Children.Add(lockRow);

        // ── X / Y inputs ──────────────────────────────────────────────────────
        var xRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        var tbX  = MakeInput("100");
        xRow.Children.Add(tbX);
        xRow.Children.Add(new TextBlock { Text = "%", Foreground = Fg(0x85, 0x85, 0x85), FontSize = 12, Margin = new Thickness(4, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center });
        xRow.Children.Add(MakeLabel("Horizontal (X)"));
        root.Children.Add(xRow);

        var yRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        var tbY  = MakeInput("100");
        yRow.Children.Add(tbY);
        yRow.Children.Add(new TextBlock { Text = "%", Foreground = Fg(0x85, 0x85, 0x85), FontSize = 12, Margin = new Thickness(4, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center });
        yRow.Children.Add(MakeLabel("Vertical (Y)"));
        root.Children.Add(yRow);

        // ── DPI ───────────────────────────────────────────────────────────────
        root.Children.Add(MakeSep());
        var dpiRow = new StackPanel { Orientation = Orientation.Horizontal };
        var tbDpi  = MakeInput("150");
        dpiRow.Children.Add(tbDpi);
        dpiRow.Children.Add(new TextBlock { Text = "DPI", Foreground = Fg(0x85, 0x85, 0x85), FontSize = 12, Margin = new Thickness(8, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center });
        dpiRow.Children.Add(MakeLabel("Render quality", muted: true));
        root.Children.Add(dpiRow);
        root.Children.Add(new TextBlock { Text = "Higher DPI = sharper raster images; 72–300 recommended", Foreground = Fg(0x60, 0x60, 0x60), FontSize = 11, Margin = new Thickness(0, 3, 0, 0) });

        // ── Action buttons ────────────────────────────────────────────────────
        root.Children.Add(MakeSep());
        var btnRow    = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var okBtn     = MakeBtn("Scale", primary: true);
        var cancelBtn = MakeBtn("Cancel");
        btnRow.Children.Add(okBtn);
        btnRow.Children.Add(cancelBtn);
        root.Children.Add(btnRow);

        dlg.Content = root;

        // ── Aspect lock ───────────────────────────────────────────────────────
        bool syncing = false;
        tbX.TextChanged += (_, _) =>
        {
            if (syncing || lockChk.IsChecked != true) return;
            syncing = true; tbY.Text = tbX.Text; syncing = false;
        };
        tbY.TextChanged += (_, _) =>
        {
            if (syncing || lockChk.IsChecked != true) return;
            syncing = true; tbX.Text = tbY.Text; syncing = false;
        };

        // ── Wire preset buttons ───────────────────────────────────────────────
        foreach (Button pb in presetPanel.Children)
        {
            var presetKey = (string)pb.Content;
            pb.Click += (_, _) =>
            {
                var (sx, sy) = PdfResizeService.ScaleForPreset(presetKey, srcW, srcH);
                syncing = true;
                tbX.Text = Math.Round(sx * 100, 1).ToString();
                tbY.Text = Math.Round(sy * 100, 1).ToString();
                syncing = false;
                lockChk.IsChecked = Math.Abs(sx - sy) < 0.001;
            };
        }

        // ── Validate & confirm ────────────────────────────────────────────────
        bool Validate(out double sx, out double sy, out int dpi)
        {
            sx = sy = 0; dpi = 0;
            return double.TryParse(tbX.Text, out sx)  && sx  >= 10 && sx  <= 1000 &&
                   double.TryParse(tbY.Text, out sy)  && sy  >= 10 && sy  <= 1000 &&
                   int.TryParse(tbDpi.Text,  out dpi) && dpi >= 36 && dpi <= 600;
        }

        okBtn.Click += (_, _) =>
        {
            if (Validate(out var sx, out var sy, out var dpi))
            {
                result           = new PdfScaleOptions(sx / 100.0, sy / 100.0, dpi);
                dlg.DialogResult = true;
            }
            else
            {
                tbX.BorderBrush  = Fg(0xFF, 0x45, 0x00);
                tbY.BorderBrush  = Fg(0xFF, 0x45, 0x00);
                tbDpi.BorderBrush = Fg(0xFF, 0x45, 0x00);
            }
        };

        cancelBtn.Click += (_, _) => dlg.DialogResult = false;

        dlg.Loaded += (_, _) => { tbX.Focus(); tbX.SelectAll(); };
        dlg.ShowDialog();
        return result;
    }
}
