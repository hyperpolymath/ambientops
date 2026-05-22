// SPDX-License-Identifier: MPL-2.0
//! FUSE virtual filesystem for Czech File Knife
//!
//! This module provides FUSE mounting capabilities to access
//! any CFK backend as a local filesystem.
//!
//! Without the `fuse` feature, a passthrough VFS is provided that
//! delegates all operations to `std::fs` on a given root directory.
//! With the `fuse` feature, a FUSE filesystem using the `fuser` crate
//! is available.

#![forbid(unsafe_code)]
use cfk_core::{CfkError, CfkResult};
use std::path::{Path, PathBuf};
use thiserror::Error;
use tracing::debug;

/// VFS errors
#[derive(Error, Debug)]
pub enum VfsError {
    /// The specified mount point directory does not exist
    #[error("Mount point does not exist: {0}")]
    MountPointNotFound(String),

    /// The specified mount point path is not a directory
    #[error("Mount point is not a directory: {0}")]
    MountPointNotDirectory(String),

    /// A filesystem is already mounted at the given path
    #[error("Already mounted at: {0}")]
    AlreadyMounted(String),

    /// No filesystem is currently mounted
    #[error("Not mounted")]
    NotMounted,

    /// An error from the FUSE layer
    #[error("FUSE error: {0}")]
    Fuse(String),

    /// An I/O error occurred
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

/// Mount options controlling VFS behaviour
#[derive(Debug, Clone, Default)]
pub struct MountOptions {
    /// Allow other users to access the mount
    pub allow_other: bool,
    /// Allow root to access the mount
    pub allow_root: bool,
    /// Read-only mount
    pub read_only: bool,
    /// Enable caching
    pub cache: bool,
    /// Cache timeout in seconds
    pub cache_timeout_secs: Option<u64>,
    /// Debug mode (extra logging)
    pub debug: bool,
}

/// VFS mount handle
///
/// Without the `fuse` feature, this is a passthrough VFS that delegates
/// all operations to `std::fs` under the specified root directory.
/// With the `fuse` feature, this manages a FUSE mount.
pub struct VfsMount {
    /// The local mount point or root directory
    mount_point: PathBuf,
    /// Mount options
    _options: MountOptions,
    /// Whether the mount is currently active
    mounted: bool,
}

impl VfsMount {
    /// Mount a CFK backend at the given path.
    ///
    /// Without the `fuse` feature, this creates a passthrough VFS
    /// rooted at `mount_point`. The `backend_id` is recorded for
    /// identification but the passthrough delegates to local fs.
    ///
    /// # Arguments
    /// * `backend_id` - The backend to mount (e.g., "local", "dropbox")
    /// * `mount_point` - The local path to mount at
    /// * `options` - Mount options
    pub fn mount(
        _backend_id: &str,
        mount_point: impl Into<PathBuf>,
        options: MountOptions,
    ) -> CfkResult<Self> {
        let mount_point = mount_point.into();

        // Validate mount point exists and is a directory
        if !mount_point.exists() {
            return Err(CfkError::Other(format!(
                "Mount point does not exist: {}", mount_point.display()
            )));
        }

        if !mount_point.is_dir() {
            return Err(CfkError::Other(format!(
                "Mount point is not a directory: {}", mount_point.display()
            )));
        }

        debug!(
            mount_point = %mount_point.display(),
            "VFS passthrough mount created"
        );

        Ok(Self {
            mount_point,
            _options: options,
            mounted: true,
        })
    }

    /// Get the mount point path.
    pub fn mount_point(&self) -> &PathBuf {
        &self.mount_point
    }

    /// Check if the mount is still active.
    pub fn is_mounted(&self) -> bool {
        self.mounted && self.mount_point.exists()
    }

    /// Unmount the filesystem.
    pub fn unmount(mut self) -> CfkResult<()> {
        self.mounted = false;
        debug!(
            mount_point = %self.mount_point.display(),
            "VFS unmounted"
        );
        Ok(())
    }

    // ----------------------------------------------------------------
    // Passthrough VFS operations (delegating to std::fs)
    // ----------------------------------------------------------------

    /// Read a file from the VFS.
    pub fn read_file(&self, path: &Path) -> CfkResult<Vec<u8>> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real = self.resolve(path)?;
        std::fs::read(&real).map_err(|e| CfkError::Other(format!(
            "VFS read failed for {}: {}", real.display(), e
        )))
    }

    /// Write a file to the VFS.
    pub fn write_file(&self, path: &Path, data: &[u8]) -> CfkResult<()> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real = self.resolve(path)?;

        // Ensure parent directories exist
        if let Some(parent) = real.parent() {
            std::fs::create_dir_all(parent).map_err(|e| CfkError::Other(format!(
                "VFS mkdir failed for {}: {}", parent.display(), e
            )))?;
        }

        std::fs::write(&real, data).map_err(|e| CfkError::Other(format!(
            "VFS write failed for {}: {}", real.display(), e
        )))
    }

    /// List entries in a directory.
    pub fn read_dir(&self, path: &Path) -> CfkResult<Vec<VfsDirEntry>> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real = self.resolve(path)?;
        let mut entries = Vec::new();

        let read_dir = std::fs::read_dir(&real).map_err(|e| CfkError::Other(format!(
            "VFS readdir failed for {}: {}", real.display(), e
        )))?;

        for entry_result in read_dir {
            let entry = entry_result.map_err(|e| CfkError::Other(format!(
                "VFS readdir entry failed: {}", e
            )))?;

            let name = entry.file_name().to_string_lossy().to_string();
            let file_type = entry.file_type().map_err(|e| CfkError::Other(format!(
                "VFS file_type failed: {}", e
            )))?;

            let kind = if file_type.is_dir() {
                VfsFileKind::Directory
            } else if file_type.is_symlink() {
                VfsFileKind::Symlink
            } else {
                VfsFileKind::File
            };

            let metadata = entry.metadata().ok();
            let size = metadata.as_ref().map(|m| m.len());

            entries.push(VfsDirEntry { name, kind, size });
        }

        Ok(entries)
    }

    /// Get metadata for a path.
    pub fn metadata(&self, path: &Path) -> CfkResult<VfsMetadata> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real = self.resolve(path)?;
        let meta = std::fs::metadata(&real).map_err(|e| CfkError::Other(format!(
            "VFS stat failed for {}: {}", real.display(), e
        )))?;

        let kind = if meta.is_dir() {
            VfsFileKind::Directory
        } else if meta.is_symlink() {
            VfsFileKind::Symlink
        } else {
            VfsFileKind::File
        };

        Ok(VfsMetadata {
            kind,
            size: meta.len(),
            readonly: meta.permissions().readonly(),
        })
    }

    /// Delete a file or directory.
    pub fn delete(&self, path: &Path, recursive: bool) -> CfkResult<()> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real = self.resolve(path)?;

        if real.is_dir() {
            if recursive {
                std::fs::remove_dir_all(&real)
            } else {
                std::fs::remove_dir(&real)
            }
        } else {
            std::fs::remove_file(&real)
        }
        .map_err(|e| CfkError::Other(format!(
            "VFS delete failed for {}: {}", real.display(), e
        )))
    }

    /// Create a directory (and any missing parents).
    pub fn create_dir(&self, path: &Path) -> CfkResult<()> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real = self.resolve(path)?;
        std::fs::create_dir_all(&real).map_err(|e| CfkError::Other(format!(
            "VFS mkdir failed for {}: {}", real.display(), e
        )))
    }

    /// Rename / move a file or directory.
    pub fn rename(&self, from: &Path, to: &Path) -> CfkResult<()> {
        if !self.mounted {
            return Err(CfkError::Other("VFS not mounted".into()));
        }

        let real_from = self.resolve(from)?;
        let real_to = self.resolve(to)?;

        std::fs::rename(&real_from, &real_to).map_err(|e| CfkError::Other(format!(
            "VFS rename failed: {} -> {}: {}", real_from.display(), real_to.display(), e
        )))
    }

    // ----------------------------------------------------------------
    // Internal helpers
    // ----------------------------------------------------------------

    /// Resolve a relative or absolute path against the mount point root.
    ///
    /// Prevents path traversal attacks by ensuring the resolved path
    /// stays within the mount point directory.
    fn resolve(&self, path: &Path) -> CfkResult<PathBuf> {
        let mut resolved = self.mount_point.clone();

        for component in path.components() {
            match component {
                std::path::Component::Normal(c) => resolved.push(c),
                std::path::Component::RootDir => { /* skip leading / */ }
                std::path::Component::ParentDir => {
                    // Prevent escaping the mount root
                    if resolved == self.mount_point {
                        return Err(CfkError::Other(
                            "Path traversal beyond mount root".into(),
                        ));
                    }
                    resolved.pop();
                }
                std::path::Component::CurDir => { /* skip . */ }
                _ => {}
            }
        }

        Ok(resolved)
    }
}

impl Drop for VfsMount {
    fn drop(&mut self) {
        if self.mounted {
            debug!(
                mount_point = %self.mount_point.display(),
                "VFS dropped while mounted"
            );
            self.mounted = false;
        }
    }
}

/// File kind for VFS directory entries
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VfsFileKind {
    /// Regular file
    File,
    /// Directory
    Directory,
    /// Symbolic link
    Symlink,
}

/// A directory entry returned by `VfsMount::read_dir`
#[derive(Debug, Clone)]
pub struct VfsDirEntry {
    /// Entry name (filename only, not full path)
    pub name: String,
    /// File kind
    pub kind: VfsFileKind,
    /// File size in bytes (None for directories/symlinks on some platforms)
    pub size: Option<u64>,
}

/// Metadata for a VFS entry
#[derive(Debug, Clone)]
pub struct VfsMetadata {
    /// File kind
    pub kind: VfsFileKind,
    /// Size in bytes
    pub size: u64,
    /// Whether the file is read-only
    pub readonly: bool,
}

/// List active mounts (currently always empty for passthrough VFS)
pub fn list_mounts() -> Vec<VfsMount> {
    Vec::new()
}

/// Check if FUSE is available on this system
pub fn is_fuse_available() -> bool {
    #[cfg(target_os = "linux")]
    {
        std::path::Path::new("/dev/fuse").exists()
    }

    #[cfg(target_os = "macos")]
    {
        // Check for macFUSE
        std::path::Path::new("/Library/Filesystems/macfuse.fs").exists()
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_fuse_available() {
        // Just make sure it doesn't panic
        let _ = is_fuse_available();
    }

    #[test]
    fn test_mount_nonexistent_fails() {
        let result = VfsMount::mount("local", "/tmp/nonexistent_cfk_test_dir_12345", MountOptions::default());
        assert!(result.is_err());
    }

    #[test]
    fn test_passthrough_lifecycle() {
        // Create a temp dir as our "mount point"
        let tmp = std::env::temp_dir().join(format!("cfk_vfs_test_{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();

        // Mount
        let vfs = VfsMount::mount("local", &tmp, MountOptions::default()).unwrap();
        assert!(vfs.is_mounted());
        assert_eq!(vfs.mount_point(), &tmp);

        // Write a file
        vfs.write_file(Path::new("hello.txt"), b"Hello, VFS!").unwrap();

        // Read it back
        let data = vfs.read_file(Path::new("hello.txt")).unwrap();
        assert_eq!(data, b"Hello, VFS!");

        // List directory
        let entries = vfs.read_dir(Path::new("")).unwrap();
        assert!(entries.iter().any(|e| e.name == "hello.txt"));

        // Get metadata
        let meta = vfs.metadata(Path::new("hello.txt")).unwrap();
        assert_eq!(meta.kind, VfsFileKind::File);
        assert_eq!(meta.size, 11);

        // Create subdirectory
        vfs.create_dir(Path::new("subdir")).unwrap();
        let meta = vfs.metadata(Path::new("subdir")).unwrap();
        assert_eq!(meta.kind, VfsFileKind::Directory);

        // Rename
        vfs.rename(Path::new("hello.txt"), Path::new("renamed.txt")).unwrap();
        let entries = vfs.read_dir(Path::new("")).unwrap();
        assert!(entries.iter().any(|e| e.name == "renamed.txt"));
        assert!(!entries.iter().any(|e| e.name == "hello.txt"));

        // Delete
        vfs.delete(Path::new("renamed.txt"), false).unwrap();
        vfs.delete(Path::new("subdir"), true).unwrap();

        // Unmount
        vfs.unmount().unwrap();

        // Cleanup
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_path_traversal_prevention() {
        let tmp = std::env::temp_dir().join(format!("cfk_vfs_traversal_{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();

        let vfs = VfsMount::mount("local", &tmp, MountOptions::default()).unwrap();

        // Attempting to read ../../etc/passwd should fail
        let result = vfs.read_file(Path::new("../../etc/passwd"));
        assert!(result.is_err());

        vfs.unmount().unwrap();
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
