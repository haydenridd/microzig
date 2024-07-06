const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const Pin = rp2040.gpio.Pin;
const time = rp2040.time;

fn execute() self_test.Result {
    var gpio16 = rp2040.gpio.num(16);
    var gpio17 = rp2040.gpio.num(17);
    return verifyGpioPair(&gpio16, &gpio17);
}

pub const instance: self_test.Instance = .{
    .name = "gpio",
    .execute = execute,
};

/// GPIO testing procedure:
/// - Two GPIOs shorted together, GPIO "OUTPUT" and GPIO "INPUT"
/// - Configure INPUT as pull-down input
/// - Measure INPUT, confirm low
/// - Configure OUTPUT as output, force low
/// - Measure INPUT, confirm low
/// - Force OUTPUT high
/// - Measure INPUT, confirm high
/// - Disable OUTPUT
/// - Measure INPUT, confirm low
/// - Change INPUT to pull-up
/// - Measure INPUT, confirm high
/// - Enable OUTPUT, force high
/// - Measure INPUT, confirm high
/// - Force OUTPUT low
/// - Measure INPUT, confirm low
/// - Disable both GPIOs + remove pull-ups
fn verifyGpioPair(output: *Pin, input: *Pin) self_test.Result {

    // Start both pins in known state by disabling + removing any pull-up/downs
    output.set_pull(.disabled);
    output.set_function(.disabled);
    input.set_pull(.disabled);
    input.set_function(.disabled);

    // Enable INPUT as input with pulldown, INPUT should read LOW
    input.set_pull(.down);
    input.set_direction(.in);
    input.set_function(.sio);
    time.sleep_ms(1);
    if (input.read() != 0)
        return .{ .fail = .{
            .msg = "Expected GPIO LOW",
            .context = @src(),
        } };

    // Set OUTPUT LOW, INPUT should read LOW
    output.set_direction(.out);
    output.set_function(.sio);
    output.put(0);
    time.sleep_ms(1);
    if (input.read() != 0) return .{ .fail = .{
        .msg = "Expected GPIO LOW",
        .context = @src(),
    } };

    // Set OUTPUT HIGH, INPUT should read HIGH
    output.put(1);
    time.sleep_ms(1);
    if (input.read() != 1) return .{ .fail = .{
        .msg = "Expected GPIO HIGH",
        .context = @src(),
    } };

    // Disable OUTPUT, INPUT should read LOW
    output.set_function(.disabled);
    time.sleep_ms(1);
    if (input.read() != 0) return .{ .fail = .{
        .msg = "Expected GPIO LOW",
        .context = @src(),
    } };

    // Enable INPUT as input with pullup, INPUT should read HIGH
    input.set_pull(.up);
    time.sleep_ms(1);
    if (input.read() != 1) return .{ .fail = .{
        .msg = "Expected GPIO HIGH",
        .context = @src(),
    } };

    // Set OUTPUT HIGH, INPUT should read HIGH
    output.set_function(.sio);
    output.put(1);
    time.sleep_ms(1);
    if (input.read() != 1) return .{ .fail = .{
        .msg = "Expected GPIO HIGH",
        .context = @src(),
    } };

    // Set OUTPUT LOW, INPUT should read LOW
    output.put(0);
    time.sleep_ms(1);
    if (input.read() != 0) return .{ .fail = .{
        .msg = "Expected GPIO LOW",
        .context = @src(),
    } };

    // Return pins to disabled
    input.set_pull(.disabled);
    input.set_function(.disabled);
    output.set_pull(.disabled);
    output.set_function(.disabled);

    return .pass;
}
