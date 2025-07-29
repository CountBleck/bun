const DecompressionStreamEncoder = @This();

pub const js = jsc.Codegen.JSDecompressionStreamEncoder;
pub const toJS = js.toJS;
pub const fromJS = js.fromJS;
pub const fromJSDirect = js.fromJSDirect;

// TODO: Fields

pub fn finalize(this: *DecompressionStreamEncoder) void {
    _ = this;
    @panic("TODO");
}

pub fn constructor(_: *JSGlobalObject, callFrame: *CallFrame) bun.JSError!*DecompressionStreamEncoder {
    _ = callFrame;
    @panic("TODO");
}

pub fn decode(this: *DecompressionStreamEncoder, globalObject: *jsc.JSGlobalObject, callFrame: *CallFrame) bun.JSError!JSValue {
    _ = this;
    _ = globalObject;
    _ = callFrame;
    @panic("TODO");
}

pub fn flush(this: *DecompressionStreamEncoder, globalObject: *jsc.JSGlobalObject, _: *CallFrame) bun.JSError!JSValue {
    _ = this;
    _ = globalObject;
    @panic("TODO");
}

const bun = @import("bun");

const jsc = bun.jsc;
const CallFrame = jsc.CallFrame;
const JSGlobalObject = jsc.JSGlobalObject;
const JSUint8Array = jsc.JSUint8Array;
const JSValue = jsc.JSValue;
