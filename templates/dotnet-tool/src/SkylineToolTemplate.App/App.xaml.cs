using System.Windows;

namespace SkylineToolTemplate.App;

public partial class App : Application
{
    // No StartupUri: we construct MainWindow with the process args so it can read the
    // $(SkylineConnection) pipe name Skyline passes as args[0].
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        new MainWindow(e.Args).Show();
    }
}
