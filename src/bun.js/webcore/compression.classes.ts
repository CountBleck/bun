import { define } from "codegen/class-definitions";

export default [
  define({
    name: "CompressionStreamEncoder",
    construct: true,
    finalize: true,
    JSType: "0b11101110",
    configurable: false,
    klass: {},
    proto: {
      encode: {
        fn: "encode",
        length: 1,

        DOMJIT: {
          returns: "JSUint8Array",
          args: ["JSUint8Array"],
        },
      },
      flush: {
        fn: "flush",
        length: 0,

        DOMJIT: {
          returns: "JSUint8Array",
          args: [],
        },
      },
    },
  }),
  define({
    name: "DecompressionStreamDecoder",
    construct: true,
    finalize: true,
    JSType: "0b11101110",
    configurable: false,
    klass: {},
    proto: {
      decode: {
        fn: "decode",
        length: 1,

        DOMJIT: {
          returns: "JSUint8Array",
          args: ["JSUint8Array"],
        },
      },
      flush: {
        fn: "flush",
        length: 0,

        DOMJIT: {
          returns: "JSUint8Array",
          args: [],
        },
      },
    },
  }),
];
