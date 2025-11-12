const std = @import("std");

pub const Permissions = enum(u8) {
    read = 1,
    write = 1<<1,
    execute = 1<<2,
    shared = 1<<3,
};

pub const Info = struct {
    pathname: ?[]const u8,
    start_addr: usize,
    end_addr: usize,
    perm: Permissions,
    offset: u32,
    dev_major: u8,
    dev_minor: u8,
    inode: u32,

    pub fn is_read(self: *Info) bool {
        return (self.perm & Permissions.read) == Permissions.read;
    }
    pub fn is_write(self: *Info) bool {
        return (self.perm & Permissions.write) == Permissions.write;
    }
    pub fn is_execute(self: *Info) bool {
        return (self.perm & Permissions.execute) == Permissions.execute;
    }
    pub fn is_shared(self: *Info) bool {
        return (self.perm & Permissions.shared) == Permissions.shared;
    }
};

pub const Manager = struct {

};

