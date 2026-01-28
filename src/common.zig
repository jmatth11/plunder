const std = @import("std");

pub const Errors = error {
    out_of_bounds,
    delimiter_not_found,
};

pub const StringList = std.array_list.Managed([]const u8);

pub const StringView = struct {
    ref: []const u8,
    delimiter: u8,
    len: usize = 0,

    pub fn init(ref: []const u8, delimiter: u8) StringView {
        var result: StringView = .{
            .ref = ref,
            .delimiter = delimiter,
        };
        result.len = result._len();
        return result;
    }

    pub fn at(self: *StringView, idx: usize) ![]const u8 {
        if (idx > self.len) {
            return Errors.out_of_bounds;
        }
        // if there was no delimiter found return the whole string.
        if (self.len == 0) {
            return self.ref;
        }
        var ref_idx: usize = 0;
        var step: usize = 0;
        var start: usize = 0;
        while (ref_idx < self.ref.len) : (ref_idx += 1) {
            if (step == idx) {
                const end = std.mem.indexOfScalar(u8, self.ref[start..], self.delimiter);
                if (end == null) {
                    return Errors.delimiter_not_found;
                }
                return self.ref[start..end.?];
            }
            if (self.ref[ref_idx] == self.delimiter) {
                step += 1;
                start = ref_idx + 1;
            }
        }
        unreachable;
    }

    fn _len(self: *StringView) usize {
        var idx: usize = 0;
        var count: usize = 0;
        while (idx < self.ref.len) : (idx += 1) {
            if (self.ref[idx] == self.delimiter) {
                count += 1;
            }
        }
        return count;
    }


};
