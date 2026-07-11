using SkylineToolTemplate.Core;

// Cross-platform CLI entry point. Put your tool's headless command surface here (it references Core only,
// so it runs on Windows/Linux/macOS). The interactive, Skyline-connected path lives in the App project.

if (args.Length > 0 && args[0] is "-h" or "--help")
{
    Console.WriteLine("SkylineToolTemplate - a Skyline external tool.");
    Console.WriteLine("Replace this with your CLI. Numbers to/from Skyline use Invariant (see Core.Invariant).");
    return 0;
}

Console.WriteLine($"SkylineToolTemplate CLI. Example invariant parse: {Invariant.Double("6.400576E+07")}");
return 0;
