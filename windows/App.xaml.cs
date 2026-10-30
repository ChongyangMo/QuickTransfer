using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using QuickTransfer.Services;
using QuickTransfer.ViewModels;

namespace QuickTransfer;

public partial class App : Application
{
    private Mutex? instance;
    private EventWaitHandle? activate;
    private RegisteredWaitHandle? activationWait;
    private TransferCore? core;
    private DesktopIntegration? desktop;
    private MainViewModel? model;
    private bool ownsInstance;
    public bool Exiting { get; private set; }

    protected override void OnStartup(StartupEventArgs args)
    {
        base.OnStartup(args);
        instance = new Mutex(true, @"Local\com.chongyang.quicktransfer.client", out ownsInstance);
        if (!ownsInstance)
        {
            if (EventWaitHandle.TryOpenExisting(@"Local\com.chongyang.quicktransfer.activate", out var existing))
            { using (existing) existing.Set(); }
            Shutdown();
            return;
        }
        try
        {
            ThemeManager.Initialize();
            var settings = new SettingsStore();
            core = new TransferCore();
            model = new MainViewModel(core, settings);
            var index = Array.IndexOf(args.Args, "--verify-config");
            if (index >= 0 && index + 1 < args.Args.Length) model.ConfigureVerification(args.Args[index + 1]);
            var window = new MainWindow(model);
            MainWindow = window;
            desktop = new DesktopIntegration(window, Quit);
            activate = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\com.chongyang.quicktransfer.activate");
            activationWait = ThreadPool.RegisterWaitForSingleObject(activate, (_, _) =>
            {
                if (!Dispatcher.HasShutdownStarted) Dispatcher.BeginInvoke(() => desktop?.Show());
            }, null, Timeout.Infinite, false);
            if (!args.Args.Contains("--background")) window.Show();
            core.Start(settings, Dispatcher);
            _ = model.LoadReceivedAsync();
        }
        catch (Exception error)
        {
            MessageBox.Show("启动失败：" + error.Message, "快传", MessageBoxButton.OK, MessageBoxImage.Error);
            Quit();
        }
    }

    public async void Quit()
    {
        if (Exiting) return;
        Exiting = true;
        try
        {
            desktop?.Dispose();
            desktop = null;
            if (core != null) await core.DisposeAsync();
            if (model != null) await model.CloseVerificationAsync();
        }
        catch (Exception error) { System.Diagnostics.Trace.WriteLine("退出快传失败：" + error.Message); }
        finally { Shutdown(); }
    }

    protected override void OnExit(ExitEventArgs args)
    {
        activationWait?.Unregister(null);
        activate?.Dispose();
        ThemeManager.Dispose();
        if (ownsInstance) instance?.ReleaseMutex();
        instance?.Dispose();
        base.OnExit(args);
    }
}
