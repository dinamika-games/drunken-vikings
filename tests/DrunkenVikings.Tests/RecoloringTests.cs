using DrunkenVikings.Looks;

using Xunit;

namespace DrunkenVikings.Tests;

public class RecoloringTests
{
    private static readonly byte[] Skin = { 255, 0, 0, 255 };
    private static readonly byte[] Hair = { 0, 255, 0, 255 };
    private static readonly byte[] Clothes = { 0, 0, 255, 255 };
    private static readonly byte[] Keep = { 255, 255, 255, 255 };

    private static byte[] Pixels(params byte[][] pixels)
    {
        var result = new byte[pixels.Length * 4];
        for (int i = 0; i < pixels.Length; i++)
        {
            pixels[i].CopyTo(result, i * 4);
        }
        return result;
    }

    [Fact]
    public void Test_that_the_area_takes_the_colour_on_average_and_keeps_its_shading()
    {
        var picture = Pixels(new byte[] { 40, 110, 100, 255 }, new byte[] { 20, 60, 55, 255 });
        var mask = Pixels(Clothes, Clothes);
        var result = Recoloring.Apply(picture, mask, new float[]?[] { null, null, new[] { 0.8f, 0.2f, 0.2f } });

        // The darker pixel stays darker, and both are red.
        Assert.True(result[0] > result[4]);
        Assert.True(result[0] > result[1] && result[0] > result[2]);
        Assert.True(result[4] > result[5] && result[4] > result[6]);
        Assert.Equal(255, result[3]);
    }

    [Fact]
    public void Test_that_what_to_keep_and_the_areas_without_a_colour_stay_as_painted()
    {
        var picture = Pixels(
            new byte[] { 200, 150, 50, 255 },
            new byte[] { 10, 20, 30, 128 },
            new byte[] { 90, 80, 70, 255 },
            new byte[] { 1, 2, 3, 0 });
        var mask = Pixels(Keep, Skin, Hair, new byte[] { 0, 0, 0, 0 });
        var result = Recoloring.Apply(picture, mask, new float[]?[] { null, new[] { 0.1f, 0.1f, 0.1f }, null });

        Assert.Equal(picture[0..8], result[0..8]);
        Assert.NotEqual(picture[8..11], result[8..11]);
        Assert.Equal(picture[12..16], result[12..16]);
    }

    [Fact]
    public void Test_that_a_picture_and_a_mask_of_different_sizes_are_refused()
    {
        Assert.Throws<System.ArgumentException>(
            () => Recoloring.Apply(new byte[8], new byte[4], new float[]?[] { null, null, null }));
    }
}
