using System.Globalization;

namespace SkylineToolTemplate.Core;

/// <summary>
/// Parse/format helpers that ALWAYS use <see cref="CultureInfo.InvariantCulture"/>. Skyline exports
/// invariant (`.` decimal separator, `6.400576E+07`), so every number your tool reads from or writes to
/// Skyline must go through invariant parsing/formatting. Replace this stub with your tool's real logic;
/// it exists to demonstrate the rule and give the template a cross-platform unit-testable surface.
/// </summary>
public static class Invariant
{
    public static double Double(string s) =>
        double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);

    public static int Int(string s) =>
        int.Parse(s, NumberStyles.Integer, CultureInfo.InvariantCulture);

    public static string Text(double value) =>
        value.ToString(CultureInfo.InvariantCulture);
}
