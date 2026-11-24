using System;
using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using QuickTransfer.Models;
using QuickTransfer.Services;
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

    private void PreserveSelection(object sender, MouseButtonEventArgs args) => args.Handled = true;

    private void OnContextMenuOpened(object sender, RoutedEventArgs args)
    {
        var showGalleryActions = !CanRemove && DataContext is Attachment;
        var visibility = showGalleryActions ? Visibility.Visible : Visibility.Collapsed;
        PinMenuItem.Visibility = visibility;
        ResendMenuItem.Visibility = visibility;
        TopSeparator.Visibility = visibility;
        BottomSeparator.Visibility = visibility;
        RemoveMenuItem.Visibility = visibility;
        DeleteMenuItem.Visibility = visibility;
        if (DataContext is Attachment file)
            PinMenuItem.Header = file.IsPinned ? "取消置顶" : "置顶";
    }

    private void TogglePin(object sender, RoutedEventArgs args)
    {
        if (DataContext is not Attachment file || Window.GetWindow(this) is not MainWindow window) return;
        var targets = window.GalleryActionTargets(file);
        window.Model.TogglePin(targets);
    }

    private async void ResendFile(object sender, RoutedEventArgs args)
    {
        if (DataContext is not Attachment file || Window.GetWindow(this) is not MainWindow window) return;
        var targets = window.GalleryActionTargets(file);
        await window.Model.ResendFilesAsync(targets);
    }

    private async void RemoveFromGallery(object sender, RoutedEventArgs args)
    {
        if (DataContext is not Attachment file || Window.GetWindow(this) is not MainWindow window) return;
        var targets = window.GalleryActionTargets(file);
        await window.Model.RemoveGalleryItemsAsync(targets);
    }

    private async void DeleteFile(object sender, RoutedEventArgs args)
    {
        if (DataContext is not Attachment file || Window.GetWindow(this) is not MainWindow window) return;
        var targets = window.GalleryActionTargets(file);
        await window.DeleteGalleryFilesWithConfirmAsync(targets);
    }

    private void OpenInExplorer(object sender, RoutedEventArgs args) =>
        RunFileAction(file => ShellFileActions.OpenInExplorer(file.Path));

    private void ShowFileProperties(object sender, RoutedEventArgs args) =>
        RunFileAction(file => ShellFileActions.ShowProperties(Window.GetWindow(this), file.Path));

    private void RunFileAction(Action<Attachment> action)
    {
        if (DataContext is not Attachment file || Window.GetWindow(this) is not MainWindow window) return;
        window.Model.Run(() =>
        {
            action(file);
            window.Model.Status = "";
        });
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
