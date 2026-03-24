// SPDX-License-Identifier: PMPL-1.0-or-later
//! NFS storage backend
//!
//! Network File System client implementation.
//! Supports NFSv3 and NFSv4 protocols.
//!
//! This implementation works by mounting the NFS export to a temporary
//! local directory via `mount -t nfs`, then performing standard
//! filesystem operations on the mount point. Requires the `nfs-utils`
//! package (or equivalent) and appropriate privileges for mount.

use async_trait::async_trait;
use bytes::Bytes;
use cfk_core::{
    backend::{ByteStream, SpaceInfo, StorageBackend, StorageCapabilities},
    entry::{DirectoryListing, Entry, EntryKind},
    error::{CfkError, CfkResult},
    metadata::{Metadata, Permissions},
    operations::*,
    VirtualPath,
};
use std::path::{Path, PathBuf};
use std::process::Command;
use tokio::fs;
use tokio::io::AsyncReadExt;
use tracing::{debug, warn};

/// NFS version
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NfsVersion {
    /// NFSv3
    V3,
    /// NFSv4
    V4,
    /// NFSv4.1
    V41,
}

impl Default for NfsVersion {
    fn default() -> Self {
        Self::V4
    }
}

/// NFS authentication flavor
#[derive(Debug, Clone)]
pub enum NfsAuth {
    /// AUTH_SYS (Unix authentication)
    Sys { uid: u32, gid: u32, gids: Vec<u32> },
    /// AUTH_NONE
    None,
    /// RPCSEC_GSS (Kerberos)
    Gss { principal: String },
}

impl Default for NfsAuth {
    fn default() -> Self {
        Self::Sys {
            uid: 65534, // nobody
            gid: 65534,
            gids: vec![],
        }
    }
}

/// NFS backend configuration
#[derive(Debug, Clone)]
pub struct NfsConfig {
    /// Server hostname or IP
    pub server: String,
    /// Export path
    pub export: String,
    /// NFS version
    pub version: NfsVersion,
    /// Authentication
    pub auth: NfsAuth,
    /// Read size (NFSv3: 65536, NFSv4: 1MB)
    pub rsize: u32,
    /// Write size
    pub wsize: u32,
    /// Use TCP (vs UDP for NFSv3)
    pub tcp: bool,
    /// Port (0 = use portmapper/rpcbind)
    pub port: u16,
}

impl Default for NfsConfig {
    fn default() -> Self {
        Self {
            server: "localhost".to_string(),
            export: "/".to_string(),
            version: NfsVersion::V4,
            auth: NfsAuth::default(),
            rsize: 1048576,  // 1MB
            wsize: 1048576,
            tcp: true,
            port: 2049,
        }
    }
}

/// NFS file handle
#[derive(Debug, Clone, Default)]
struct NfsFileHandle {
    data: Vec<u8>,
}

/// NFS storage backend
///
/// Mounts the NFS export to a temporary directory and performs
/// standard filesystem operations on the mount point. The mount
/// is created lazily on first use and cleaned up on drop.
pub struct NfsBackend {
    id: String,
    config: NfsConfig,
    capabilities: StorageCapabilities,
    /// Local mount point where the NFS export is mounted
    mount_point: Option<PathBuf>,
}

impl NfsBackend {
    /// Create a new NFS backend with the given configuration.
    pub fn new(id: impl Into<String>, config: NfsConfig) -> Self {
        Self {
            id: id.into(),
            config,
            capabilities: StorageCapabilities {
                read: true,
                write: true,
                delete: true,
                rename: true,
                copy: false,
                list: true,
                ..Default::default()
            },
            mount_point: None,
        }
    }

    /// Create from NFS URL: nfs://server/export
    pub fn from_url(id: impl Into<String>, url: &str) -> CfkResult<Self> {
        let parsed = url::Url::parse(url)
            .map_err(|e| CfkError::InvalidPath(format!("Invalid URL: {}", e)))?;

        if parsed.scheme() != "nfs" {
            return Err(CfkError::InvalidPath("URL scheme must be nfs".into()));
        }

        let server = parsed
            .host_str()
            .ok_or_else(|| CfkError::InvalidPath("Missing server".into()))?
            .to_string();

        let export = parsed.path().to_string();
        let port = parsed.port().unwrap_or(2049);

        Ok(Self::new(
            id,
            NfsConfig {
                server,
                export,
                port,
                ..Default::default()
            },
        ))
    }

    /// Mount the NFS export to a temporary local directory.
    ///
    /// Creates a temp directory under `/tmp/cfk_nfs_<id>_<pid>` and
    /// runs `mount -t nfs` to mount the export there.
    pub async fn mount(&mut self) -> CfkResult<()> {
        if self.mount_point.is_some() {
            return Ok(()); // Already mounted
        }

        let mount_dir = std::env::temp_dir().join(format!(
            "cfk_nfs_{}_{}", self.id, std::process::id()
        ));

        // Create mount point directory
        std::fs::create_dir_all(&mount_dir).map_err(|e| {
            CfkError::Other(format!("Failed to create mount point: {}", e))
        })?;

        self.mount_system(&mount_dir)?;
        self.mount_point = Some(mount_dir);
        Ok(())
    }

    /// Unmount the NFS export and clean up the temporary directory.
    pub async fn unmount(&mut self) -> CfkResult<()> {
        if let Some(ref mp) = self.mount_point {
            self.unmount_system(mp)?;
            let _ = std::fs::remove_dir(mp);
            self.mount_point = None;
        }
        Ok(())
    }

    /// Ensure the export is mounted, mounting lazily if needed.
    async fn ensure_mounted(&mut self) -> CfkResult<&Path> {
        if self.mount_point.is_none() {
            self.mount().await?;
        }
        Ok(self.mount_point.as_ref().unwrap().as_path())
    }

    /// Get the current mount point, returning an error if not mounted.
    fn get_mount_point(&self) -> CfkResult<&Path> {
        self.mount_point.as_deref().ok_or_else(|| {
            CfkError::ProviderApi {
                provider: "nfs".into(),
                message: "NFS export is not mounted. Call mount() first.".into(),
            }
        })
    }

    /// Convert a VirtualPath to the real local path on the mount point.
    fn to_real_path(&self, path: &VirtualPath) -> CfkResult<PathBuf> {
        let mp = self.get_mount_point()?;
        let mut real = mp.to_path_buf();
        for seg in &path.segments {
            real.push(seg);
        }
        Ok(real)
    }

    /// Build an Entry from a local path on the mount point.
    async fn entry_from_path(&self, real: &Path, vpath: &VirtualPath) -> CfkResult<Entry> {
        let meta = fs::metadata(real).await?;
        let kind = if meta.is_dir() {
            EntryKind::Directory
        } else if meta.is_file() {
            EntryKind::File
        } else if meta.is_symlink() {
            EntryKind::Symlink
        } else {
            EntryKind::Unknown
        };

        let mut metadata = Metadata::new();
        metadata.size = Some(meta.len());

        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            metadata.permissions = Some(Permissions::new(meta.mode()));
        }

        if let Ok(modified) = meta.modified() {
            metadata.modified = Some(modified.into());
        }
        if let Ok(created) = meta.created() {
            metadata.created = Some(created.into());
        }

        Ok(Entry { path: vpath.clone(), kind, metadata })
    }

    /// Convert VirtualPath to NFS path components
    fn to_path_components(&self, path: &VirtualPath) -> Vec<String> {
        path.segments.clone()
    }
}

#[async_trait]
impl StorageBackend for NfsBackend {
    fn id(&self) -> &str {
        &self.id
    }

    fn display_name(&self) -> &str {
        match self.config.version {
            NfsVersion::V3 => "NFSv3",
            NfsVersion::V4 => "NFSv4",
            NfsVersion::V41 => "NFSv4.1",
        }
    }

    fn capabilities(&self) -> &StorageCapabilities {
        &self.capabilities
    }

    async fn is_available(&self) -> bool {
        self.mount_point.as_ref().map_or(false, |mp| mp.exists())
    }

    async fn get_metadata(&self, path: &VirtualPath) -> CfkResult<Entry> {
        let real = self.to_real_path(path)?;
        if !real.exists() {
            return Err(CfkError::NotFound(path.to_string()));
        }
        self.entry_from_path(&real, path).await
    }

    async fn list_directory(&self, path: &VirtualPath, _options: &ListOptions) -> CfkResult<DirectoryListing> {
        let real = self.to_real_path(path)?;
        if !real.is_dir() {
            return Err(CfkError::NotADirectory(path.to_string()));
        }

        let mut entries = Vec::new();
        let mut read_dir = fs::read_dir(&real).await?;

        while let Some(dir_entry) = read_dir.next_entry().await? {
            let entry_path = dir_entry.path();
            let name = dir_entry.file_name().to_string_lossy().to_string();
            let vpath = path.join(&name);
            if let Ok(entry) = self.entry_from_path(&entry_path, &vpath).await {
                entries.push(entry);
            }
        }

        Ok(DirectoryListing::new(path.clone(), entries))
    }

    async fn read_file(&self, path: &VirtualPath, options: &ReadOptions) -> CfkResult<ByteStream> {
        let real = self.to_real_path(path)?;
        if !real.is_file() {
            return Err(CfkError::NotAFile(path.to_string()));
        }

        let mut file = fs::File::open(&real).await?;
        let mut buffer = Vec::new();

        if let Some((start, end)) = options.range {
            use tokio::io::AsyncSeekExt;
            file.seek(std::io::SeekFrom::Start(start)).await?;
            let len = (end - start) as usize;
            buffer.resize(len, 0);
            file.read_exact(&mut buffer).await?;
        } else {
            file.read_to_end(&mut buffer).await?;
        }

        let bytes = Bytes::from(buffer);
        Ok(Box::pin(futures::stream::once(async { Ok(bytes) })))
    }

    async fn write_file(&self, path: &VirtualPath, data: Bytes, options: &WriteOptions) -> CfkResult<Entry> {
        let real = self.to_real_path(path)?;

        if real.exists() && !options.overwrite {
            return Err(CfkError::AlreadyExists(path.to_string()));
        }

        if options.create_parents {
            if let Some(parent) = real.parent() {
                fs::create_dir_all(parent).await?;
            }
        }

        fs::write(&real, &data).await?;
        self.get_metadata(path).await
    }

    async fn write_file_stream(&self, path: &VirtualPath, mut stream: ByteStream, _size_hint: Option<u64>, options: &WriteOptions) -> CfkResult<Entry> {
        use futures::StreamExt;

        let mut data = Vec::new();
        while let Some(chunk) = stream.next().await {
            data.extend_from_slice(&chunk?);
        }
        self.write_file(path, Bytes::from(data), options).await
    }

    async fn delete(&self, path: &VirtualPath, options: &DeleteOptions) -> CfkResult<()> {
        let real = self.to_real_path(path)?;

        if !real.exists() {
            if options.force {
                return Ok(());
            }
            return Err(CfkError::NotFound(path.to_string()));
        }

        if real.is_dir() {
            if options.recursive {
                fs::remove_dir_all(&real).await?;
            } else {
                fs::remove_dir(&real).await?;
            }
        } else {
            fs::remove_file(&real).await?;
        }
        Ok(())
    }

    async fn create_directory(&self, path: &VirtualPath) -> CfkResult<Entry> {
        let real = self.to_real_path(path)?;
        fs::create_dir_all(&real).await?;
        self.get_metadata(path).await
    }

    async fn copy(&self, _from: &VirtualPath, _to: &VirtualPath, _options: &CopyOptions) -> CfkResult<Entry> {
        // NFS doesn't have native copy (until NFSv4.2 COPY operation)
        Err(CfkError::Unsupported("NFS doesn't support native copy".into()))
    }

    async fn rename(&self, from: &VirtualPath, to: &VirtualPath, options: &MoveOptions) -> CfkResult<Entry> {
        let src_real = self.to_real_path(from)?;
        let dst_real = self.to_real_path(to)?;

        if !src_real.exists() {
            return Err(CfkError::NotFound(from.to_string()));
        }
        if dst_real.exists() && !options.overwrite {
            return Err(CfkError::AlreadyExists(to.to_string()));
        }

        fs::rename(&src_real, &dst_real).await?;
        self.get_metadata(to).await
    }

    async fn get_space_info(&self) -> CfkResult<SpaceInfo> {
        #[cfg(unix)]
        {
            if let Some(ref mp) = self.mount_point {
                use std::ffi::CString;
                use std::mem::MaybeUninit;

                let path_cstr = CString::new(mp.to_string_lossy().as_bytes())
                    .map_err(|_| CfkError::InvalidPath(mp.display().to_string()))?;

                let mut stat: MaybeUninit<libc::statvfs> = MaybeUninit::uninit();
                let result = unsafe { libc::statvfs(path_cstr.as_ptr(), stat.as_mut_ptr()) };

                if result == 0 {
                    let stat = unsafe { stat.assume_init() };
                    let block_size = stat.f_frsize as u64;
                    let total = stat.f_blocks as u64 * block_size;
                    let available = stat.f_bavail as u64 * block_size;
                    let free = stat.f_bfree as u64 * block_size;
                    let used = total - free;

                    return Ok(SpaceInfo {
                        total: Some(total),
                        used: Some(used),
                        available: Some(available),
                    });
                }
            }
        }

        Ok(SpaceInfo::unknown())
    }
}

impl Drop for NfsBackend {
    fn drop(&mut self) {
        // Best-effort unmount on drop
        if let Some(ref mp) = self.mount_point {
            let _ = self.unmount_system(mp);
            let _ = std::fs::remove_dir(mp);
        }
    }
}

/// NFS file types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NfsFileType {
    /// Regular file
    Regular = 1,
    /// Directory
    Directory = 2,
    /// Block device
    BlockDevice = 3,
    /// Character device
    CharDevice = 4,
    /// Symbolic link
    Symlink = 5,
    /// Socket
    Socket = 6,
    /// Named pipe (FIFO)
    Fifo = 7,
}

/// NFS file attributes (fattr3/fattr4)
#[derive(Debug, Clone, Default)]
pub struct NfsAttributes {
    /// File type (see NfsFileType)
    pub file_type: u32,
    /// Unix permission mode
    pub mode: u32,
    /// Number of hard links
    pub nlink: u32,
    /// Owner user ID
    pub uid: u32,
    /// Owner group ID
    pub gid: u32,
    /// File size in bytes
    pub size: u64,
    /// Space used on disk
    pub used: u64,
    /// Filesystem ID
    pub fsid: u64,
    /// File ID (inode)
    pub fileid: u64,
    /// Access time seconds
    pub atime_sec: u32,
    /// Access time nanoseconds
    pub atime_nsec: u32,
    /// Modification time seconds
    pub mtime_sec: u32,
    /// Modification time nanoseconds
    pub mtime_nsec: u32,
    /// Change time seconds
    pub ctime_sec: u32,
    /// Change time nanoseconds
    pub ctime_nsec: u32,
}

impl NfsAttributes {
    /// Convert NFS attributes to a CFK Entry.
    pub fn to_entry(&self, backend_id: &str, path: &str) -> Entry {
        let kind = match self.file_type {
            2 => EntryKind::Directory,
            5 => EntryKind::Symlink,
            _ => EntryKind::File,
        };

        let mut metadata = Metadata::default();
        metadata.size = Some(self.size);
        metadata.permissions = Some(Permissions::new(self.mode));

        if self.mtime_sec > 0 {
            metadata.modified = chrono::DateTime::from_timestamp(
                self.mtime_sec as i64,
                self.mtime_nsec,
            );
        }

        Entry {
            path: VirtualPath::new(backend_id, path),
            kind,
            metadata,
        }
    }
}

/// Helper function to use system NFS mount
impl NfsBackend {
    /// Mount using system mount command (requires root or fuse-nfs)
    pub fn mount_system(&self, mount_point: &PathBuf) -> CfkResult<()> {
        let source = format!("{}:{}", self.config.server, self.config.export);
        let version = match self.config.version {
            NfsVersion::V3 => "3",
            NfsVersion::V4 => "4",
            NfsVersion::V41 => "4.1",
        };

        let status = Command::new("mount")
            .args([
                "-t", "nfs",
                "-o", &format!("vers={}", version),
                &source,
                mount_point.to_str().unwrap_or("/mnt"),
            ])
            .status()
            .map_err(|e| CfkError::Network(format!("Failed to run mount: {}", e)))?;

        if !status.success() {
            return Err(CfkError::ProviderApi {
                provider: "nfs".into(),
                message: "mount command failed".into(),
            });
        }

        Ok(())
    }

    /// Unmount system mount
    pub fn unmount_system(&self, mount_point: &PathBuf) -> CfkResult<()> {
        let status = Command::new("umount")
            .arg(mount_point.to_str().unwrap_or("/mnt"))
            .status()
            .map_err(|e| CfkError::Network(format!("Failed to run umount: {}", e)))?;

        if !status.success() {
            return Err(CfkError::ProviderApi {
                provider: "nfs".into(),
                message: "umount command failed".into(),
            });
        }

        Ok(())
    }
}
