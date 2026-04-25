allocator: std.mem.Allocator,

ram: []u8,
rom: []const u8,
vga: VGA,

const RAM_START = 0x00000;
const RAM_END = 0x9FFFF;
const RAM_SIZE = RAM_END - RAM_START;

const ROM_START = 0xF0000;
const ROM_END = 0xFFFFF;
const ROM_SIZE = ROM_END - ROM_START;

const VGA_START = 0xB0000;
const VGA_END = 0xBFFFF;
const VGA_SIZE = VGA_END - VGA_START;

const GARBAGE_DATA = 0xAA;

pub fn init(io: std.Io, alloctor: std.mem.Allocator, bios_path: []const u8) !Self {
    var self: Self = .{
        .allocator = alloctor,
        .rom = undefined,
        .ram = try alloctor.alloc(u8, RAM_SIZE),
        .vga = .{},
    };

    try self.loadBIOS(io, bios_path);

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.rom);
    self.allocator.free(self.ram);
}

pub fn loadBIOS(self: *Self, io: std.Io, bios_path: []const u8) !void {
    var mem = try self.allocator.alloc(u8, ROM_SIZE);
    self.rom = mem;

    var file_task = io.async(std.Io.Dir.openFile, .{ .cwd(), io, bios_path, .{} });
    defer if (file_task.cancel(io)) |file| file.close(io) else |_| {};

    const f: std.Io.File = try file_task.await(io);

    const file_size: usize = @intCast((try f.stat(io)).size);

    if (file_size > mem.len)
        return error.file_too_large;

    const offset = mem.len - file_size;

    const dst = mem[offset..mem.len];

    const read_size = try f.readPositionalAll(io, dst, 0);

    if (read_size != file_size)
        return error.read_size_not_match;
}

fn read(ctx: ?*anyopaque, addr: u20) u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    return switch (addr) {
        RAM_START...RAM_END => self.readRAM(addr),
        VGA_START...VGA_END => self.vga.read(addr),
        ROM_START...ROM_END => self.readROM(addr),
        else => data: {
            log.warn("read from unknown memory: {X:0>5}", .{addr});
            break :data GARBAGE_DATA;
        },
    };
}

fn readRAM(self: *const Self, addr: u20) u8 {
    const offset = addr - RAM_START;
    const data = if (offset < self.ram.len) self.ram[@intCast(offset)] else GARBAGE_DATA;

    log.debug("RAM read: {X:0>5} -> {X:0>5} -> {X:0>2}", .{ offset, addr, data });
    return data;
}

fn readROM(self: *const Self, addr: u20) u8 {
    const offset = addr - ROM_START;
    const data = if (offset < self.rom.len) self.rom[@intCast(offset)] else GARBAGE_DATA;

    log.debug("ROM read: {X:0>5} -> {X:0>5} -> {X:0>2}", .{ offset, addr, data });
    return data;
}

fn write(ctx: ?*anyopaque, addr: u20, data: u8) void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    switch (addr) {
        RAM_START...RAM_END => self.writeRAM(addr, data),
        VGA_START...VGA_END => self.vga.write(addr, data),
        ROM_START...ROM_END => log.warn("tried writing to ROM memory: {X:0>5}", .{addr}),
        else => log.warn("tried writing to unknown memory: {X:0>5}", .{addr}),
    }
}

fn writeRAM(self: *Self, addr: u20, data: u8) void {
    const offset = addr - RAM_START;
    log.debug("RAM write: {X:0>5} <- {X:0>5} <- {X:0>2}", .{ offset, addr, data });

    if (offset < self.ram.len) self.ram[@intCast(offset)] = data;
}

const vtable: Bus.VTable = .{
    .read_fn = &read,
    .write_fn = &write,
};

pub fn bus(self: *Self) Bus {
    return .{ .ctx = self, .vtable = &vtable };
}

const std = @import("std");
const panic = std.debug.panic;
const log = std.log.scoped(.ibm_pc_bus);

const Self = @This();

const Bus = @import("I8086").Bus;
const VGA = @import("VGA.zig");
