pub const CompressionStreamEncoder = StreamEncoderDecoder(jsc.Codegen.JSCompressionStreamEncoder, CompressorContext);
pub const DecompressionStreamDecoder = StreamEncoderDecoder(jsc.Codegen.JSDecompressionStreamDecoder, DecompressorContext);

// TODO: Remove this once done with debugging...probably?
const log = bun.Output.scoped(.compression, false);

fn StreamEncoderDecoder(js: type, Context: type) type {
    return struct {
        const Self = @This();

        pub const toJS = js.toJS;
        pub const fromJS = js.fromJS;
        pub const fromJSDirect = js.fromJSDirect;

        pub const new = bun.TrivialNew(@This());

        context: Context,

        pub fn finalize(this: *Self) void {
            switch (this.context) {
                inline else => |*ctx| ctx.deinit(),
            }

            bun.destroy(this);
        }

        pub fn constructor(_: *JSGlobalObject, callFrame: *CallFrame) bun.JSError!*Self {
            const format: Format = @enumFromInt(callFrame.argument(0).asInt32());
            const this = new(.{
                .context = switch (format) {
                    inline else => |f| @unionInit(Context, @tagName(f), .{}),
                },
            });

            switch (this.context) {
                inline else => |*ctx| try ctx.init(format),
            }

            return this;
        }

        pub fn process(this: *Self, globalObject: *JSGlobalObject, callFrame: *CallFrame) bun.JSError!JSValue {
            const array_buffer = callFrame.argument(0).asArrayBuffer(globalObject) orelse @panic("unreachable");
            const chunk = array_buffer.slice();

            if (chunk.len == 0) return .null;

            const output = switch (this.context) {
                inline else => |*ctx| try ctx.process(globalObject, chunk),
            };

            return if (output.len != 0) JSUint8Array.fromBytes(globalObject, output) else .null;
        }

        pub fn flush(this: *Self, globalObject: *JSGlobalObject, _: *CallFrame) bun.JSError!JSValue {
            const output = switch (this.context) {
                inline else => |*ctx| try ctx.flush(globalObject),
            };

            return if (output.len != 0) JSUint8Array.fromBytes(globalObject, output) else .null;
        }
    };
}

// The order of this enum should match the order of `algorithms` in CompressionStream.ts.
const Format = enum(u3) { Brotli, Deflate, DeflateRaw, Gzip, Zstd };

const CompressorContext = union(Format) {
    Brotli: BrotliCompressorContext,
    Deflate: ZlibCompressorContext,
    DeflateRaw: ZlibCompressorContext,
    Gzip: ZlibCompressorContext,
    Zstd: ZstdCompressorContext,
};

const DecompressorContext = union(Format) {
    Brotli: BrotliDecompressorContext,
    Deflate: ZlibDecompressorContext,
    DeflateRaw: ZlibDecompressorContext,
    Gzip: ZlibDecompressorContext,
    Zstd: ZstdDecompressorContext,
};

const ZlibCompressorContext = ZlibContext(true);
const ZlibDecompressorContext = ZlibContext(false);

fn ZlibContext(is_compressing: bool) type {
    return struct {
        const Self = @This();
        const c = bun.zlib;

        state: c.z_stream = std.mem.zeroes(c.z_stream),

        pub fn init(this: *Self, format: Format) bun.JSError!void {
            const Z_DEFAULT_COMPRESSION = -1;
            const Z_DEFLATED = 8;
            const Z_DEFAULT_WINDOWBITS = 15;
            const Z_DEFAULT_MEMLEVEL = 8;
            const Z_DEFAULT_STRATEGY = 0;

            // See windowBitsActual in NativeZlib.zig
            const actual_window_bits: i32 = switch (format) {
                .Deflate => Z_DEFAULT_WINDOWBITS,
                .Gzip => Z_DEFAULT_WINDOWBITS + 16,
                .DeflateRaw => -Z_DEFAULT_WINDOWBITS,
                else => unreachable,
            };

            const err = if (is_compressing) c.deflateInit2_(
                &this.state,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                actual_window_bits,
                Z_DEFAULT_MEMLEVEL,
                Z_DEFAULT_STRATEGY,
                c.zlibVersion(),
                @sizeOf(c.z_stream),
            ) else c.inflateInit2_(
                &this.state,
                actual_window_bits,
                c.zlibVersion(),
                @sizeOf(c.z_stream),
            );

            switch (err) {
                .Ok => {},
                .MemError => return error.OutOfMemory,
                else => unreachable,
            }
        }

        pub fn deinit(this: *Self) void {
            if (is_compressing) {
                _ = c.deflateEnd(&this.state);
            } else {
                _ = c.inflateEnd(&this.state);
            }
        }

        fn process(this: *Self, globalObject: *JSGlobalObject, chunk: []const u8) bun.JSError![]u8 {
            // TODO: Anything better than using ArrayList? Multiple N-byte-sized allocations maybe?
            var output: std.ArrayListUnmanaged(u8) = .{};
            errdefer output.deinit(bun.default_allocator);

            var offset: usize = 0;

            this.state.avail_in = @intCast(chunk.len);
            this.state.next_in = chunk.ptr;

            while (this.state.avail_in != 0) {
                // TODO: Is there a better way to do this?
                try output.resize(bun.default_allocator, output.capacity + 1024);
                output.expandToCapacity();

                this.state.avail_out = @intCast(output.items[offset..].len);
                this.state.next_out = output.items[offset..].ptr;

                const err = if (is_compressing)
                    c.deflate(&this.state, .NoFlush)
                else
                    c.inflate(&this.state, .NoFlush);

                switch (err) {
                    .Ok => {},
                    .StreamEnd => if (is_compressing) unreachable else bun.assert_eql(this.state.avail_in, 0),
                    .MemError => return error.OutOfMemory,
                    .NeedDict, .DataError => if (is_compressing)
                        unreachable
                    else
                        return this.throwError(globalObject, err),
                    .StreamError => @panic("unexpected StreamError"),
                    .BufError => @panic("unexpected BufError"), // TODO: This should be unreachable, right?
                    .ErrNo => unreachable,
                    .VersionError => unreachable,
                }

                // avail_out holds the remaining amount of space,
                // so next time, start right before that point.
                // (Or return up until this point if we've consumed all input.)
                offset = output.items.len - this.state.avail_out;
                log("did deflate/inflate, new offset {}", .{offset});
            }

            output.items.len = offset;
            log("zlib done with deflate/inflate, length {} out of allocated {}", .{ offset, output.capacity });
            return output.toOwnedSlice(bun.default_allocator);
        }

        pub fn flush(
            this: *Self,
            globalObject: *JSGlobalObject,
        ) bun.JSError![]u8 {
            var output: std.ArrayListUnmanaged(u8) = .{};
            errdefer output.deinit(bun.default_allocator);

            var offset: usize = 0;

            this.state.avail_in = 0;
            this.state.next_in = null;

            var err: c.ReturnCode = .Ok;
            while (err == .Ok) {
                // TODO: Is there a better way to do this?
                try output.resize(bun.default_allocator, output.capacity + 1024);
                output.expandToCapacity();

                this.state.avail_out = @intCast(output.items[offset..].len);
                this.state.next_out = output.items[offset..].ptr;

                err = if (is_compressing)
                    c.deflate(&this.state, .Finish)
                else
                    c.inflate(&this.state, .Finish);

                offset = output.items.len - this.state.avail_out;
                log("zlib did (partial) flush, new offset {}", .{offset});
            }

            output.items.len = offset;
            log("zlib done with flush, length {} out of allocated {}", .{ offset, output.capacity });
            switch (err) {
                .Ok => unreachable,
                .StreamEnd => return output.toOwnedSlice(bun.default_allocator),
                .MemError => return error.OutOfMemory,
                .NeedDict, .DataError => if (is_compressing)
                    unreachable
                else
                    return this.throwError(globalObject, err),
                .StreamError => @panic("unexpected StreamError"),
                .BufError => if (is_compressing)
                    @panic("unexpected BufError")
                else
                    // We reached EOF prematurely
                    return this.throwError(globalObject, err),
                .ErrNo => unreachable,
                .VersionError => unreachable,
            }
        }

        fn throwError(this: *Self, globalObject: *JSGlobalObject, err: c.ReturnCode) bun.JSError {
            // TODO: Node-compatible error messages?
            const message = if (this.state.err_msg) |msg| std.mem.sliceTo(msg, 0) else switch (err) {
                .NeedDict => "dictionary required",
                .DataError => "input corrupted",
                .BufError => "unexpected end-of-file",
                else => unreachable,
            };
            return globalObject.throw("zlib error: {s}", .{message});
        }
    };
}

const BrotliCompressorContext = TodoContextRemoveMePleaseAndThankYou;
const BrotliDecompressorContext = TodoContextRemoveMePleaseAndThankYou;

const ZstdCompressorContext = TodoContextRemoveMePleaseAndThankYou;
const ZstdDecompressorContext = TodoContextRemoveMePleaseAndThankYou;

// TODO: Remove this bogus type
const TodoContextRemoveMePleaseAndThankYou = struct {
    pub fn init(this: *TodoContextRemoveMePleaseAndThankYou, format: Format) bun.JSError!void {
        _ = this;
        _ = format;
        @panic("TODO");
    }

    pub fn deinit(this: *TodoContextRemoveMePleaseAndThankYou) void {
        _ = this;
        @panic("TODO");
    }

    pub fn process(this: *TodoContextRemoveMePleaseAndThankYou, globalObject: *JSGlobalObject, chunk: []const u8) bun.JSError![]u8 {
        _ = this;
        _ = globalObject;
        _ = chunk;
        @panic("TODO");
    }

    pub fn flush(this: *TodoContextRemoveMePleaseAndThankYou, globalObject: *JSGlobalObject) bun.JSError![]u8 {
        _ = this;
        _ = globalObject;
        @panic("TODO");
    }
};

const std = @import("std");
const bun = @import("bun");

const jsc = bun.jsc;
const CallFrame = jsc.CallFrame;
const JSGlobalObject = jsc.JSGlobalObject;
const JSUint8Array = jsc.JSUint8Array;
const JSValue = jsc.JSValue;
