const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const Pin = rp2040.gpio.Pin;
const uart = rp2040.uart;
const time = rp2040.time;
const dma = rp2040.dma;

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
    uart1.apply(.{
        .clock_config = rp2040.clock_config,
        .baud_rate = 9600,
    });

    const longer_buffer = "A MUCH LONGER MY NAME JEFF!\r\n";
    const dma0 = dma.instance.DMA0;
    dma0.apply(.{
        .transfer_word_size = .ONE_BYTE,
        .transfer_count = longer_buffer.len,
        .read_increment = true,
        .write_increment = false,
        .dreq = uart1.dma_dreq_tx(),
        .read_addr = @as(u32, @intFromPtr(longer_buffer)),
        .write_addr = uart1.dma_tx_address(),
    });
    dma0.enable();
    while (dma0.is_busy()) {}

    var read_buffer: [100]u8 = undefined;

    const dma1 = dma.instance.DMA1;
    dma1.apply(.{
        .transfer_word_size = .ONE_BYTE,
        .transfer_count = 20,
        .read_increment = false,
        .write_increment = true,
        .dreq = uart1.dma_dreq_rx(),
        .read_addr = uart1.dma_rx_address(),
        .write_addr = @as(u32, @intFromPtr(&read_buffer)),
    });
    dma1.enable();

    while (dma1.is_busy() or dma0.is_busy()) {}
    dma0.disable();
    dma1.disable();

    std.log.info("Received 20 bytes: {s}", .{read_buffer[0..20]});

    // uart1.write_blocking("MY NAME JEFF\r\n", time.Duration.from_ms(100)) catch unreachable;
    // if (!unstickUs100(uart1)) {
    //     return .{ .fail = .{
    //         .msg = "Unable to unstick US100 device",
    //         .context = @src(),
    //     } };
    // }

    // uart1.write_blocking(&.{@intFromEnum(US100.Command.TEMPERATURE)}, time.Duration.from_ms(10)) catch |e| {
    //     std.log.err("Error encountered: {any}", .{e});
    //     return .{ .fail = .{
    //         .msg = "Error on UART",
    //         .context = @src(),
    //     } };
    // };

    // const temperature_byte = uart1.read_word(time.Duration.from_ms(10)) catch |e| {
    //     std.log.err("Error encountered: {any}", .{e});
    //     return .{ .fail = .{
    //         .msg = "Error on UART",
    //         .context = @src(),
    //     } };
    // };

    // if ((0x30 > temperature_byte) or (temperature_byte > 0x50)) {
    //     std.log.err("Weird temp byte value: 0x{X}", .{temperature_byte});
    //     return .{ .fail = .{
    //         .msg = "Bad temperature byte",
    //         .context = @src(),
    //     } };
    // }
    // time.sleep_ms(1000);

    // uart1.write_blocking(&.{@intFromEnum(US100.Command.DISTANCE)}, time.Duration.from_ms(10)) catch |e| {
    //     std.log.err("Error encountered: {any}", .{e});
    //     return .{ .fail = .{
    //         .msg = "Error on UART",
    //         .context = @src(),
    //     } };
    // };

    // var distance_bytes: [2]u8 = undefined;
    // uart1.read_blocking(&distance_bytes, time.Duration.from_ms(50)) catch |e| {
    //     std.log.err("Error encountered: {any}", .{e});
    //     return .{ .fail = .{
    //         .msg = "Error on UART",
    //         .context = @src(),
    //     } };
    // };
    // const distance_mm: u16 = @as(u16, distance_bytes[0]) * 256 + @as(u16, distance_bytes[1]);

    // // Pretty hacky test, basically just ensuring we read SOMETHING valid
    // if ((distance_mm == 0) or (distance_mm == std.math.maxInt(u16))) {
    //     std.log.err("Weird distance value: {d}", .{distance_mm});
    //     return .{ .fail = .{
    //         .msg = "Bad distance val!",
    //         .context = @src(),
    //     } };
    // }
    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "uart",
    .execute = execute,
};
