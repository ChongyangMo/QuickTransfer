using System;
using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using QuickTransfer.Models;
using QuickTransfer.Views;

namespace QuickTransfer.Controls;

public partial class FileTile : UserControl
{
    private Point dragOrigin;
    private bool dragging;
    private bool dragArmed;
    public static readonly DependencyProperty CanRemoveProperty = DependencyProperty.Register(nameof(CanRemove), typeof(bool), typeof(FileTile));
    public static readonly DependencyProperty RemoveCommandProperty = DependencyProperty.Register(nameof(RemoveCommand), typeof(ICommand), typeof(FileTile));
    public static readonly DependencyProperty SelectionEnabledProperty = DependencyProperty.Register(nameof(SelectionEnabled), typeof(bool), typeof(FileTile));
    public bool CanRemove { get => (bool)GetValue(CanRemoveProperty); set => SetValue(CanRemoveProperty, value); }
    public ICommand? RemoveCommand { get => (ICommand?)GetValue(RemoveCommandProperty); set => SetValue(RemoveCommandProperty, value); }
    public bool SelectionEnabled { get => (bool)GetValue(SelectionEnabledProperty); set => SetValue(SelectionEnabledProperty, value); }
    public FileTile()
    {
        InitializeComponent();
        Loaded += (_, _) => LoadThumbnail();
        DataContextChanged += (_, _) => { if (IsLoaded) LoadThumbnail(); };
        PreviewMouseLeftButtonUp += (_, _) => dragArmed = false;
        Unloaded += (_, _) => dragArmed = false;
    }

    private void LoadThumbnail()
    {
        if (DataContext is Attachment file && Application.Current.MainWindow is MainWindow window)
            _ = window.Model.FileService.LoadThumbnailAsync(file);
    }

    private void UpdateClip(object sender, SizeChangedEventArgs args) =>
        ((UIElement)sender).Clip = new RectangleGeometry(new Rect(args.NewSize), 10, 10);

    private void ToggleSelection(object sender, RoutedEventArgs args)
    {
        args.Handled = true;
        if (DataContext is Attachment file && Window.GetWindow(this) is MainWindow window)
            window.AnchorGallerySelection(file);
    }

    private void BeginDrag(object sender, MouseButtonEventArgs args)
    {
        dragOrigin = args.GetPosition(this);
        dragging = false;
        dragArmed = true;
    }

    internal void CancelPointerGesture()
    {
        dragArmed = false;
        dragging = true;
    }

    private void MoveDrag(object sender, MouseEventArgs args)
    {
        if (!dragArmed || args.LeftButton != MouseButtonState.Pressed || dragging || DataContext is not Attachment file) return;
        var point = args.GetPosition(this);
        if (Math.Abs(point.X - dragOrigin.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(point.Y - dragOrigin.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        dragging = true;
        dragArmed = false;
        args.Handled = true;
        try
        {
            var paths = !CanRemove && Window.GetWindow(this) is MainWindow window ? window.GalleryDragPaths(file) : new[] { file.Path };
            foreach (var path in paths)
                if (!File.Exists(path)) throw new FileNotFoundException("文件已移动或删除：" + Path.GetFileName(path));
            var data = new DataObject();
            var files = new StringCollection();
            files.AddRange(paths);
            data.SetFileDropList(files);
            DragDrop.DoDragDrop(this, data, DragDropEffects.Copy);
        }
        catch (Exception error) { ((MainWindow)Application.Current.MainWindow).Model.Report(error); }
    }

    private async void OpenFile(object sender, RoutedEventArgs args)
    {
        if (dragging || DataContext is not Attachment file) return;
        if (!CanRemove && (SelectionEnabled || (Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Shift)) != 0))
        {
            if (Window.GetWindow(this) is MainWindow window) window.SelectGalleryFile(file, Keyboard.Modifiers);
            return;
        }
        await FilePreviewWindow.OpenAsync(Window.GetWindow(this), file.Path);
    }
}
