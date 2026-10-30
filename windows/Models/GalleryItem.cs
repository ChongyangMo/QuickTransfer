namespace QuickTransfer.Models;

public sealed record GalleryItem(TransferRecord Record, Attachment File)
{
    public bool IsHeader => false;
    public override string ToString() => File.Name;
}
