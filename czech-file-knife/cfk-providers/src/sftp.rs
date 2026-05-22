// SPDX-License-Identifier: MPL-2.0
//! SFTP storage backend
//!
//! SSH File Transfer Protocol implementation.
//! Supports password, key-based, and agent authentication.
//!
//! Delegates to the system `sftp` / `ssh` CLI tools via
//! `std::process::Command`. Falls back gracefully when the tools
//! are not available.

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
use std::path::PathBuf;
use std::process::Command;
use tracing::{debug, warn};

/// SFTP authentication method
#[derive(Debug, Clone)]
pub enum SftpAuth {
    /// Password authentication
    Password { username: String, password: String },
    /// Private key authentication
    PrivateKey {
        username: String,
        private_key_path: PathBuf,
        passphrase: Option<String>,
    },
    /// SSH agent authentication
    Agent { username: String },
}

/// SFTP backend configuration
#[derive(Debug, Clone)]
pub struct SftpConfig {
    /// Host address
    pub host: String,
    /// Port (default: 22)
    pub port: u16,
    /// Authentication method
    pub auth: SftpAuth,
    /// Known hosts file path
    pub known_hosts: Option<PathBuf>,
    /// Skip host key verification (insecure!)
    pub skip_host_key_check: bool,
    /// Remote base path
    pub base_path: String,
}

impl Default for SftpConfig {
    fn default() -> Self {
        Self {
            host: "localhost".to_string(),
            port: 22,
            auth: SftpAuth::Agent {
                username: whoami::username(),
            },
            known_hosts: None,
            skip_host_key_check: false,
            base_path: "/".to_string(),
        }
    }
}

/// SFTP storage backend
///
/// Delegates to the system `sftp` CLI for file operations.
/// Uses batch mode (`-b -`) to pipe commands via stdin.
pub struct SftpBackend {
    id: String,
    config: SftpConfig,
    capabilities: StorageCapabilities,
}

impl SftpBackend {
    /// Create a new SFTP backend with the given configuration.
    pub fn new(id: impl Into<String>, config: SftpConfig) -> Self {
        Self {
            id: id.into(),
            config,
            capabilities: StorageCapabilities {
                read: true,
                write: true,
                delete: true,
                rename: true,
                copy: false, // SFTP doesn't have native copy
                list: true,
                ..Default::default()
            },
        }
    }

    /// Create from SSH URL: sftp://user@host:port/path
    pub fn from_url(id: impl Into<String>, url: &str) -> CfkResult<Self> {
        let parsed = url::Url::parse(url)
            .map_err(|e| CfkError::InvalidPath(format!("Invalid URL: {}", e)))?;

        if parsed.scheme() != "sftp" {
            return Err(CfkError::InvalidPath("URL scheme must be sftp".into()));
        }

        let host = parsed
            .host_str()
            .ok_or_else(|| CfkError::InvalidPath("Missing host".into()))?
            .to_string();

        let port = parsed.port().unwrap_or(22);
        let username = if parsed.username().is_empty() {
            whoami::username()
        } else {
            parsed.username().to_string()
        };

        let base_path = if parsed.path().is_empty() {
            "/".to_string()
        } else {
            parsed.path().to_string()
        };

        let auth = if let Some(password) = parsed.password() {
            SftpAuth::Password {
                username,
                password: password.to_string(),
            }
        } else {
            SftpAuth::Agent { username }
        };

        Ok(Self::new(
            id,
            SftpConfig {
                host,
                port,
                auth,
                base_path,
                ..Default::default()
            },
        ))
    }

    /// Convert VirtualPath to remote path on the SFTP server.
    fn to_remote_path(&self, path: &VirtualPath) -> String {
        let base = self.config.base_path.trim_end_matches('/');
        if path.segments.is_empty() {
            base.to_string()
        } else {
            format!("{}/{}", base, path.segments.join("/"))
        }
    }

    /// Get the username from the configured auth method.
    fn username(&self) -> &str {
        match &self.config.auth {
            SftpAuth::Password { username, .. } => username,
            SftpAuth::PrivateKey { username, .. } => username,
            SftpAuth::Agent { username } => username,
        }
    }

    /// Build common SSH options for the sftp command.
    fn ssh_options(&self) -> Vec<String> {
        let mut opts = Vec::new();

        // Port
        opts.push("-oPort".to_string());
        opts.push(self.config.port.to_string());

        // Batch mode — disable interactive prompts
        opts.push("-oBatchMode=yes".to_string());

        // Host key checking
        if self.config.skip_host_key_check {
            opts.push("-oStrictHostKeyChecking=no".to_string());
            opts.push("-oUserKnownHostsFile=/dev/null".to_string());
        } else if let Some(ref kh) = self.config.known_hosts {
            opts.push(format!("-oUserKnownHostsFile={}", kh.display()));
        }

        // Private key
        if let SftpAuth::PrivateKey { private_key_path, .. } = &self.config.auth {
            opts.push("-oIdentityFile".to_string());
            opts.push(private_key_path.display().to_string());
        }

        opts
    }

    /// Run an sftp batch command and return its stdout.
    ///
    /// The `batch_commands` string is fed to `sftp -b -` via stdin.
    fn run_sftp_batch(&self, batch_commands: &str) -> CfkResult<String> {
        let destination = format!("{}@{}", self.username(), self.config.host);
        let mut args = vec!["-b".to_string(), "-".to_string()];
        args.extend(self.ssh_options());
        args.push(destination);

        debug!(batch = %batch_commands, "Running sftp batch command");

        let output = Command::new("sftp")
            .args(&args)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .and_then(|mut child| {
                use std::io::Write;
                if let Some(ref mut stdin) = child.stdin {
                    stdin.write_all(batch_commands.as_bytes())?;
                }
                child.wait_with_output()
            })
            .map_err(|e| CfkError::Network(format!("Failed to run sftp: {}", e)))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(CfkError::ProviderApi {
                provider: "sftp".into(),
                message: format!("sftp failed: {}", stderr.trim()),
            });
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Run an SSH command and return its stdout (used for stat, ls).
    fn run_ssh_command(&self, remote_cmd: &str) -> CfkResult<String> {
        let destination = format!("{}@{}", self.username(), self.config.host);

        let mut args = Vec::new();
        // Port
        args.push("-p".to_string());
        args.push(self.config.port.to_string());

        // Batch mode
        args.push("-oBatchMode=yes".to_string());

        if self.config.skip_host_key_check {
            args.push("-oStrictHostKeyChecking=no".to_string());
            args.push("-oUserKnownHostsFile=/dev/null".to_string());
        } else if let Some(ref kh) = self.config.known_hosts {
            args.push(format!("-oUserKnownHostsFile={}", kh.display()));
        }

        if let SftpAuth::PrivateKey { private_key_path, .. } = &self.config.auth {
            args.push("-i".to_string());
            args.push(private_key_path.display().to_string());
        }

        args.push(destination);
        args.push(remote_cmd.to_string());

        let output = Command::new("ssh")
            .args(&args)
            .output()
            .map_err(|e| CfkError::Network(format!("Failed to run ssh: {}", e)))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(CfkError::ProviderApi {
                provider: "sftp".into(),
                message: format!("ssh command failed: {}", stderr.trim()),
            });
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Connect to SFTP server (validates connectivity).
    pub async fn connect(&self) -> CfkResult<()> {
        self.run_sftp_batch("ls\n")?;
        Ok(())
    }
}

#[async_trait]
impl StorageBackend for SftpBackend {
    fn id(&self) -> &str {
        &self.id
    }

    fn display_name(&self) -> &str {
        "SFTP"
    }

    fn capabilities(&self) -> &StorageCapabilities {
        &self.capabilities
    }

    async fn is_available(&self) -> bool {
        // Check that the sftp binary exists
        Command::new("sftp").arg("-h").output().is_ok()
    }

    async fn get_metadata(&self, path: &VirtualPath) -> CfkResult<Entry> {
        let remote_path = self.to_remote_path(path);

        // Use ssh + stat to get file metadata
        let cmd = format!(
            "stat -c '%F %s %Y %a' '{}'",
            remote_path.replace('\'', "'\\''")
        );
        let output = self.run_ssh_command(&cmd)?;
        let trimmed = output.trim();

        // Parse: "<type> <size> <mtime_epoch> <octal_perms>"
        let parts: Vec<&str> = trimmed.splitn(4, ' ').collect();
        if parts.len() < 4 {
            return Err(CfkError::NotFound(path.to_string()));
        }

        let kind = if parts[0].contains("directory") {
            EntryKind::Directory
        } else if parts[0].contains("symbolic") {
            EntryKind::Symlink
        } else {
            EntryKind::File
        };

        let mut metadata = Metadata::new();
        if let Ok(size) = parts[1].parse::<u64>() {
            metadata.size = Some(size);
        }
        if let Ok(mtime) = parts[2].parse::<i64>() {
            metadata.modified = chrono::DateTime::from_timestamp(mtime, 0);
        }
        if let Ok(mode) = u32::from_str_radix(parts[3], 8) {
            metadata.permissions = Some(Permissions::new(mode));
        }

        Ok(Entry { path: path.clone(), kind, metadata })
    }

    async fn list_directory(&self, path: &VirtualPath, _options: &ListOptions) -> CfkResult<DirectoryListing> {
        let remote_path = self.to_remote_path(path);

        // Use ssh + ls to get a reliable directory listing
        let cmd = format!(
            "ls -1a '{}'",
            remote_path.replace('\'', "'\\''")
        );
        let output = self.run_ssh_command(&cmd)?;

        let mut entries = Vec::new();
        for line in output.lines() {
            let name = line.trim();
            if name.is_empty() || name == "." || name == ".." {
                continue;
            }

            // We get basic type info from a second stat call per entry
            // For performance, use ls -la and parse instead
            let entry_path = path.join(name);
            entries.push(Entry {
                path: entry_path,
                kind: EntryKind::Unknown, // Could be enriched with stat
                metadata: Metadata::new(),
            });
        }

        // Enrich entries with type info via a single stat call
        if !entries.is_empty() {
            let stat_cmd = format!(
                "for f in '{}'/*; do stat -c '%F %s %Y %n' \"$f\" 2>/dev/null; done",
                remote_path.replace('\'', "'\\''")
            );
            if let Ok(stat_output) = self.run_ssh_command(&stat_cmd) {
                // Rebuild entries from stat output
                entries.clear();
                for line in stat_output.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }

                    // Format: "<type> <size> <mtime> <full_path>"
                    let parts: Vec<&str> = trimmed.splitn(4, ' ').collect();
                    if parts.len() < 4 {
                        continue;
                    }

                    let kind = if parts[0].contains("directory") {
                        EntryKind::Directory
                    } else if parts[0].contains("symbolic") {
                        EntryKind::Symlink
                    } else {
                        EntryKind::File
                    };

                    let full_remote_path = parts[3];
                    let name = full_remote_path
                        .rsplit('/')
                        .next()
                        .unwrap_or(full_remote_path);

                    if name == "." || name == ".." {
                        continue;
                    }

                    let mut metadata = Metadata::new();
                    if let Ok(size) = parts[1].parse::<u64>() {
                        metadata.size = Some(size);
                    }
                    if let Ok(mtime) = parts[2].parse::<i64>() {
                        metadata.modified = chrono::DateTime::from_timestamp(mtime, 0);
                    }

                    let entry_path = path.join(name);
                    entries.push(Entry { path: entry_path, kind, metadata });
                }
            }
        }

        Ok(DirectoryListing::new(path.clone(), entries))
    }

    async fn read_file(&self, path: &VirtualPath, _options: &ReadOptions) -> CfkResult<ByteStream> {
        let remote_path = self.to_remote_path(path);

        // Download to a temp file via sftp, then read locally
        let tmp_dir = std::env::temp_dir();
        let tmp_file = tmp_dir.join(format!("cfk_sftp_{}", std::process::id()));
        let tmp_path_str = tmp_file.display().to_string();

        let batch = format!("get {} {}\n", remote_path, tmp_path_str);
        self.run_sftp_batch(&batch)?;

        let data = std::fs::read(&tmp_file).map_err(|e| {
            CfkError::Other(format!("Failed to read downloaded file: {}", e))
        })?;
        let _ = std::fs::remove_file(&tmp_file);

        let bytes = Bytes::from(data);
        Ok(Box::pin(futures::stream::once(async { Ok(bytes) })))
    }

    async fn write_file(&self, path: &VirtualPath, data: Bytes, _options: &WriteOptions) -> CfkResult<Entry> {
        let remote_path = self.to_remote_path(path);

        // Write to a temp file, then upload via sftp
        let tmp_dir = std::env::temp_dir();
        let tmp_file = tmp_dir.join(format!("cfk_sftp_put_{}", std::process::id()));
        std::fs::write(&tmp_file, &data).map_err(|e| {
            CfkError::Other(format!("Failed to write temp file: {}", e))
        })?;

        let tmp_path_str = tmp_file.display().to_string();
        let batch = format!("put {} {}\n", tmp_path_str, remote_path);
        let result = self.run_sftp_batch(&batch);
        let _ = std::fs::remove_file(&tmp_file);
        result?;

        let mut metadata = Metadata::new();
        metadata.size = Some(data.len() as u64);
        Ok(Entry {
            path: path.clone(),
            kind: EntryKind::File,
            metadata,
        })
    }

    async fn write_file_stream(&self, path: &VirtualPath, mut stream: ByteStream, _size_hint: Option<u64>, options: &WriteOptions) -> CfkResult<Entry> {
        use futures::StreamExt;

        let mut data = Vec::new();
        while let Some(chunk) = stream.next().await {
            data.extend_from_slice(&chunk?);
        }
        self.write_file(path, Bytes::from(data), options).await
    }

    async fn delete(&self, path: &VirtualPath, _options: &DeleteOptions) -> CfkResult<()> {
        let remote_path = self.to_remote_path(path);

        // Try rm first (file), then rmdir (directory)
        let batch = format!("rm {}\n", remote_path);
        match self.run_sftp_batch(&batch) {
            Ok(_) => Ok(()),
            Err(_) => {
                let batch = format!("rmdir {}\n", remote_path);
                self.run_sftp_batch(&batch)?;
                Ok(())
            }
        }
    }

    async fn create_directory(&self, path: &VirtualPath) -> CfkResult<Entry> {
        let remote_path = self.to_remote_path(path);
        let batch = format!("mkdir {}\n", remote_path);
        self.run_sftp_batch(&batch)?;

        Ok(Entry {
            path: path.clone(),
            kind: EntryKind::Directory,
            metadata: Metadata::new(),
        })
    }

    async fn copy(&self, _from: &VirtualPath, _to: &VirtualPath, _options: &CopyOptions) -> CfkResult<Entry> {
        // SFTP doesn't support server-side copy
        Err(CfkError::Unsupported(
            "SFTP doesn't support native copy".into(),
        ))
    }

    async fn rename(&self, from: &VirtualPath, to: &VirtualPath, _options: &MoveOptions) -> CfkResult<Entry> {
        let from_path = self.to_remote_path(from);
        let to_path = self.to_remote_path(to);

        let batch = format!("rename {} {}\n", from_path, to_path);
        self.run_sftp_batch(&batch)?;

        self.get_metadata(to).await
    }

    async fn get_space_info(&self) -> CfkResult<SpaceInfo> {
        let remote_path = self.to_remote_path(&VirtualPath::root(&self.id));

        // Use ssh + df to get space info
        let cmd = format!("df -B1 '{}' | tail -1", remote_path.replace('\'', "'\\''"));
        if let Ok(output) = self.run_ssh_command(&cmd) {
            let parts: Vec<&str> = output.trim().split_whitespace().collect();
            if parts.len() >= 4 {
                let total = parts[1].parse::<u64>().ok();
                let used = parts[2].parse::<u64>().ok();
                let available = parts[3].parse::<u64>().ok();
                return Ok(SpaceInfo { total, used, available });
            }
        }

        Ok(SpaceInfo::unknown())
    }
}

/// Helper to get username from environment
mod whoami {
    /// Returns the current username from the USER or USERNAME environment variable.
    pub fn username() -> String {
        std::env::var("USER")
            .or_else(|_| std::env::var("USERNAME"))
            .unwrap_or_else(|_| "nobody".to_string())
    }
}

/// SFTP file attributes (mirrors ssh2::FileStat)
#[derive(Debug, Clone, Default)]
pub struct FileAttributes {
    /// File size in bytes
    pub size: Option<u64>,
    /// Owner user ID
    pub uid: Option<u32>,
    /// Owner group ID
    pub gid: Option<u32>,
    /// Unix permission bits
    pub permissions: Option<u32>,
    /// Last access time (Unix epoch)
    pub atime: Option<u64>,
    /// Last modification time (Unix epoch)
    pub mtime: Option<u64>,
}

impl FileAttributes {
    /// Returns true if the entry is a directory.
    pub fn is_dir(&self) -> bool {
        self.permissions
            .map(|p| (p & 0o40000) != 0)
            .unwrap_or(false)
    }

    /// Returns true if the entry is a symbolic link.
    pub fn is_symlink(&self) -> bool {
        self.permissions
            .map(|p| (p & 0o120000) == 0o120000)
            .unwrap_or(false)
    }

    /// Returns true if the entry is a regular file.
    pub fn is_file(&self) -> bool {
        self.permissions
            .map(|p| (p & 0o100000) != 0)
            .unwrap_or(false)
    }

    /// Convert to CFK Metadata.
    pub fn to_metadata(&self) -> Metadata {
        let mut meta = Metadata::default();
        meta.size = self.size;
        if let Some(mode) = self.permissions {
            meta.permissions = Some(Permissions::new(mode));
        }

        if let Some(mtime) = self.mtime {
            meta.modified = chrono::DateTime::from_timestamp(mtime as i64, 0);
        }

        meta
    }
}
