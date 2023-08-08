pub const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("wrapper.h");
});
pub usingnamespace c;
