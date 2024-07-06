const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const Pin = rp2040.gpio.Pin;
const pwm = rp2040.pwm;
const time = rp2040.time;

fn execute() self_test.Result {
    var gpio18 = rp2040.gpio.num(18);
    gpio18.set_function(.pwm);

    const PwmGp18 = pwm.Pwm(1, .a);
    var pwm_gp18: PwmGp18 = .{};
    pwm_gp18.set_level(128);
    var pwm_gp18_slice = pwm_gp18.slice();
    pwm_gp18_slice.set_wrap(256);
    pwm_gp18_slice.set_clk_div(128, 0);

    // var gpio19 = rp2040.gpio.num(19);
    // gpio19.set_function(.pwm);
    // const PwmGp19 = pwm.Pwm(1, .b);
    // var pwm_gp19: PwmGp19 = .{};
    // pwm_gp19.set_level(128);
    // var pwm_gp19_slice = pwm_gp19.slice();
    // pwm_gp19_slice.set_wrap(256);
    // pwm_gp19_slice.set_clk_div(128, 0);
    // pwm_gp19_slice.enable();

    // pwm_gp18_slice.enable();
    // pwm_gp18_slice.disable();
    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "pwm",
    .execute = execute,
};
