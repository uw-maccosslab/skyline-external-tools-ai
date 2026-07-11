namespace SkylineToolTemplate.Skyline;

/// <summary>
/// The subset of Skyline's JSON-RPC surface your tool actually uses. Keeping this as an interface (rather
/// than handing out the concrete <c>SkylineJsonToolClient</c>) lets a FakeClient drive your whole tool in
/// unit tests with no live Skyline. Add methods here as you need them and forward the new call in
/// <see cref="SkylineSession"/>'s adapter.
/// </summary>
public interface ISkylineClient
{
    string GetDocumentPath();

    string GetVersion();

    /// <summary>Runs a SkylineCmd command line against the live document (one flag per call is safest).</summary>
    string RunCommand(string[] args);
}

/// <summary>
/// Runs an action against a freshly-connected Skyline client. Skyline closes the pipe after each call, so
/// every operation opens its own connection - the executor owns that lifetime. A FakeExecutor implements
/// this over a FakeClient for tests.
/// </summary>
public interface ISkylineExecutor
{
    T Execute<T>(Func<ISkylineClient, T> action);

    void Execute(Action<ISkylineClient> action);
}
