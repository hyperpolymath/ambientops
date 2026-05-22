// SPDX-License-Identifier: MPL-2.0
//! Raw C bindings to libfuse3 via @cImport

pub usingnamespace @cImport({
    @cDefine("FUSE_USE_VERSION", "35");
    @cInclude("fuse3/fuse.h");
    @cInclude("fuse3/fuse_lowlevel.h");
});
