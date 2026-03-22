using System.Windows;

namespace CTHub;

public partial class App : Application
{
    public static HubServer Hub { get; } = new();

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        await Hub.StartAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Hub.Stop();
        base.OnExit(e);
    }
}
