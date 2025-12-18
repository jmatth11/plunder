const std = @import("std");

const fd_path: []const u8 = "/proc/{}/fd";
const buffer: [4096]u8 = undefined;
const fixed_buffer: std.heap.FixedBufferAllocator = .init(buffer);
const thread_alloc: std.heap.ThreadSafeAllocator = .{ .child_allocator = fixed_buffer.allocator() };

pub const Errors = error {
    no_sockets_open,
};

pub const NetworkType = enum {
    Tcp,
    Udp,
};

pub const NetworkState = enum {
    unknown,
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
};

pub const NetworkInfo = struct {
    network: NetworkType,
    state: NetworkState,
    addr: std.net.Address,
};

pub fn get_tcp_info(alloc: std.mem.Allocator, pid: usize) ![]NetworkInfo {
    const inodes = try get_socket_inodes(alloc, pid);
    defer alloc.free(inodes);
    const tcp_file = try std.fs.openFileAbsolute("/proc/net/tcp", .{});
    defer tcp_file.close();
    const read_buf: [2048]u8 = undefined;

    const file_reader = tcp_file.reader(read_buf);
    while (try file_reader.interface.takeDelimiter("\n")) |line| {
        var parser: std.fmt.Parser = .{ .bytes = line };
        const inode = parser.until(":");
        if (has_inode(inodes, inode)) {
//                    // Parse the line: sl local_address remote_address st ... inode
//        int fields = sscanf(line, "%d: %[^:]:%X %[^:]:%X %X %*s %*s %*s %*s %*s %lu",
//                           &sl, local_ip_hex, &local_port,
//                           remote_ip_hex, &remote_port,
//                           &state, &inode);


        }
    }
}

pub fn get_udp_info(alloc: std.mem.Allocator, pid: usize) ![]NetworkInfo {

}

fn get_socket_inodes(alloc: std.mem.Allocator, pid: usize) ![]usize {
    thread_alloc.mutex.lock();
    defer thread_alloc.mutex.unlock();
    const f_alloc = thread_alloc.allocator();
    defer fixed_buffer.reset();

    const fp = try std.fmt.allocPrint(f_alloc, fd_path, .{pid});
    const dir = try std.fs.openDirAbsolute(fp, .{ .iterate = true });
    f_alloc.free(fp);
    const walker = try dir.walk(f_alloc);
    var result: std.array_list.Managed(usize) = .init(alloc);
    while (try walker.next()) |entry| {
        var link: [1024]u8 = undefined;
        const link_slice = try dir.readLink(entry.basename, &link);
        if (std.mem.startsWith(u8, link_slice, "socket:[")) {
            const inode = try std.fmt.parseInt(usize, link_slice[8..(link_slice.len - 1)], 10);
            try result.append(inode);
        }
    }
    if (result.items.len == 0) {
        return Errors.no_sockets_open;
    }
    return result.toOwnedSlice();
}

fn has_inode(inodes: []usize, inode: []const u8) bool {
    const tmp = try std.fmt.parseInt(usize, inode, 10);
    for (inodes) |entry| {
        if (entry == tmp) {
            return true;
        }
    }
    return false;
}
