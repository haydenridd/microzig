const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;

fn execute() self_test.Result {
    rp2040.adc.instance.set_enabled(true);
    const input_channels: []const rp2040.adc.Input = &.{ .ain0, .ain1, .ain2, .temp_sensor };
    inline for (input_channels, &.{ 2475, 1650, 825, 700 }) |input_channel, expected_mv| {

        // TODO: Change sampling freq + comment on dedicated function for this maybe?
        // rp2040.adc.instance.apply(.{ .sample_frequency = 12000 });
        input_channel.configure_gpio_pin();
        rp2040.adc.instance.select_input(input_channel);
        if (input_channel == .temp_sensor) {
            rp2040.adc.instance.set_temp_sensor_enabled(true);
        }
        const conv: u32 = @intCast(rp2040.adc.instance.convert_one_shot_blocking() catch return .{ .fail = .{
            .msg = "Error on ADC",
            .context = @src(),
        } });

        const approx_mv = (conv * 3300) / 4096;
        if ((approx_mv < (expected_mv - 200)) or (approx_mv > (expected_mv + 200))) {
            std.log.err("Unexpected ADC reading of: {d} mV for expected value of: {d} mV", .{ approx_mv, expected_mv });
            return .{ .fail = .{
                .msg = "Bad ADC mV reading",
                .context = @src(),
            } };
        }
    }
    rp2040.adc.instance.set_enabled(false);

    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "adc",
    .execute = execute,
};
