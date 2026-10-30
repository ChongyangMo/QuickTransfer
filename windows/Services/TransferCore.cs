using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace QuickTransfer.Services;

public sealed class TransferCore : IAsyncDisposable
{
    private readonly CancellationTokenSource stopping = new();
    private Task? pump;
    private bool nativeStarted;
    public event Action<IReadOnlyList<JsonElement>>? Events;
    public event Action<Exception>? Error;

    public void Start(SettingsStore settings, Dispatcher dispatcher)
    {
        if (pump != null) throw new InvalidOperationException("传输服务已经启动");
        var configuration = settings.CoreConfiguration();
        pump = Task.Run(async () =>
        {
            try
            {
                Native.qt_start(configuration);
                nativeStarted = true;
                using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(50));
                while (await timer.WaitForNextTickAsync(stopping.Token))
                {
                    var batch = new List<JsonElement>();
                    for (var i = 0; i < 128; i++)
                    {
                        var pointer = Native.qt_poll();
                        if (pointer == IntPtr.Zero) break;
                        try
                        {
                            using var document = JsonDocument.Parse(Marshal.PtrToStringUTF8(pointer)!);
                            batch.Add(document.RootElement.Clone());
                        }
                        finally { Native.qt_free(pointer); }
                    }
                    if (batch.Count > 0)
                        await dispatcher.InvokeAsync(() => Events?.Invoke(batch), DispatcherPriority.Background, stopping.Token);
                }
            }
            catch (OperationCanceledException) when (stopping.IsCancellationRequested) { }
            catch (Exception error)
            {
                if (!stopping.IsCancellationRequested)
                    await dispatcher.InvokeAsync(() => Error?.Invoke(error));
            }
        });
    }

    public void Send(object command) => Native.qt_command(JsonSerializer.Serialize(command));
    public void Restart(SettingsStore settings) => Native.qt_start(settings.CoreConfiguration());

    public async ValueTask DisposeAsync()
    {
        stopping.Cancel();
        if (pump != null)
        {
            await pump;
            if (nativeStarted) Native.qt_stop();
        }
        stopping.Dispose();
    }

    private static class Native
    {
        [DllImport("quicktransfer.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void qt_start([MarshalAs(UnmanagedType.LPUTF8Str)] string config);
        [DllImport("quicktransfer.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void qt_command([MarshalAs(UnmanagedType.LPUTF8Str)] string command);
        [DllImport("quicktransfer.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr qt_poll();
        [DllImport("quicktransfer.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void qt_free(IntPtr value);
        [DllImport("quicktransfer.dll", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void qt_stop();
    }
}
