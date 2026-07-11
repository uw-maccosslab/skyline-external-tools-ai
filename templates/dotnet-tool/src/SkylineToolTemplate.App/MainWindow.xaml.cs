using System;
using System.Windows;
using SkylineToolTemplate.Skyline;

namespace SkylineToolTemplate.App;

public partial class MainWindow : Window
{
    private readonly string[] _args;

    public MainWindow(string[] args)
    {
        _args = args;
        InitializeComponent();
        StatusText.Text = args.Length > 0 && !string.IsNullOrEmpty(args[0])
            ? "Received a $(SkylineConnection) argument. Click Run to talk to Skyline."
            : "No $(SkylineConnection) argument (launched standalone). Run will report that.";
    }

    private void OnRun(object sender, RoutedEventArgs e)
    {
        // Do RPC off the UI thread in a real tool; kept inline here for a minimal, readable template.
        try
        {
            var session = SkylineSession.FromArguments(_args);
            var version = session.Execute(c => c.GetVersion());
            var path = session.Execute(c => c.GetDocumentPath());
            Log($"Connected. Skyline {version}");
            Log($"Document: {path}");
        }
        catch (Exception ex)
        {
            Log("ERROR: " + ex.Message);
        }
    }

    private void Log(string message)
    {
        LogBox.AppendText(message + Environment.NewLine);
        LogBox.ScrollToEnd();
        MainTabs.SelectedItem = LogTab;
    }
}
