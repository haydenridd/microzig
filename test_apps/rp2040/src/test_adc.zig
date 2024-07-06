const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;

fn execute() self_test.Result {

    // TODO: Change sampling freq + comment on dedicated function for this maybe?
    // rp2040.adc.apply(.{ .sample_frequency = 12000 });
    const adc0 = rp2040.adc.input(0);
    rp2040.adc.set_enabled(true);
    const conv: u32 = @intCast(rp2040.adc.convert_one_shot_blocking(adc0) catch return .{ .fail = .{
        .msg = "Error on ADC",
        .context = @src(),
    } });

    const approx_mv = (conv * 3300) / 4096;
    if ((approx_mv < 1300) or (approx_mv > 1900))
        return .{ .fail = .{
            .msg = "Did not get ADC mV reading of approx 1600mV",
            .context = @src(),
        } };

    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "adc",
    .execute = execute,
};
