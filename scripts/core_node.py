import ctypes,json,sys,time,threading,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
library=ctypes.CDLL(str(ROOT/"core/target/aarch64-apple-darwin/release/libquicktransfer.dylib"))
library.qt_start.argtypes=[ctypes.c_char_p];library.qt_command.argtypes=[ctypes.c_char_p]
library.qt_poll.restype=ctypes.c_void_p;library.qt_free.argtypes=[ctypes.c_void_p]
config=json.loads(pathlib.Path(sys.argv[1]).read_text())
library.qt_start(json.dumps(config).encode())
def commands():
    for line in sys.stdin:
        library.qt_command(line.encode())
threading.Thread(target=commands,daemon=True).start()
try:
    while True:
        pointer=library.qt_poll()
        if pointer:
            print(ctypes.string_at(pointer).decode(),flush=True);library.qt_free(pointer)
        else:time.sleep(.01)
finally:library.qt_stop()
