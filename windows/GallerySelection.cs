using System;
using System.Collections.Specialized;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using QuickTransfer.Models;

namespace QuickTransfer;

public partial class MainWindow
{
    private GalleryItem? selectionAnchor;

    private void ToggleGallerySelection(object sender, RoutedEventArgs args)
    {
        Model.IsSelecting = !Model.IsSelecting;
        if (!Model.IsSelecting) ClearGallerySelection();
    }

    private void ClearGallerySelection()
    {
        galleryDragSelection.Cancel();
        GalleryList.UnselectAll();
        selectionAnchor = null;
        Model.IsSelecting = false;
    }

    private void GallerySelectionChanged(object sender, SelectionChangedEventArgs args) =>
        Model.SelectedGalleryCount = GalleryList.SelectedItems.OfType<GalleryItem>().Count();

    public void AnchorGallerySelection(Attachment file)
    {
        Model.IsSelecting = true;
        selectionAnchor = Model.Gallery.FirstOrDefault(entry => ReferenceEquals(entry.File, file));
    }

    public void SelectGalleryFile(Attachment file, ModifierKeys modifiers)
    {
        var item = Model.Gallery.FirstOrDefault(entry => ReferenceEquals(entry.File, file));
        if (item == null) return;
        Model.IsSelecting = true;
        if ((modifiers & ModifierKeys.Shift) != 0 && selectionAnchor != null && GalleryList.Items.Contains(selectionAnchor))
        {
            var start = GalleryList.Items.IndexOf(selectionAnchor);
            var end = GalleryList.Items.IndexOf(item);
            if ((modifiers & ModifierKeys.Control) == 0) GalleryList.UnselectAll();
            for (var index = Math.Min(start, end); index <= Math.Max(start, end); index++)
                if (GalleryList.Items[index] is GalleryItem entry && !GalleryList.SelectedItems.Contains(entry))
                    GalleryList.SelectedItems.Add(entry);
        }
        else
        {
            if (GalleryList.SelectedItems.Contains(item)) GalleryList.SelectedItems.Remove(item);
            else GalleryList.SelectedItems.Add(item);
            selectionAnchor = item;
        }
    }

    private void SelectAllGallery(object sender, RoutedEventArgs args)
    {
        Model.IsSelecting = true;
        GalleryList.UnselectAll();
        foreach (var item in Model.Gallery) GalleryList.SelectedItems.Add(item);
        selectionAnchor = Model.Gallery.FirstOrDefault();
    }

    private void ToggleAllGallery(object sender, RoutedEventArgs args)
    {
        if (!Model.AllGallerySelected) { SelectAllGallery(sender, args); return; }
        GalleryList.UnselectAll();
        selectionAnchor = null;
    }

    private string[] SelectedGalleryPaths() => GalleryList.SelectedItems.OfType<GalleryItem>()
        .Select(item => item.File.Path).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();

    public string[] GalleryDragPaths(Attachment file)
    {
        var selected = SelectedGalleryPaths();
        return selected.Contains(file.Path, StringComparer.OrdinalIgnoreCase) ? selected : new[] { file.Path };
    }

    private void CopyGallerySelection(object sender, RoutedEventArgs args)
    {
        Model.Run(() =>
        {
            var paths = SelectedGalleryPaths();
            if (paths.Length == 0) return;
            foreach (var path in paths)
                if (!File.Exists(path)) throw new FileNotFoundException("文件已移动或删除：" + Path.GetFileName(path));
            var files = new StringCollection();
            files.AddRange(paths);
            Clipboard.SetFileDropList(files);
            Model.Status = "";
        });
    }

    private async void StageGallerySelection(object sender, RoutedEventArgs args)
    {
        try
        {
            var paths = SelectedGalleryPaths();
            if (paths.Length == 0) return;
            await Model.AddFilesAsync(paths);
            ClearGallerySelection();
        }
        catch (Exception error) { Model.Report(error); }
    }

    private bool HandleGalleryKey(KeyEventArgs args)
    {
        if (Keyboard.FocusedElement is TextBox) return false;
        if (args.Key == Key.Escape && Model.IsSelecting) { ClearGallerySelection(); return true; }
        if (!GalleryList.IsKeyboardFocusWithin && !Model.IsSelecting) return false;
        if (Keyboard.Modifiers == ModifierKeys.Control && args.Key == Key.A) { SelectAllGallery(this, args); return true; }
        if (Keyboard.Modifiers == ModifierKeys.Control && args.Key == Key.C && Model.HasGallerySelection)
        { CopyGallerySelection(this, args); return true; }
        return false;
    }
}
