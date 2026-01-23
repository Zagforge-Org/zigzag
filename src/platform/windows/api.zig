const std = @import("std");
const windows = std.os.windows;

pub const PAGE_READONLY: u32 = 0x02;
pub const FILE_MAP_READ: u32 = 0x0004;

// Import the CreateFileMappingW function from kernel32.dll
// This function creates or opens a named or unnamed file mapping object for a given file handle.
// Parameters:
// - hFile: Handle to the file to be mapped (use std.os.windows.INVALID_HANDLE_VALUE for pagefile-backed memory).
// - lpFileMappingAttributes: Optional security attributes (usually null).
// - flProtect: Memory protection for the mapping (e.g., PAGE_READWRITE).
// - dwMaximumSizeHigh / dwMaximumSizeLow: Maximum size of the mapping (split into high and low DWORDs).
// - lpName: Optional name of the mapping object (null for unnamed).
// Returns: Handle to the file mapping object, or INVALID_HANDLE_VALUE on failure.
pub extern "kernel32" fn CreateFileMappingW(
    hFile: windows.HANDLE,
    lpFileMappingAttributes: ?*anyopaque,
    flProtect: u32,
    dwMaximumSizeHigh: u32,
    dwMaximumSizeLow: u32,
    lpName: ?[*:0]const u16,
) callconv(.winapi) windows.HANDLE;

// Import the MapViewOfFile function from kernel32.dll
// Maps a view of a file mapping object into the address space of the calling process.
// Parameters:
// - hFileMappingObject: Handle returned by CreateFileMappingW.
// - dwDesiredAccess: Access type (e.g., FILE_MAP_READ, FILE_MAP_WRITE).
// - dwFileOffsetHigh / dwFileOffsetLow: Offset in the file mapping where mapping should start.
// - dwNumberOfBytesToMap: Number of bytes to map (0 to map the entire object).
// Returns: Pointer to the mapped memory, or null on failure.
pub extern "kernel32" fn MapViewOfFile(
    hFileMappingObject: windows.HANDLE,
    dwDesiredAccess: u32,
    dwFileOffsetHigh: u32,
    dwFileOffsetLow: u32,
    dwNumberOfBytesToMap: usize,
) callconv(.winapi) ?*anyopaque;

// Import the CloseHandle function from kernel32.dll
// Closes an open object handle (like a file mapping object or file handle).
// Parameters:
// - hObject: Handle to close.
// Returns: non-zero on success, zero on failure.
pub extern "kernel32" fn CloseHandle(
    hObject: windows.HANDLE,
) callconv(.winapi) windows.BOOL;

// Import the UnmapViewOfFile function from kernel32.dll
// Unmaps a previously mapped view of a file mapping object.
// Parameters:
// - lpBaseAddress: Pointer to the base address of the mapped view.
// Returns: non-zero on success, zero on failure.
pub extern "kernel32" fn UnmapViewOfFile(
    lpBaseAddress: *anyopaque,
) callconv(.winapi) windows.BOOL;
