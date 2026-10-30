using QuickTransfer.Infrastructure;

namespace QuickTransfer.Models;

public sealed class Peer(string id) : ObservableObject
{
    public string Id { get; } = id;
    private string alias = "";
    private bool mobile;
    public string Alias { get => alias; set => Set(ref alias, value); }
    public bool Mobile { get => mobile; set { if (Set(ref mobile, value)) Notify(nameof(Glyph)); } }
    public string Glyph => Mobile ? "\uE8EA" : "\uE7F8";
    public override string ToString() => Alias;
}
