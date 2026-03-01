const std = @import("std");
const windows = std.os.windows;

pub extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const u16,
    dwDesiredAccess: u32,
    dwShareMode: u32,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: u32,
    dwFlagsAndAttributes: u32,
    hTemplateFile: ?windows.HANDLE,
) callconv(.winapi) windows.HANDLE;

pub extern "kernel32" fn ReadDirectoryChangesW(
    hDirectory: windows.HANDLE,
    lpBuffer: *anyopaque,
    nBufferLength: u32,
    bWatchSubtree: windows.BOOL,
    dwNotifyFilter: u32,
    lpBytesReturned: ?*u32,
    lpOverlapped: ?*anyopaque,
    lpCompletionRoutine: ?*anyopaque,
) callconv(.winapi) windows.BOOL;

pub const FILE_LIST_DIRECTORY: u32 = 0x00000001;
pub const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x02000000;

pub const FILE_NOTIFY_CHANGE_FILE_NAME: u32 = 0x00000001;
pub const FILE_NOTIFY_CHANGE_DIR_NAME: u32 = 0x00000002;
pub const FILE_NOTIFY_CHANGE_LAST_WRITE: u32 = 0x00000010;

pub const FILE_ACTION_ADDED: u32 = 0x00000001;
pub const FILE_ACTION_REMOVED: u32 = 0x00000002;
pub const FILE_ACTION_MODIFIED: u32 = 0x00000003;
pub const FILE_ACTION_RENAMED_OLD_NAME: u32 = 0x00000004;
pub const FILE_ACTION_RENAMED_NEW_NAME: u32 = 0x00000005;

pub const FileNotifyInformation = extern struct {
    NextEntryOffset: u32,
    Action: u32,
    FileNameLength: u32,
    // WCHAR FileName[] follows immediately after this struct
};
