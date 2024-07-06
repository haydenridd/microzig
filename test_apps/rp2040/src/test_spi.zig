const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const Pin = rp2040.gpio.Pin;
const spi = rp2040.spi;
const time = rp2040.time;

const W25Q16JV = struct {
    pub const Command = enum(u8) {
        POWERUP_AND_DEVID = 0xAB,
        SECTOR_ERASE = 0x20,
        CHIP_ERASE = 0x60,
        READ_STATUS1 = 0x05,
        WRITE_ENABLE = 0x06,
        PAGE_PROGRAM = 0x02,
        READ = 0x03,
    };
    pub const DefaultValues = struct {
        pub const DEVICE_ID: u8 = 0x14;
    };
};

fn pollOnBusy(spi_inst: spi.SPI, csn_pin: Pin) void {
    var reg_data: [2]u8 = .{ 0, 1 };
    while ((reg_data[1] & 0b1) > 0) {
        csn_pin.put(0);
        spi_inst.transceive_blocking(
            u8,
            &.{ @intFromEnum(W25Q16JV.Command.READ_STATUS1), 0 },
            &reg_data,
        );
        csn_pin.put(1);
    }
}

fn execute() self_test.Result {
    const csn = rp2040.gpio.num(1);
    csn.set_function(.sio);
    csn.set_direction(.out);
    csn.put(1);

    const hodi = rp2040.gpio.num(3);
    const hido = rp2040.gpio.num(4);
    const sck = rp2040.gpio.num(2);
    inline for (&.{ hodi, hido, sck }) |pin| {
        pin.set_function(.spi);
    }

    // Try a couple different baud rates
    inline for (&.{ 500_000, 1_000_000, 2_000_000 }) |baud_rate| {
        const cfg = comptime spi.Config{
            .clock_config = rp2040.clock_config,
            .baud_rate = baud_rate,
        };

        const spi0 = spi.instance.SPI0;
        spi0.apply(cfg) catch unreachable;

        // Reusable read buffer
        var read_data: [64]u8 = [_]u8{0} ** 64;

        // Release powerdown + read device ID
        csn.put(0);
        spi0.transceive_blocking(
            u8,
            &.{ @intFromEnum(W25Q16JV.Command.POWERUP_AND_DEVID), 0x0, 0x0, 0x0, 0x0 },
            read_data[0..5],
        );
        csn.put(1);
        if (read_data[4] != W25Q16JV.DefaultValues.DEVICE_ID)
            return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };

        // Write enable
        csn.put(0);
        spi0.write_blocking(u8, &.{@intFromEnum(W25Q16JV.Command.WRITE_ENABLE)});
        csn.put(1);

        // Erase the first sector of flash
        csn.put(0);
        spi0.write_blocking(u8, &.{ @intFromEnum(W25Q16JV.Command.SECTOR_ERASE), 0x0, 0x0, 0x0 });
        csn.put(1);
        pollOnBusy(spi0, csn);

        // Read 16 bytes from memory, should all be erased
        csn.put(0);
        spi0.write_blocking(u8, &.{ @intFromEnum(W25Q16JV.Command.READ), 0x0, 0x0, 0x0 });
        spi0.read_blocking(u8, 0x0, read_data[0..16]);
        csn.put(1);

        for (read_data[0..16]) |byte| {
            if (byte != 0xFF) return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };
        }

        // Write enable
        csn.put(0);
        spi0.write_blocking(u8, &.{@intFromEnum(W25Q16JV.Command.WRITE_ENABLE)});
        csn.put(1);

        // Write 16 bytes to memory
        const write_data: []const u8 = &.{
            0x0,
            0x1,
            0x2,
            0x3,
            0x4,
            0x5,
            0x6,
            0x7,
            0x8,
            0x9,
            0xA,
            0xB,
            0xC,
            0xD,
            0xE,
            0xF,
        };
        const header: []const u8 = &.{ @intFromEnum(W25Q16JV.Command.PAGE_PROGRAM), 0x0, 0x0, 0x0 };
        const payload: []const u8 = header ++ write_data;
        csn.put(0);
        spi0.write_blocking(u8, payload);
        csn.put(1);
        pollOnBusy(spi0, csn);

        // Read back 16 bytes
        csn.put(0);
        spi0.write_blocking(u8, &.{ @intFromEnum(W25Q16JV.Command.READ), 0x0, 0x0, 0x0 });
        spi0.read_blocking(u8, 0x0, read_data[0..16]);
        csn.put(1);

        for (read_data[0..16], write_data) |byte, expected_byte| {
            if (byte != expected_byte) return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };
        }

        // Disable + return peripheral to reset state
        spi0.reset();
    }
    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "spi",
    .execute = execute,
};
