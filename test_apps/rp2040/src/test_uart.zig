const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const Pin = rp2040.gpio.Pin;
const uart = rp2040.uart;
const time = rp2040.time;

const US100 = struct {
    pub const Command = enum(u8) {
        DISTANCE = 0x55,
        TEMPERATURE = 0x50,
    };
};

/// Depending on how we powered on, the us100 can be in an odd state, just keep writing/reading back
/// a byte until we don't have any errors on the line.
fn unstickUs100(uart_inst: uart.UART) bool {
    // Give up after 10 tries
    for (0..10) |_| {
        uart_inst.clear_errors();
        uart_inst.write_blocking(&.{@intFromEnum(US100.Command.TEMPERATURE)}, time.Duration.from_ms(10)) catch continue;
        _ = uart_inst.read_word(time.Duration.from_ms(10)) catch continue;
        time.sleep_ms(10);
        return true;
    }
    return false;
}

fn execute() self_test.Result {
    const tx = rp2040.gpio.num(8);
    const rx = rp2040.gpio.num(9);
    inline for (&.{ tx, rx }) |pin| {
        pin.set_function(.uart);
    }

    const uart1 = uart.instance.UART1;

    // Ensure invalid baud rates can be caught at runtime
    const bad_config: uart.Config = .{
        .clock_config = rp2040.clock_config,
        .baud_rate = 0,
    };
    const ret = uart1.apply_runtime(bad_config);
    if (ret != uart.ConfigError.UnsupportedBaudRate) {
        return .{ .fail = .{
            .msg = "Unexpected error returned",
            .context = @src(),
        } };
    }

    uart1.apply(.{
        .clock_config = rp2040.clock_config,
        .baud_rate = 9600,
    });

    if (!unstickUs100(uart1)) {
        return .{ .fail = .{
            .msg = "Unable to unstick US100 device",
            .context = @src(),
        } };
    }

    uart1.write_blocking(&.{@intFromEnum(US100.Command.TEMPERATURE)}, time.Duration.from_ms(10)) catch |e| {
        std.log.err("Error encountered: {any}", .{e});
        return .{ .fail = .{
            .msg = "Error on UART",
            .context = @src(),
        } };
    };

    const temperature_byte = uart1.read_word(time.Duration.from_ms(10)) catch |e| {
        std.log.err("Error encountered: {any}", .{e});
        return .{ .fail = .{
            .msg = "Error on UART",
            .context = @src(),
        } };
    };

    if ((0x30 > temperature_byte) or (temperature_byte > 0x50)) {
        std.log.err("Weird temp byte value: 0x{X}", .{temperature_byte});
        return .{ .fail = .{
            .msg = "Bad temperature byte",
            .context = @src(),
        } };
    }
    time.sleep_ms(1000);

    uart1.write_blocking(&.{@intFromEnum(US100.Command.DISTANCE)}, time.Duration.from_ms(10)) catch |e| {
        std.log.err("Error encountered: {any}", .{e});
        return .{ .fail = .{
            .msg = "Error on UART",
            .context = @src(),
        } };
    };

    var distance_bytes: [2]u8 = undefined;
    uart1.read_blocking(&distance_bytes, time.Duration.from_ms(50)) catch |e| {
        std.log.err("Error encountered: {any}", .{e});
        return .{ .fail = .{
            .msg = "Error on UART",
            .context = @src(),
        } };
    };
    const distance_mm: u16 = @as(u16, distance_bytes[0]) * 256 + @as(u16, distance_bytes[1]);

    // Pretty hacky test, basically just ensuring we read SOMETHING valid
    if ((distance_mm == 0) or (distance_mm == std.math.maxInt(u16))) {
        std.log.err("Weird distance value: {d}", .{distance_mm});
        return .{ .fail = .{
            .msg = "Bad distance val!",
            .context = @src(),
        } };
    }

    // Write something that doesn't get a response, expect a timeout on read
    uart1.write_blocking(&.{ 0xA5, 0xA5 }, time.Duration.from_ms(10)) catch |e| {
        std.log.err("Error encountered: {any}", .{e});
        return .{ .fail = .{
            .msg = "Error on UART",
            .context = @src(),
        } };
    };

    const timeout_ret = uart1.read_blocking(&distance_bytes, time.Duration.from_ms(50));
    if (timeout_ret != uart.TransactionError.Timeout) {
        return .{ .fail = .{
            .msg = "Unexpected error returned",
            .context = @src(),
        } };
    }

    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "uart",
    .execute = execute,
};
