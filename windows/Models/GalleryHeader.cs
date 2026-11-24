using System;

namespace QuickTransfer.Models;

public sealed record GalleryHeader(string BatchId, DateTimeOffset StartedAt, string? CustomLabel = null)
{
    public bool IsHeader => true;
    public string Label => CustomLabel ?? StartedAt.LocalDateTime.ToString("yyyy/MM/dd HH:mm:ss");
    public override string ToString() => Label;
}
