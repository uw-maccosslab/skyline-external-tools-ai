using SkylineToolTemplate.Core;
using Xunit;

namespace SkylineToolTemplate.Tests;

public sealed class InvariantTests
{
    [Fact]
    public void Parses_skyline_invariant_scientific_notation()
    {
        Assert.Equal(6.400576e7, Invariant.Double("6.400576E+07"), 3);
        Assert.Equal(314, Invariant.Int("314"));
    }
}
