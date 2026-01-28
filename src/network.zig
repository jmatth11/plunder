const std = @import("std");

const fd_path: []const u8 = "/proc/{}/fd";
var buffer: [4096]u8 = undefined;
var fixed_buffer: std.heap.FixedBufferAllocator = .init(&buffer);
var thread_alloc: std.heap.ThreadSafeAllocator = .{ .child_allocator = fixed_buffer.allocator() };

/// Errors related to network operations.
pub const Errors = error{
    /// No network sockets are open for the given process ID.
    no_sockets_open,
    /// Invalid IP.
    invalid_ip,
    /// Invalid network line.
    invalid_network_line,
};

/// Network types.
pub const NetworkType = enum {
    Tcp,
    Udp,

    /// Get string value for network type.
    pub fn to_str(self: *const NetworkType) []const u8 {
        return switch (self.*) {
            .Tcp => "TCP",
            .Udp => "UDP",
        };
    }
};

/// Network state enum.
pub const NetworkState = enum(u16) {
    unknown = 0,
    established,
    syn_sent,
    syn_recv,
    fin_wait1,
    fin_wait2,
    time_wait,
    close,
    close_wait,
    last_ack,
    listen,
    closing,
    new_syn_recv,

    /// Get the string value of the enum.
    pub fn to_str(self: *const NetworkState) []const u8 {
        return switch (self.*) {
            .unknown => "UNKNOWN",
            .established => "ESTABLISHED",
            .syn_sent => "SYN_SENT",
            .syn_recv => "SYN_RECV",
            .fin_wait1 => "FIN_WAIT1",
            .fin_wait2 => "FIN_WAIT2",
            .time_wait => "TIME_WAIT",
            .close => "CLOSE",
            .close_wait => "CLOSE_WAIT",
            .last_ack => "LAST_ACK",
            .listen => "LISTEN",
            .closing => "CLOSING",
            .new_syn_recv => "NEW_SYN_RECV",
        };
    }
};

/// NetworkInfo structure.
pub const NetworkInfo = struct {
    /// The inode.
    inode: usize,
    /// The network type.
    network: NetworkType,
    /// The state of the network.
    state: NetworkState,
    /// The local address.
    local_addr: std.net.Address,
    /// The remote address.
    remote_addr: std.net.Address,
    /// The kernel hash slot.
    kernel_hash_slot: usize,

    /// Format the info into a tablulated structure.
    pub fn format(self: *const NetworkInfo, writer: *std.Io.Writer, include_header: bool) !void {
        if (include_header) {
            _ = try writer.write("Type | State | Local Addr | Remote Addr | inode | Kernel Slot\n");
        }
        _ = try writer.write(self.network.to_str());
        _ = try writer.write(" | ");
        _ = try writer.write(self.state.to_str());
        _ = try writer.write(" | ");
        _ = try self.local_addr.format(writer);
        _ = try writer.write(" | ");
        _ = try self.remote_addr.format(writer);
        _ = try writer.write(" | ");
        _ = try writer.print("{}", .{self.inode});
        _ = try writer.write(" | ");
        _ = try writer.print("{}\n", .{self.kernel_hash_slot});
    }
};

/// Get the TCP network info for a given process ID.
pub fn get_tcp_info(alloc: std.mem.Allocator, pid: usize) ![]NetworkInfo {
    return try get_network_info(.Tcp, alloc, pid);
}

/// Get the UDP network info for a given process ID.
pub fn get_udp_info(alloc: std.mem.Allocator, pid: usize) ![]NetworkInfo {
    return try get_network_info(.Udp, alloc, pid);
}

/// Get the network info for the given process ID and network type.
fn get_network_info(comptime T: NetworkType, alloc: std.mem.Allocator, pid: usize) ![]NetworkInfo {
    const network_file = switch (T) {
        .Tcp => try std.fs.openFileAbsolute("/proc/net/tcp", .{}),
        .Udp => try std.fs.openFileAbsolute("/proc/net/udp", .{}),
    };
    defer network_file.close();

    const inodes = try get_socket_inodes(alloc, pid);
    defer alloc.free(inodes);

    var read_buf: [2048]u8 = undefined;

    var file_reader = network_file.reader(&read_buf);
    var result: std.array_list.Managed(NetworkInfo) = .init(alloc);
    errdefer result.deinit();
    // skip the header line
    _ = try file_reader.interface.takeDelimiter('\n');
    while (try file_reader.interface.takeDelimiter('\n')) |line| {
        const info_op: ?NetworkInfo = try parse_network_line(T, line, inodes);
        if (info_op) |info| {
            try result.append(info);
        }
    }
    return try result.toOwnedSlice();
}

/// Get the list of socket inodes for a given process ID.
fn get_socket_inodes(alloc: std.mem.Allocator, pid: usize) ![]usize {
    const f_alloc = thread_alloc.allocator();
    defer fixed_buffer.reset();

    const fp = try std.fmt.allocPrint(f_alloc, fd_path, .{pid});
    var dir = try std.fs.openDirAbsolute(fp, .{
        .iterate = true,
        .access_sub_paths = false,
        .no_follow = true,
    });
    defer dir.close();
    f_alloc.free(fp);
    var it = dir.iterate();

    var result: std.array_list.Managed(usize) = .init(alloc);
    errdefer result.deinit();

    while (try it.next()) |entry| {
        var link: [1024]u8 = undefined;
        const link_slice = try dir.readLink(entry.name, &link);
        if (std.mem.startsWith(u8, link_slice, "socket:[")) {
            const inode = try std.fmt.parseInt(usize, link_slice[8..(link_slice.len - 1)], 10);
            try result.append(inode);
        }
    }
    if (result.items.len == 0) {
        return Errors.no_sockets_open;
    }
    return try result.toOwnedSlice();
}

/// Convenience function to check if inode is in inodes list.
fn has_inode(inodes: []usize, inode: usize) bool {
    for (inodes) |entry| {
        if (entry == inode) {
            return true;
        }
    }
    return false;
}

/// Parse the given hex formated IP and port into an Address.
fn get_ip4_addr(ip_hex: []const u8, port_hex: []const u8) !std.net.Address {
    if (ip_hex.len < 8) {
        return Errors.invalid_ip;
    }
    var ip: [4]u8 = @splat(0);
    ip[0] = try std.fmt.parseInt(u8, ip_hex[0..2], 16);
    ip[1] = try std.fmt.parseInt(u8, ip_hex[2..4], 16);
    ip[2] = try std.fmt.parseInt(u8, ip_hex[4..6], 16);
    ip[3] = try std.fmt.parseInt(u8, ip_hex[6..8], 16);
    const port: u16 = try std.fmt.parseInt(u16, port_hex, 16);
    const result: std.net.Address = .initIp4(ip, port);
    return result;
}

/// Parse the network line into a NetworkInfo if it is included in the list of
/// given inodes.
fn parse_network_line(network_type: NetworkType, line: []const u8, inodes: []usize) !?NetworkInfo {
    var parser: std.fmt.Parser = .{ .bytes = line, .i = 0 };
    const sl = std.mem.trim(u8, parser.until(':'), " ");
    parser.i += 2;
    if (parser.i > parser.bytes.len) {
        return Errors.invalid_network_line;
    }
    const local_ip_hex = parser.until(':');
    parser.i += 1;
    const local_port = parser.until(' ');
    parser.i += 1;
    const remote_ip_hex = parser.until(':');
    parser.i += 1;
    const remote_port = parser.until(' ');
    parser.i += 1;
    const state = parser.until(' ');
    parser.i += 1;
    // skip tx_queue:rx_queue
    _ = parser.until(' ');
    parser.i += 1;
    // skip tr:tm->when
    _ = parser.until(' ');
    parser.i += 1;
    // skip retrnsmt
    _ = parser.until(' ');
    parser.i += 1;
    var skip_count: usize = 0;
    // skip variable whitespace columns (UID, timeout)
    while (parser.peek(0)) |char| {
        if (std.ascii.isDigit(char)) {
            skip_count += 1;
            _ = parser.until(' ');
            parser.i += 1;
            if (skip_count == 2) {
                break;
            }
        } else {
            parser.i += 1;
        }
    }
    const inode_str = parser.until(' ');
    const inode = try std.fmt.parseInt(usize, inode_str, 10);
    if (has_inode(inodes, inode)) {
        const info: NetworkInfo = .{
            .inode = inode,
            .state = @enumFromInt(try std.fmt.parseInt(u16, state, 16)),
            .network = network_type,
            .local_addr = try get_ip4_addr(local_ip_hex, local_port),
            .remote_addr = try get_ip4_addr(remote_ip_hex, remote_port),
            .kernel_hash_slot = try std.fmt.parseInt(usize, sl, 10),
        };
        return info;
    }
    return null;
}
