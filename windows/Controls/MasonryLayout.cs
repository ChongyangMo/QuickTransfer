using System;
using System.Collections;
using System.Windows;
using QuickTransfer.Models;

namespace QuickTransfer.Controls;

internal static class MasonryLayout
{
    public static (Rect[] Bounds, double Height) Calculate(IList items, double width, double targetWidth, double gap, bool compact)
    {
        var columns = Math.Clamp((int)Math.Round((width + gap) / (targetWidth + gap)), 1, 10);
        var itemWidth = Math.Max(1, (width - gap * (columns - 1)) / columns);
        var heights = new double[columns];
        var bounds = new Rect[items.Count];
        double total = 0;
        for (var index = 0; index < items.Count; index++)
        {
            if (items[index] is GalleryHeader)
            {
                double top = 0;
                foreach (var bottom in heights) top = Math.Max(top, bottom);
                bounds[index] = new Rect(0, top, width, 32);
                Array.Fill(heights, top + 32 + gap);
                total = top + 32;
                continue;
            }
            var file = items[index] switch { Attachment attachment => attachment, GalleryItem item => item.File, _ => null };
            var height = compact ? 112 : file is { IsImage: true } ? itemWidth / file.AspectRatio : 108;
            var column = 0;
            for (var candidate = 1; candidate < columns; candidate++)
                if (heights[candidate] < heights[column]) column = candidate;
            bounds[index] = new Rect(column * (itemWidth + gap), heights[column], itemWidth, height);
            heights[column] += height + gap;
            total = Math.Max(total, heights[column] - gap);
        }
        return (bounds, total);
    }
}
