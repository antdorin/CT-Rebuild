using System.ComponentModel;
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
}
