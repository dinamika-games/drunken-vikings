using Godot;

using DrunkenVikings.Looks;

/// <summary>
/// Recolour a painted picture of the game by its mask (see
/// <see cref="Recoloring"/>), for <c>Looks</c> (GDScript), which keeps what
/// it baked.
/// </summary>
public partial class Recolor : RefCounted
{
    /// <summary>
    /// A new texture of the <paramref name="picture"/> with its skin, hair and
    /// clothes in the given colours (a colour with the alpha 0 keeps its area
    /// as painted), or null if the <paramref name="mask"/> does not fit it.
    /// </summary>
    public ImageTexture? Bake(Texture2D picture, Texture2D mask, Color skin, Color hair, Color clothes)
    {
        var image = Prepared(picture.GetImage());
        var maskImage = Prepared(mask.GetImage());
        if (image.GetSize() != maskImage.GetSize())
        {
            GD.PushError(
                $"The mask {mask.ResourcePath} ({maskImage.GetSize()}) does not fit "
                + $"its picture {picture.ResourcePath} ({image.GetSize()}).");
            return null;
        }
        var colors = new float[]?[] { Rgb(skin), Rgb(hair), Rgb(clothes) };
        var data = Recoloring.Apply(image.GetData(), maskImage.GetData(), colors);
        var result = Image.CreateFromData(image.GetWidth(), image.GetHeight(), false, Image.Format.Rgba8, data);
        if (picture.GetImage().HasMipmaps())
        {
            result.GenerateMipmaps();
        }
        return ImageTexture.CreateFromImage(result);
    }

    private static Image Prepared(Image image)
    {
        var copy = (Image)image.Duplicate();
        if (copy.IsCompressed())
        {
            copy.Decompress();
        }
        copy.ClearMipmaps();
        copy.Convert(Image.Format.Rgba8);
        return copy;
    }

    private static float[]? Rgb(Color color)
    {
        return color.A <= 0f ? null : new[] { color.R, color.G, color.B };
    }
}
