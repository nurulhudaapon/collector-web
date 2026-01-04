//! Payloads sent both ways for HTTP APIs
//!
//! This module is used by both backend and frontend to keep them sync

pub const signin = struct {
    pub const Input = struct {
        username: []const u8,
        password: []const u8,
        referrer: []const u8,
    };

    pub const Output = struct {
        token: []const u8,
    };
};

pub const login = signin;

pub const logout = struct {
    pub const Input = struct {
        token: []const u8,
    };

    pub const Output = struct {
        // FIXME: replace with bool after https://github.com/mitchellh/zig-js/pull/5
        ok: u1,
    };
};

pub const fetch = struct {
    pub const start = struct {
        pub const Input = struct {
            name: []const u8,
        };

        pub const Output = struct {
            id: u64,
        };
    };

    pub const status = struct {
        pub const Input = struct {
            id: u64,
        };

        pub const Output = struct {
            count: u64,
            finished: bool,
            ms_elapsed: u64,
        };
    };
};
