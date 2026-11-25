using System;

namespace DrunkenVikings.Looks;

/// <summary>
/// Recolour a painted picture by its mask: the skin, the hair and the clothes
/// each take a colour of their own and keep their shading; what the mask
/// marks to keep (the trims, the belts, the bands, the wood) keeps its paint.
/// </summary>
/// <remarks>
/// <para>
/// The pictures and the masks are RGBA, 8 bits a channel, row by row. The
/// mask paints the skin red (#FF0000), the hair green (#00FF00) and the
/// clothes blue (#0000FF); white, black or a transparent pixel keep the
/// paint (see dev/pictures/cut_looks.py).
/// </para>
/// <para>
/// The colour of an area is its average, as painted, outlines and shadows
/// included: every pixel of the area keeps how much lighter or darker it is
/// than the average of its area (its luminance over the average luminance),
/// so the picture keeps its shading, and the area its colour on average
/// whatever it was painted in (e.g., the teal of Ylva or the plum of Sigrid).
/// The pixels lighter than the average blend a little towards white, so that
/// the highlights stay highlights also on a dark colour.
/// </para>
/// </remarks>
public static class Recoloring
{
    /// <summary>The areas of a mask.</summary>
    public enum Area
    {
        Keep = -1,
        Skin = 0,
        Hair = 1,
        Clothes = 2,
    }

    /// <summary>How far the highlights blend towards white, at most.</summary>
    public const float Highlight = 0.35f;

    /// <summary>The area of the mask pixel at the byte <paramref name="i"/>.</summary>
    public static Area AreaOf(byte[] mask, int i)
    {
        if (mask[i + 3] < 128)
        {
            return Area.Keep;
        }
        bool r = mask[i] >= 128;
        bool g = mask[i + 1] >= 128;
        bool b = mask[i + 2] >= 128;
        if (r && !g && !b)
        {
            return Area.Skin;
        }
        if (g && !r && !b)
        {
            return Area.Hair;
        }
        if (b && !r && !g)
        {
            return Area.Clothes;
        }
        return Area.Keep;
    }

    /// <summary>The luminance of the RGB at the byte <paramref name="i"/>, in [0, 1].</summary>
    public static float Luminance(byte[] rgba, int i)
    {
        return (0.299f * rgba[i] + 0.587f * rgba[i + 1] + 0.114f * rgba[i + 2]) / 255f;
    }

    /// <summary>
    /// Recolour the <paramref name="picture"/> by its <paramref name="mask"/>
    /// (of the same size) into a new array.
    /// </summary>
    /// <param name="picture">The painted picture, RGBA.</param>
    /// <param name="mask">Its mask, RGBA.</param>
    /// <param name="colors">
    /// The colour of the skin, the hair and the clothes (RGB in [0, 1]), each
    /// null to keep the area as painted.
    /// </param>
    public static byte[] Apply(byte[] picture, byte[] mask, float[]?[] colors)
    {
        if (picture.Length != mask.Length || picture.Length % 4 != 0)
        {
            throw new ArgumentException(
                $"The picture ({picture.Length} bytes) and its mask ({mask.Length} bytes) differ.");
        }
        if (colors.Length != 3)
        {
            throw new ArgumentException($"Expected the colours of 3 areas, got {colors.Length}.");
        }

        // NOTE (mristin):
        // The average luminance of each area, weighted by the alpha of the
        // picture, so that its soft edges count less.
        var sums = new double[3];
        var weights = new double[3];
        for (int i = 0; i < picture.Length; i += 4)
        {
            var area = AreaOf(mask, i);
            if (area == Area.Keep || colors[(int)area] == null)
            {
                continue;
            }
            double weight = picture[i + 3] / 255.0;
            sums[(int)area] += Luminance(picture, i) * weight;
            weights[(int)area] += weight;
        }
        var averages = new float[3];
        for (int k = 0; k < 3; k++)
        {
            averages[k] = weights[k] > 0.0 ? (float)Math.Max(sums[k] / weights[k], 1e-3) : 1f;
        }

        var result = (byte[])picture.Clone();
        for (int i = 0; i < picture.Length; i += 4)
        {
            var area = AreaOf(mask, i);
            if (area == Area.Keep)
            {
                continue;
            }
            var color = colors[(int)area];
            if (color == null)
            {
                continue;
            }
            float average = averages[(int)area];
            float luminance = Luminance(picture, i);
            for (int c = 0; c < 3; c++)
            {
                float value;
                if (luminance <= average)
                {
                    value = color[c] * luminance / average;
                }
                else
                {
                    float light = (luminance - average) / Math.Max(1f - average, 1e-3f);
                    value = color[c] + (1f - color[c]) * light * Highlight;
                }
                result[i + c] = (byte)Math.Clamp((int)Math.Round(value * 255f), 0, 255);
            }
        }
        return result;
    }
}
