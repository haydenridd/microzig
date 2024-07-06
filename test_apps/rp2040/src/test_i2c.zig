const std = @import("std");
const self_test = @import("self_test.zig");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const Pin = rp2040.gpio.Pin;
const time = rp2040.time;

const ConfigurationState = enum {
    init,
    deinit,
};

fn configure_gpio_for_i2c(pin: Pin, config: ConfigurationState) void {
    switch (config) {
        .init => {
            pin.set_function(.i2c);
            pin.set_pull(.up);
            pin.set_slew_rate(.slow);
            pin.set_schmitt_trigger(.enabled);
        },
        .deinit => {
            // Not setting slew_rate and/or schmitt trigger since init() sets them to their POR default values
            pin.set_pull(.disabled);
            pin.set_function(.disabled);
        },
    }
}

fn execute() self_test.Result {
    const MSA301 = struct {
        pub const address: rp2040.i2c.Address = @enumFromInt(0x26);

        pub const Registers = struct {
            pub const DEVICE_ID = 0x01;
            pub const OFFSETX = 0x38;
        };
        pub const DefaultValues = struct {
            pub const DEVICE_ID: u8 = 0x13;
        };
    };

    const Setup = struct {
        instance_num: u1,
        sda_num: u5,
        scl_num: u5,
    };
    const setups = &.{
        Setup{ .instance_num = 0, .sda_num = 12, .scl_num = 13 },
        Setup{ .instance_num = 1, .sda_num = 10, .scl_num = 11 },
    };

    const TransactionError = rp2040.i2c.TransactionError;
    const ConfigError = rp2040.i2c.ConfigError;

    inline for (setups) |setup| {
        const sda = rp2040.gpio.num(setup.sda_num);
        const scl = rp2040.gpio.num(setup.scl_num);
        configure_gpio_for_i2c(sda, .init);
        configure_gpio_for_i2c(scl, .init);

        var i2c_inst = rp2040.i2c.instance.num(
            setup.instance_num,
        );

        // Bad baud rate
        const ret2 = i2c_inst.apply(.{
            .clock_config = rp2040.clock_config,
            .baud_rate = 0,
        });
        if (ret2 != ConfigError.UnsupportedBaudRate)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };

        i2c_inst.apply(.{
            .clock_config = rp2040.clock_config,
            .baud_rate = 400_000,
        }) catch return .{ .fail = .{
            .msg = "Unexpected error configuring I2C",
            .context = @src(),
        } };

        // Basic write + read to read a device register
        var read_data = [_]u8{0};
        i2c_inst.write_blocking(MSA301.address, &.{MSA301.Registers.DEVICE_ID}, null) catch |err| std.debug.panic("I2C write failure: {any}", .{err});
        i2c_inst.read_blocking(MSA301.address, &read_data, null) catch |err| std.debug.panic("I2C read failure: {any}", .{err});
        if (read_data[0] != MSA301.DefaultValues.DEVICE_ID)
            return .{ .fail = .{
                .msg = "Wrong device ID",
                .context = @src(),
            } };

        // Using write_then_read to do it back-to-back with a repeated start in between
        i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301.Registers.DEVICE_ID}, &read_data, null) catch |err| std.debug.panic("I2C write_then_read failure: {any}", .{err});
        if (read_data[0] != MSA301.DefaultValues.DEVICE_ID)
            return .{ .fail = .{
                .msg = "Wrong device ID",
                .context = @src(),
            } };

        // Successive read of multiple consecutive addresses
        const MSA301_FREEFALL_DIR_REG = 0x22;
        const EXPECTED_DATA = .{ 0x9, 0x30, 0x1, 0x0 };
        var read_data2 = [4]u8{ 0, 0, 0, 0 };
        i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301_FREEFALL_DIR_REG}, &read_data2, null) catch |err| std.debug.panic("I2C write_then_read failure: {any}", .{err});
        if (!std.mem.eql(u8, &read_data2, &EXPECTED_DATA))
            return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };

        // Write + readback a register
        i2c_inst.write_blocking(MSA301.address, &.{ MSA301.Registers.OFFSETX, 0x0 }, null) catch |err| std.debug.panic("I2C write failure: {any}", .{err});
        i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301.Registers.OFFSETX}, &read_data, null) catch |err| std.debug.panic("I2C write_then_read failure: {any}", .{err});
        if (read_data[0] != 0x0)
            return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };

        i2c_inst.write_blocking(MSA301.address, &.{ MSA301.Registers.OFFSETX, 0xAA }, null) catch |err| std.debug.panic("I2C write failure: {any}", .{err});
        i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301.Registers.OFFSETX}, &read_data, null) catch |err| std.debug.panic("I2C write_then_read failure: {any}", .{err});
        if (read_data[0] != 0xAA)
            return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };

        // Write + readback multiple registers
        read_data2[0] = MSA301.Registers.OFFSETX;
        std.mem.copyForwards(u8, read_data2[1..], &.{ 0xA, 0xB, 0xC });
        i2c_inst.write_blocking(MSA301.address, &read_data2, null) catch |err| std.debug.panic("I2C write failure: {any}", .{err});
        i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301.Registers.OFFSETX}, read_data2[0..3], null) catch |err| std.debug.panic("I2C write_then_read failure: {any}", .{err});
        if (!std.mem.eql(u8, read_data2[0..3], &.{ 0xA, 0xB, 0xC }))
            return .{ .fail = .{
                .msg = "Incorrect data",
                .context = @src(),
            } };

        // Try a write + read with non repeated start
        i2c_inst.apply(.{
            .clock_config = rp2040.clock_config,
            .baud_rate = 100_000,
            .repeated_start = false,
        }) catch return .{ .fail = .{
            .msg = "Unexpected error configuring I2C",
            .context = @src(),
        } };

        i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301.Registers.DEVICE_ID}, &read_data, null) catch |err| std.debug.panic("I2C write_then_read failure: {any}", .{err});
        if (read_data[0] != MSA301.DefaultValues.DEVICE_ID)
            return .{ .fail = .{
                .msg = "Wrong device ID",
                .context = @src(),
            } };

        // Non-existent device (wrong device address) Error check:
        var ret = i2c_inst.write_blocking(@enumFromInt(0x12), &.{MSA301.Registers.DEVICE_ID}, null);
        if (ret != TransactionError.DeviceNotPresent)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        ret = i2c_inst.read_blocking(@enumFromInt(0x12), &read_data, null);
        if (ret != TransactionError.DeviceNotPresent)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        ret = i2c_inst.write_then_read_blocking(@enumFromInt(0x12), &.{MSA301.Registers.DEVICE_ID}, &read_data, null);
        if (ret != TransactionError.DeviceNotPresent)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };

        // Reserved address check
        ret = i2c_inst.write_blocking(@enumFromInt(0x2), &.{MSA301.Registers.DEVICE_ID}, null);
        if (ret != TransactionError.TargetAddressReserved)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        ret = i2c_inst.read_blocking(@enumFromInt(0x2), &read_data, null);
        if (ret != TransactionError.TargetAddressReserved)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        ret = i2c_inst.write_then_read_blocking(@enumFromInt(0x2), &.{MSA301.Registers.DEVICE_ID}, &read_data, null);
        if (ret != TransactionError.TargetAddressReserved)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };

        // Timeout checks
        ret = i2c_inst.write_blocking(MSA301.address, &.{MSA301.Registers.DEVICE_ID}, time.Duration.from_ms(0));
        if (ret != TransactionError.Timeout)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        time.sleep_ms(10); // Let the actual transaction finish
        ret = i2c_inst.read_blocking(MSA301.address, &read_data, time.Duration.from_ms(0));
        if (ret != TransactionError.Timeout)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        time.sleep_ms(10); // Let the actual transaction finish
        ret = i2c_inst.write_then_read_blocking(MSA301.address, &.{MSA301.Registers.DEVICE_ID}, &read_data, time.Duration.from_ms(0));
        if (ret != TransactionError.Timeout)
            return .{ .fail = .{
                .msg = "Incorrect error returned",
                .context = @src(),
            } };
        time.sleep_ms(10); // Let the actual transaction finish
        i2c_inst.reset();

        configure_gpio_for_i2c(sda, .deinit);
        configure_gpio_for_i2c(scl, .deinit);
    }

    return .pass;
}

pub const instance: self_test.Instance = .{
    .name = "i2c",
    .execute = execute,
};
