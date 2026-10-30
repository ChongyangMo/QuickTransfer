using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using QuickTransfer.Models;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel
{
    public ObservableCollection<object> GalleryTimeline { get; } = new();
    private bool isSelecting;
    private int selectedGalleryCount;
    public bool IsSelecting
    {
        get => isSelecting;
        set { if (Set(ref isSelecting, value)) Notify(nameof(SelectionLabel)); }
    }
    public string SelectionLabel => IsSelecting ? "取消多选" : "多选";
    public int SelectedGalleryCount
    {
        get => selectedGalleryCount;
        set
        {
            if (!Set(ref selectedGalleryCount, value)) return;
            Notify(nameof(HasGallerySelection));
            Notify(nameof(AllGallerySelected));
            Notify(nameof(SelectAllLabel));
        }
    }
    public bool HasGallerySelection => SelectedGalleryCount > 0;
    public bool AllGallerySelected => Gallery.Count > 0 && SelectedGalleryCount == Gallery.Count;
    public string SelectAllLabel => AllGallerySelected ? "取消全选" : "全选";
    public bool GroupGalleryByTime
    {
        get => Settings.GroupGalleryByTime;
        set
        {
            if (value == GroupGalleryByTime) return;
            try
            {
                Settings.SaveGalleryGrouping(value);
                RebuildGalleryTimeline();
            }
            catch (Exception error) { Report(error); }
            Notify();
        }
    }

    private void RebuildGalleryTimeline()
    {
        var entries = new List<object>();
        foreach (var group in Gallery.GroupBy(item => item.Record.BatchId)
                     .OrderByDescending(group => group.Max(item => item.Record.StartedAt)))
        {
            if (GroupGalleryByTime)
                entries.Add(new GalleryHeader(group.Key, group.Min(item => item.Record.StartedAt)));
            entries.AddRange(group);
        }
        var desired = entries.ToHashSet();
        for (var index = GalleryTimeline.Count - 1; index >= 0; index--)
            if (!desired.Contains(GalleryTimeline[index])) GalleryTimeline.RemoveAt(index);
        for (var index = 0; index < entries.Count; index++)
        {
            if (index < GalleryTimeline.Count && Equals(GalleryTimeline[index], entries[index])) continue;
            var previous = GalleryTimeline.IndexOf(entries[index]);
            if (previous >= 0) GalleryTimeline.Move(previous, index);
            else GalleryTimeline.Insert(index, entries[index]);
        }
        Notify(nameof(AllGallerySelected));
        Notify(nameof(SelectAllLabel));
    }
}
