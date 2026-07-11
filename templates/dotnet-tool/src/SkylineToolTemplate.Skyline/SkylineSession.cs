using System.IO.Pipes;
using SkylineTool;

namespace SkylineToolTemplate.Skyline;

/// <summary>
/// Connects to a running Skyline over JSON-RPC. Encodes the three connection rules that otherwise cost
/// hours (all produce `0x00 is invalid start of value` when wrong):
///   1. transform args[0] (the legacy tool-service pipe name) to the JSON pipe name;
///   2. connect PER CALL (Skyline closes the pipe after each request);
///   3. set ReadMode = Message before reading.
/// </summary>
public sealed class SkylineSession : ISkylineExecutor
{
    private readonly string _pipeName;
    private readonly int _timeoutMs;

    public SkylineSession(string jsonPipeName, int timeoutMs = 5000)
    {
        _pipeName = jsonPipeName;
        _timeoutMs = timeoutMs;
    }

    /// <summary>
    /// Builds a session from the tool's process args. Skyline passes the legacy ToolService pipe name as
    /// args[0] (from `Arguments=$(SkylineConnection)` in the manifest); we derive the JSON pipe name.
    /// </summary>
    public static SkylineSession FromArguments(string[] args, int timeoutMs = 5000)
    {
        if (args == null || args.Length == 0 || string.IsNullOrEmpty(args[0]))
        {
            throw new ArgumentException(
                "No $(SkylineConnection) argument. Skyline passes the tool-service pipe name as args[0].");
        }

        var raw = args[0];
        var jsonName = raw.StartsWith(JsonToolConstants.JSON_PIPE_PREFIX)
            ? raw
            : JsonToolConstants.GetJsonPipeName(raw);
        return new SkylineSession(jsonName, timeoutMs);
    }

    public T Execute<T>(Func<ISkylineClient, T> action)
    {
        using var pipe = new NamedPipeClientStream(".", _pipeName, PipeDirection.InOut);
        pipe.Connect(_timeoutMs);
        pipe.ReadMode = PipeTransmissionMode.Message; // MANDATORY - else the response read never completes.
        using var client = new SkylineJsonToolClient(pipe);
        return action(new JsonClientAdapter(client));
    }

    public void Execute(Action<ISkylineClient> action) =>
        Execute<object>(client =>
        {
            action(client);
            return null;
        });

    /// <summary>Forwards the <see cref="ISkylineClient"/> subset to the vendored client.</summary>
    private sealed class JsonClientAdapter : ISkylineClient
    {
        private readonly SkylineJsonToolClient _client;

        public JsonClientAdapter(SkylineJsonToolClient client) => _client = client;

        public string GetDocumentPath() => _client.GetDocumentPath();

        public string GetVersion() => _client.GetVersion();

        public string RunCommand(string[] args) => _client.RunCommand(args);
    }
}
