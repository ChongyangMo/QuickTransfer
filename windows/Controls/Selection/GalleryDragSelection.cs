using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using QuickTransfer.Models;

namespace QuickTransfer.Controls;

internal sealed class GalleryDragSelection
{
    private readonly ListBox list;
    private readonly Action<GalleryItem?> beginSelection;
    private readonly DispatcherTimer timer;
    private readonly HashSet<GalleryItem> previousSelection = new();
    private MasonryPanel? panel;
    private FileTile? pressedTile;
    private GalleryItem? pressedItem;
    private AdornerLayer? layer;
    private SelectionAdorner? adorner;
    private Window? window;
    private Point origin, pressPosition;
    private ModifierKeys modifiers;
    private bool pending, active, moved;

    public GalleryDragSelection(ListBox list, Action<GalleryItem?> beginSelection)
    {
        this.list = list;
        this.beginSelection = beginSelection;
        timer = new DispatcherTimer(DispatcherPriority.Input, list.Dispatcher);
        timer.Tick += OnTick;
        list.PreviewMouseLeftButtonDown += OnMouseDown;
        list.PreviewMouseMove += OnMouseMove;
        list.PreviewMouseLeftButtonUp += OnMouseUp;
        list.LostMouseCapture += OnLostCapture;
        list.Loaded += (_, _) =>
        {
            window = Window.GetWindow(list);
            if (window != null) window.Deactivated += OnDeactivated;
        };
        list.Unloaded += (_, _) =>
        {
            Cancel();
            if (window != null) window.Deactivated -= OnDeactivated;
            window = null;
        };
        list.IsVisibleChanged += (_, _) => { if (!list.IsVisible) Cancel(); };
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs args)
    {
        Cancel();
        var source = args.OriginalSource as DependencyObject;
        if (FindAncestor<ScrollBar>(source) != null || FindAncestor<CheckBox>(source) != null) return;
        panel = FindChild<MasonryPanel>(list);
        if (panel == null) return;
        var position = args.GetPosition(panel);
        if (!new Rect(panel.RenderSize).Contains(position)) return;
        pressedTile = FindAncestor<FileTile>(source);
        pressedItem = (ItemsControl.ContainerFromElement(list, source) as ListBoxItem)?.Content as GalleryItem;
        origin = new Point(position.X, position.Y + panel.VerticalOffset);
        pressPosition = args.GetPosition(list);
        modifiers = Keyboard.Modifiers;
        previousSelection.UnionWith(list.SelectedItems.OfType<GalleryItem>());
        pending = true;
        timer.Interval = TimeSpan.FromMilliseconds(450);
        timer.Start();
        // 空白处由框选接管，图片上的短按与快速拖出仍交给原控件。
        if (pressedTile == null)
        {
            list.CaptureMouse();
            args.Handled = true;
        }
    }

    private void OnMouseMove(object sender, MouseEventArgs args)
    {
        if (!pending && !active) return;
        if (args.LeftButton != MouseButtonState.Pressed) { Cancel(); return; }
        var delta = args.GetPosition(list) - pressPosition;
        moved |= Math.Abs(delta.X) >= SystemParameters.MinimumHorizontalDragDistance ||
                 Math.Abs(delta.Y) >= SystemParameters.MinimumVerticalDragDistance;
        if (pending && moved)
        {
            if (pressedTile != null) { Cancel(); return; }
            StartSelection();
        }
        if (!active) return;
        UpdateSelection();
        args.Handled = true;
    }

    private void OnTick(object? sender, EventArgs args)
    {
        if (Mouse.LeftButton != MouseButtonState.Pressed) { Cancel(); return; }
        if (pending)
        {
            // 停留在空白处不会自行清空已有选择。
            if (pressedTile == null) return;
            StartSelection();
        }
        if (!active || panel == null) return;
        if (moved)
        {
            var position = Mouse.GetPosition(panel);
            const double edge = 28;
            var distance = position.Y < edge ? position.Y - edge :
                position.Y > panel.ViewportHeight - edge ? position.Y - panel.ViewportHeight + edge : 0;
            if (distance != 0)
            {
                panel.SetVerticalOffset(panel.VerticalOffset + Math.Clamp(distance, -24, 24));
                panel.UpdateLayout();
            }
        }
        UpdateSelection();
    }

    private void StartSelection()
    {
        if (panel == null) return;
        pending = false;
        active = true;
        pressedTile?.CancelPointerGesture();
        if (!list.CaptureMouse()) { Cancel(); return; }
        beginSelection(pressedItem);
        list.UpdateLayout();
        layer = AdornerLayer.GetAdornerLayer(panel);
        adorner = new SelectionAdorner(panel) { IsHitTestVisible = false };
        layer?.Add(adorner);
        timer.Interval = TimeSpan.FromMilliseconds(30);
        UpdateSelection();
    }

    private void UpdateSelection()
    {
        if (panel == null || adorner == null) return;
        var position = Mouse.GetPosition(panel);
        var end = new Point(Math.Clamp(position.X, 0, panel.ViewportWidth),
            Math.Clamp(position.Y, 0, panel.ViewportHeight) + panel.VerticalOffset);
        var area = new Rect(origin, end);
        area.Inflate(.5, .5);
        var desired = panel.ItemsInSelection(area).Where(index => index < list.Items.Count)
            .Select(index => list.Items[index]).OfType<GalleryItem>().ToHashSet();
        if ((modifiers & ModifierKeys.Control) != 0) desired.SymmetricExceptWith(previousSelection);
        else if ((modifiers & ModifierKeys.Shift) != 0) desired.UnionWith(previousSelection);
        foreach (var item in list.SelectedItems.OfType<GalleryItem>().ToArray())
            if (!desired.Contains(item)) list.SelectedItems.Remove(item);
        foreach (var item in desired)
            if (list.Items.Contains(item) && !list.SelectedItems.Contains(item)) list.SelectedItems.Add(item);
        area.Offset(0, -panel.VerticalOffset);
        adorner.Selection = area;
        adorner.InvalidateVisual();
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs args)
    {
        if (active) { UpdateSelection(); args.Handled = true; }
        Cancel();
    }

    private void OnLostCapture(object sender, MouseEventArgs args)
    {
        if (ReferenceEquals(args.OriginalSource, list) && !list.IsMouseCaptured) Cancel();
    }

    private void OnDeactivated(object? sender, EventArgs args) => Cancel();

    public void Cancel()
    {
        pending = active = moved = false;
        timer.Stop();
        if (adorner != null) layer?.Remove(adorner);
        adorner = null;
        layer = null;
        panel = null;
        pressedTile = null;
        pressedItem = null;
        previousSelection.Clear();
        if (list.IsMouseCaptured) list.ReleaseMouseCapture();
    }

    private static T? FindAncestor<T>(DependencyObject? node) where T : DependencyObject
    {
        while (node != null)
        {
            if (node is T found) return found;
            node = node is Visual ? VisualTreeHelper.GetParent(node) : LogicalTreeHelper.GetParent(node);
        }
        return null;
    }

    private static T? FindChild<T>(DependencyObject node) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(node); index++)
        {
            var child = VisualTreeHelper.GetChild(node, index);
            if (child is T match) return match;
            if (FindChild<T>(child) is T nested) return nested;
        }
        return null;
    }
}
