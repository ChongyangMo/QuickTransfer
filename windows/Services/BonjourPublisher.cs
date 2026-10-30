using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace QuickTransfer.Services;

public sealed class BonjourPublisher
{
    private readonly SemaphoreSlim gate = new(1);
    private Registration? current;
    private int port;

    public async Task PublishAsync(int servicePort)
    {
        await gate.WaitAsync();
        try
        {
            if (current != null && port == servicePort) return;
            if (current != null)
            {
                await current.RunAsync(false);
                current.Release();
                current = null;
            }
            var registration = new Registration(servicePort);
            // 请求结构和回调委托一直保留到异步 DNS 操作结束。
            current = registration;
            await registration.RunAsync(true);
            port = servicePort;
        }
        finally { gate.Release(); }
    }

    private sealed class Registration
    {
        private readonly IntPtr instance;
        private readonly IntPtr request;
        private readonly Completed callback;
        private TaskCompletionSource<uint>? completion;

        public Registration(int port)
        {
            var host = Environment.MachineName;
            instance = DnsServiceConstructInstance(host + "._quicktransfer._tcp.local", host + ".local", IntPtr.Zero, IntPtr.Zero, (ushort)port, 0, 0, 0, IntPtr.Zero, IntPtr.Zero);
            if (instance == IntPtr.Zero) throw new InvalidOperationException("创建设备广播失败");
            callback = (status, _, result) =>
            {
                if (result != IntPtr.Zero) DnsServiceFreeInstance(result);
                completion?.TrySetResult(status);
            };
            var data = new RegisterRequest { Version = 1, Instance = instance, Callback = Marshal.GetFunctionPointerForDelegate(callback) };
            request = Marshal.AllocHGlobal(Marshal.SizeOf<RegisterRequest>());
            Marshal.StructureToPtr(data, request, false);
        }

        public async Task RunAsync(bool register)
        {
            completion = new TaskCompletionSource<uint>(TaskCreationOptions.RunContinuationsAsynchronously);
            var result = register ? DnsServiceRegister(request, IntPtr.Zero) : DnsServiceDeRegister(request, IntPtr.Zero);
            if (result != 9506) throw new Win32Exception((int)result);
            var status = await completion.Task;
            if (status != 0) throw new Win32Exception((int)status);
            GC.KeepAlive(callback);
        }

        public void Release()
        {
            Marshal.FreeHGlobal(request);
            DnsServiceFreeInstance(instance);
            GC.KeepAlive(callback);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RegisterRequest
    {
        public uint Version, InterfaceIndex;
        public IntPtr Instance, Callback, Context, Credentials;
        public int Unicast;
    }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void Completed(uint status, IntPtr context, IntPtr instance);
    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr DnsServiceConstructInstance(string name, string host, IntPtr ipv4, IntPtr ipv6, ushort port, ushort priority, ushort weight, uint propertyCount, IntPtr keys, IntPtr values);
    [DllImport("dnsapi.dll")]
    private static extern uint DnsServiceRegister(IntPtr request, IntPtr cancel);
    [DllImport("dnsapi.dll")]
    private static extern uint DnsServiceDeRegister(IntPtr request, IntPtr cancel);
    [DllImport("dnsapi.dll")]
    private static extern void DnsServiceFreeInstance(IntPtr instance);
}
