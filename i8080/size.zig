pub const Size = enum(u1) {
    /// Byte
    b,
    /// Word
    w,

    pub fn from(val: u1) Size {
        return @enumFromInt(val);
    }

    pub fn T(comptime self: @This()) type {
        return switch (self) {
            .b => u8,
            .w => u16,
        };
    }
};
