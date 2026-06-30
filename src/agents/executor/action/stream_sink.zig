//! Thread-local stream sink for executor action blocks (MCP, skills).

const stream = @import("../../../stream/mod.zig");

threadlocal var tls_sink: ?stream.Sink = null;

pub fn set(sink: ?stream.Sink) void {
    tls_sink = sink;
}

pub fn get() ?stream.Sink {
    return tls_sink;
}
