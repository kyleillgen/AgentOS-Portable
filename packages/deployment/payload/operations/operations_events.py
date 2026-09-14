"""Filesystem wakeups and parent lifetime; no model or HTTP dependency."""
import ctypes, os, threading

def parent_alive(pid):
    if not pid: return True
    if os.name != "nt":
        try: os.kill(pid,0); return True
        except ProcessLookupError: return False
    kernel=ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype=ctypes.c_void_p
    kernel.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32]
    kernel.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
    kernel.CloseHandle.argtypes=[ctypes.c_void_p]
    handle=kernel.OpenProcess(0x100000,False,pid)
    if not handle: return False
    try: return kernel.WaitForSingleObject(handle,0) == 258
    finally: kernel.CloseHandle(handle)

class DirectoryWake:
    """Windows filesystem notifications wake the checker; timed scan is fallback."""
    def __init__(self, paths):
        self.dirty=threading.Event();self.dirty.set();self.handles=[]
        if os.name == 'nt':
            for path in paths:
                threading.Thread(target=self.watch,args=(str(path),),daemon=True).start()
    def watch(self,path):
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
        kernel.CreateFileW.restype=ctypes.c_void_p
        kernel.ReadDirectoryChangesW.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32,ctypes.POINTER(ctypes.c_uint32),ctypes.c_void_p,ctypes.c_void_p]
        handle=kernel.CreateFileW(path,1,7,None,3,0x02000000,None)
        if handle in (None,ctypes.c_void_p(-1).value):return
        self.handles.append(handle);buffer=ctypes.create_string_buffer(65536);count=ctypes.c_uint32()
        while kernel.ReadDirectoryChangesW(handle,buffer,len(buffer),True,0x1|0x2|0x8|0x10,ctypes.byref(count),None,None):
            data=buffer.raw[:count.value];offset=0
            if not data:self.dirty.set();continue
            while offset+12 <= len(data):
                step=int.from_bytes(data[offset:offset+4],'little');size=int.from_bytes(data[offset+8:offset+12],'little')
                name=data[offset+12:offset+12+size].decode('utf-16le','replace').replace('\\','/')
                if name.endswith(('.json','.md','.txt')) and not any(t in name for t in ('notifications.json','notifier.json','desktop-seen.json','checker-error','checker-health','watchdog.json','monitor-heartbeat','desk.lock','-stdout','-stderr','-prompt')):self.dirty.set()
                if not step:break
                offset+=step
