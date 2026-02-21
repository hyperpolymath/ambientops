// SPDX-License-Identifier: AGPL-3.0-or-later
//! Raw C bindings to libfuse3 via @cImport

pub usingnamespace @cImport({
    @cDefine("FUSE_USE_VERSION", "35");
    @cInclude("fuse3/fuse.h");
    @cInclude("fuse3/fuse_lowlevel.h");
});
