using System;
using System.Windows.Media;
using QuickTransfer.Infrastructure;

namespace QuickTransfer.Models;

public sealed class Attachment(string path, long size, double aspectRatio = 1, bool isImage = false) : ObservableObject
{
    public string Path { get; } = path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Detail => FormatSize(size);
    public bool IsImage { get; } = isImage;
    public double AspectRatio { get; } = Math.Clamp(aspectRatio, .64, 1.8);
    private ImageSource? thumbnail;
    public ImageSource? Thumbnail { get => thumbnail; set { if (Set(ref thumbnail, value)) Notify(nameof(HasThumbnail)); } }
    public bool HasThumbnail => Thumbnail != null;
    internal bool ThumbnailRequested { get; set; }
    public override string ToString() => Name;

    public static string FormatSize(double bytes) => bytes switch
    {
        >= 1_073_741_824 => $"{bytes / 1_073_741_824:0.#} GB",
        >= 1_048_576 => $"{bytes / 1_048_576:0.#} MB",
        >= 1024 => $"{bytes / 1024:0.#} KB",
        _ => $"{bytes:0} B"
    };
}
