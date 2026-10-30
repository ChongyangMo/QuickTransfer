using System;

namespace QuickTransfer.Models;

public sealed record GalleryHeader(string BatchId, DateTimeOffset StartedAt)
{
    public bool IsHeader => true;
    public string Label => StartedAt.LocalDateTime.ToString("yyyy/MM/dd HH:mm:ss");
    public override string ToString() => Label;
}
