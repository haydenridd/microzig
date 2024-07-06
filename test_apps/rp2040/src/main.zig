const std = @import("std");
const microzig = @import("microzig");
const rtt = @import("rtt");
const rp2040 = microzig.hal;
const time = rp2040.time;
const Pin = rp2040.gpio.Pin;

const self_test = @import("self_test.zig");
const test_instances: []const self_test.Instance = &.{
    @import("test_gpio.zig").instance,
    @import("test_adc.zig").instance,
    @import("test_i2c.zig").instance,
    @import("test_spi.zig").instance,
    @import("test_pwm.zig").instance,
};

pub const microzig_options = .{
    .logFn = rtt.logFn,
};

const test_logger = std.log.scoped(.SelfTest);

fn blinkLed(led_gpio: *Pin) void {
    led_gpio.put(0);
    time.sleep_ms(500);
    led_gpio.put(1);
    time.sleep_ms(500);
}

pub fn main() !void {
    // Don't forget to bring a blinky!
    var led_gpio = rp2040.gpio.num(25);
    led_gpio.set_direction(.out);
    led_gpio.set_function(.sio);
    led_gpio.put(1);

    test_logger.info("Starting tests", .{});

    inline for (test_instances) |test_inst| {
        switch (test_inst.execute()) {
            .pass => {
                test_logger.info("PASS: {s}", .{test_inst.name});
            },
            .fail => |failure| {
                test_logger.err("FAIL: {s}", .{test_inst.name});
                failure.log(test_logger);
                std.debug.panic("Test failure", .{});
            },
        }
    }

    // End and just idle forever
    test_logger.info("Tests completed", .{});
    while (true) {
        blinkLed(&led_gpio);
    }
}
