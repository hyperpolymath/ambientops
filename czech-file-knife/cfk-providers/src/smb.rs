// SPDX-License-Identifier: MPL-2.0
//! SMB/CIFS storage backend
//!
//! Server Message Block / Common Internet File System protocol.
//! Compatible with Windows shares, Samba, and macOS file sharing.
//!
//! This implementation delegates to the system `smbclient` CLI tool
//! via `std::process::Command`. Falls back gracefully if smbclient
//! is not installed.

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

/// SMB protocol version
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SmbVersion {
    /// SMB 1.0 (legacy, insecure)
    Smb1,
    /// SMB 2.0
    Smb2,
    /// SMB 2.1
    Smb21,
    /// SMB 3.0
    Smb3,
    /// SMB 3.0.2
    Smb302,
    /// SMB 3.1.1
    Smb311,
}

impl Default for SmbVersion {
    fn default() -> Self {
        Self::Smb3 // Secure default
    }
}

/// SMB authentication
#[derive(Debug, Clone)]
pub enum SmbAuth {
    /// Anonymous/Guest access
    Anonymous,
    /// NTLM authentication
    Ntlm { username: String, password: String, domain: Option<String> },
    /// Kerberos authentication
    Kerberos { principal: String },
}

impl Default for SmbAuth {
    fn default() -> Self {
        Self::Anonymous
    }
}

/// SMB backend configuration
#[derive(Debug, Clone)]
pub struct SmbConfig {
    /// Server hostname or IP
    pub server: String,
    /// Share name
    pub share: String,
    /// SMB protocol version
    pub version: SmbVersion,
    /// Authentication
    pub auth: SmbAuth,
    /// Port (default: 445, legacy: 139)
    pub port: u16,
    /// Encrypt traffic (SMB 3.0+)
    pub encryption: bool,
    /// Sign messages
    pub signing: bool,
}

impl Default for SmbConfig {
    fn default() -> Self {
        Self {
            server: "localhost".to_string(),
            share: "share".to_string(),
            version: SmbVersion::default(),
            auth: SmbAuth::default(),
            port: 445,
            encryption: true,
            signing: true,
        }
    }
}

/// SMB tree connection ID
#[derive(Debug, Clone, Copy, Default)]
struct TreeId(u32);

/// SMB session ID
#[derive(Debug, Clone, Copy, Default)]
struct SessionId(u64);

/// SMB file ID
#[derive(Debug, Clone, Copy, Default)]
struct FileId {
    persistent: u64,
    volatile: u64,
}

/// SMB storage backend
///
/// Delegates to system `smbclient` CLI for all file operations.
/// Falls back gracefully when smbclient is unavailable.
pub struct SmbBackend {
    id: String,
    config: SmbConfig,
    capabilities: StorageCapabilities,
    session: Option<SessionId>,
    tree_id: Option<TreeId>,
}

impl SmbBackend {
    /// Create a new SMB backend instance with the given configuration.
    pub fn new(id: impl Into<String>, config: SmbConfig) -> Self {
        let mut caps = StorageCapabilities {
            read: true,
            write: true,
            delete: true,
            rename: true,
            copy: true, // SMB2+ has server-side copy
            list: true,
            search: true, // SMB has FIND
            ..Default::default()
        };

        // Adjust capabilities based on version
        if config.version == SmbVersion::Smb1 {
            caps.copy = false; // SMB1 doesn't have server-side copy
        }

        Self {
            id: id.into(),
            config,
            capabilities: caps,
            session: None,
            tree_id: None,
        }
    }

    /// Create from SMB URL: smb://user:pass@server/share
    pub fn from_url(id: impl Into<String>, url: &str) -> CfkResult<Self> {
        let parsed = url::Url::parse(url)
            .map_err(|e| CfkError::InvalidPath(format!("Invalid URL: {}", e)))?;

        if parsed.scheme() != "smb" {
            return Err(CfkError::InvalidPath("URL scheme must be smb".into()));
        }

        let server = parsed
            .host_str()
            .ok_or_else(|| CfkError::InvalidPath("Missing server".into()))?
            .to_string();

        let share = parsed
            .path()
            .trim_start_matches('/')
            .split('/')
            .next()
            .unwrap_or("share")
            .to_string();

        let port = parsed.port().unwrap_or(445);

        let auth = if !parsed.username().is_empty() {
            SmbAuth::Ntlm {
                username: parsed.username().to_string(),
                password: parsed.password().unwrap_or("").to_string(),
                domain: None,
            }
        } else {
            SmbAuth::Anonymous
        };

        Ok(Self::new(
            id,
            SmbConfig {
                server,
                share,
                port,
                auth,
                ..Default::default()
            },
        ))
    }

    /// Check whether the `smbclient` binary is available on the system PATH.
    fn smbclient_available() -> bool {
        Command::new("smbclient")
            .arg("--version")
            .output()
            .is_ok()
    }

    /// Build common smbclient authentication arguments from the backend configuration.
    fn auth_args(&self) -> Vec<String> {
        match &self.config.auth {
            SmbAuth::Anonymous => vec!["-N".to_string()],
            SmbAuth::Ntlm { username, password, domain } => {
                let mut args = vec![
                    "-U".to_string(),
                    if let Some(dom) = domain {
                        format!("{}\\{}%{}", dom, username, password)
                    } else {
                        format!("{}%{}", username, password)
                    },
                ];
                args
            }
            SmbAuth::Kerberos { .. } => vec!["-k".to_string()],
        }
    }

    /// Build the smbclient service string (e.g. `//server/share`).
    fn service_string(&self) -> String {
        format!("//{}/{}", self.config.server, self.config.share)
    }

    /// Build the SMB protocol version flag for smbclient.
    fn max_protocol_arg(&self) -> Vec<String> {
        let proto = match self.config.version {
            SmbVersion::Smb1 => "NT1",
            SmbVersion::Smb2 => "SMB2",
            SmbVersion::Smb21 => "SMB2",
            SmbVersion::Smb3 | SmbVersion::Smb302 | SmbVersion::Smb311 => "SMB3",
        };
        vec!["-m".to_string(), proto.to_string()]
    }

    /// Run an smbclient command with the given `-c` directive and return stdout.
    fn run_smbclient_command(&self, smb_command: &str) -> CfkResult<String> {
        if !Self::smbclient_available() {
            return Err(CfkError::Unsupported(
                "smbclient is not installed. Install samba-client to use the SMB backend.".into(),
            ));
        }

        let mut args = vec![self.service_string()];
        args.extend(self.auth_args());
        args.extend(self.max_protocol_arg());
        args.push("-p".to_string());
        args.push(self.config.port.to_string());
        args.push("-c".to_string());
        args.push(smb_command.to_string());

        debug!(cmd = %smb_command, "Running smbclient command");

        let output = Command::new("smbclient")
            .args(&args)
            .output()
            .map_err(|e| CfkError::Network(format!("Failed to run smbclient: {}", e)))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(CfkError::ProviderApi {
                provider: "smb".into(),
                message: format!("smbclient failed: {}", stderr.trim()),
            });
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Connect to SMB server (validates connectivity via smbclient)
    pub async fn connect(&mut self) -> CfkResult<()> {
        // Verify smbclient can reach the share by listing root
        let _output = self.run_smbclient_command("ls")?;
        self.session = Some(SessionId(1));
        self.tree_id = Some(TreeId(1));
        Ok(())
    }

    /// Disconnect from SMB server
    pub async fn disconnect(&mut self) -> CfkResult<()> {
        self.tree_id = None;
        self.session = None;
        Ok(())
    }

    /// Convert VirtualPath to SMB path (backslashes)
    fn to_smb_path(&self, path: &VirtualPath) -> String {
        if path.segments.is_empty() {
            "\\".to_string()
        } else {
            format!("\\{}", path.segments.join("\\"))
        }
    }

    /// Convert VirtualPath to a POSIX-style path for smbclient commands.
    fn to_smb_posix_path(&self, path: &VirtualPath) -> String {
        if path.segments.is_empty() {
            "/".to_string()
        } else {
            format!("/{}", path.segments.join("/"))
        }
    }

    /// Parse an `ls` output line from smbclient into an entry.
    ///
    /// Typical smbclient `ls` output lines look like:
    /// ```text
    ///   .                                   D        0  Mon Jan  1 00:00:00 2024
    ///   ..                                  D        0  Mon Jan  1 00:00:00 2024
    ///   somefile.txt                        A     1234  Mon Jan  1 12:34:56 2024
    ///   subdir                              D        0  Mon Jan  1 00:00:00 2024
    /// ```
    fn parse_ls_line(&self, line: &str, parent_path: &VirtualPath) -> Option<Entry> {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return None;
        }

        // smbclient ls format: "  name   attrs   size   date"
        // We parse by finding the attributes column (single letter flags like D, A, H, S, R, N)
        // The attributes are typically a sequence of letters like "D", "A", "DA", "AHS" etc.
        // They appear after whitespace following the filename.

        // Skip summary lines like "blocks of size ... blocks available"
        if trimmed.contains("blocks of size") || trimmed.contains("blocks available") {
            return None;
        }

        // Try to parse: filename is at the start (may have spaces),
        // then flags, then size, then date.
        // We look for the attributes field which contains only D/A/H/S/R/N characters.
        // The trick is to scan from the right: date, then size, then attrs, then name.

        // Split into parts respecting the fixed-width format
        // smbclient uses a fixed-width column format:
        //   filename (variable)  attrs(~1-6 chars)  size(~10 chars right-aligned)  date

        // Find the size field (a number) by scanning from the right past the date
        let parts: Vec<&str> = trimmed.splitn(2, |c: char| c == 'D' || c == 'A' || c == 'N' || c == 'H' || c == 'S' || c == 'R')
            .collect();

        // Simpler approach: use a regex-like manual parse
        // Pattern: "  NAME    FLAGS    SIZE  DATE"
        // FLAGS is one or more of [DAHSRN]
        // SIZE is a number
        // We find the last number before the date

        // Find all whitespace-separated tokens
        let tokens: Vec<&str> = trimmed.split_whitespace().collect();
        if tokens.len() < 6 {
            return None;
        }

        // The name is everything before the attribute flags
        // Attribute flags are single-char sequences from DAHSRN
        // Find the attribute token index
        let mut attr_idx = None;
        for (i, token) in tokens.iter().enumerate() {
            if i > 0 && token.chars().all(|c| "DAHSRN".contains(c)) && !token.is_empty() {
                // Next token should be a number (size)
                if i + 1 < tokens.len() && tokens[i + 1].parse::<u64>().is_ok() {
                    attr_idx = Some(i);
                    break;
                }
            }
        }

        let attr_idx = attr_idx?;
        let name = tokens[..attr_idx].join(" ");

        // Skip . and ..
        if name == "." || name == ".." {
            return None;
        }

        let attrs = tokens[attr_idx];
        let size: u64 = tokens[attr_idx + 1].parse().ok()?;

        let is_dir = attrs.contains('D');
        let kind = if is_dir { EntryKind::Directory } else { EntryKind::File };

        let mut metadata = Metadata::new();
        metadata.size = Some(size);
        metadata.custom.insert("smb_attrs".to_string(), attrs.to_string());

        let entry_path = parent_path.join(&name);
        Some(Entry { path: entry_path, kind, metadata })
    }
}

#[async_trait]
impl StorageBackend for SmbBackend {
    fn id(&self) -> &str {
        &self.id
    }

    fn display_name(&self) -> &str {
        match self.config.version {
            SmbVersion::Smb1 => "SMB1/CIFS",
            SmbVersion::Smb2 => "SMB2",
            SmbVersion::Smb21 => "SMB2.1",
            SmbVersion::Smb3 => "SMB3",
            SmbVersion::Smb302 => "SMB3.0.2",
            SmbVersion::Smb311 => "SMB3.1.1",
        }
    }

    fn capabilities(&self) -> &StorageCapabilities {
        &self.capabilities
    }

    async fn is_available(&self) -> bool {
        Self::smbclient_available()
    }

    async fn get_metadata(&self, path: &VirtualPath) -> CfkResult<Entry> {
        let smb_path = self.to_smb_posix_path(path);
        let cmd = format!("allinfo \"{}\"", smb_path);
        let output = self.run_smbclient_command(&cmd)?;

        // Parse allinfo output for file attributes
        let mut metadata = Metadata::new();
        let mut kind = EntryKind::File;

        for line in output.lines() {
            let trimmed = line.trim();
            if let Some(size_str) = trimmed.strip_prefix("stream: [::$DATA], ") {
                // Parse size from stream info
                if let Some(size_part) = size_str.strip_suffix(" bytes") {
                    if let Ok(size) = size_part.trim().parse::<u64>() {
                        metadata.size = Some(size);
                    }
                }
            }
            if trimmed.starts_with("attributes:") && trimmed.contains("D") {
                kind = EntryKind::Directory;
            }
        }

        Ok(Entry { path: path.clone(), kind, metadata })
    }

    async fn list_directory(&self, path: &VirtualPath, _options: &ListOptions) -> CfkResult<DirectoryListing> {
        let smb_path = self.to_smb_posix_path(path);
        let cmd = if smb_path == "/" {
            "ls".to_string()
        } else {
            format!("ls \"{}/*\"", smb_path.trim_end_matches('/'))
        };

        let output = self.run_smbclient_command(&cmd)?;

        let mut entries = Vec::new();
        for line in output.lines() {
            if let Some(entry) = self.parse_ls_line(line, path) {
                entries.push(entry);
            }
        }

        Ok(DirectoryListing::new(path.clone(), entries))
    }

    async fn read_file(&self, path: &VirtualPath, _options: &ReadOptions) -> CfkResult<ByteStream> {
        let smb_path = self.to_smb_posix_path(path);

        // Use a temporary file to download via smbclient
        let tmp_dir = std::env::temp_dir();
        let tmp_file = tmp_dir.join(format!("cfk_smb_{}", std::process::id()));
        let tmp_path_str = tmp_file.display().to_string();

        let cmd = format!("get \"{}\" \"{}\"", smb_path, tmp_path_str);
        self.run_smbclient_command(&cmd)?;

        // Read the temporary file and clean up
        let data = std::fs::read(&tmp_file).map_err(|e| {
            CfkError::Other(format!("Failed to read downloaded file: {}", e))
        })?;
        let _ = std::fs::remove_file(&tmp_file);

        let bytes = Bytes::from(data);
        Ok(Box::pin(futures::stream::once(async { Ok(bytes) })))
    }

    async fn write_file(&self, path: &VirtualPath, data: Bytes, _options: &WriteOptions) -> CfkResult<Entry> {
        let smb_path = self.to_smb_posix_path(path);

        // Write data to a temporary local file, then upload via smbclient
        let tmp_dir = std::env::temp_dir();
        let tmp_file = tmp_dir.join(format!("cfk_smb_put_{}", std::process::id()));
        std::fs::write(&tmp_file, &data).map_err(|e| {
            CfkError::Other(format!("Failed to write temp file: {}", e))
        })?;

        let tmp_path_str = tmp_file.display().to_string();
        let cmd = format!("put \"{}\" \"{}\"", tmp_path_str, smb_path);
        let result = self.run_smbclient_command(&cmd);
        let _ = std::fs::remove_file(&tmp_file);
        result?;

        // Return metadata for the written file
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

        // Collect the stream into a single buffer, then delegate to write_file
        let mut data = Vec::new();
        while let Some(chunk) = stream.next().await {
            data.extend_from_slice(&chunk?);
        }
        self.write_file(path, Bytes::from(data), options).await
    }

    async fn delete(&self, path: &VirtualPath, _options: &DeleteOptions) -> CfkResult<()> {
        let smb_path = self.to_smb_posix_path(path);

        // Try rm first (file), then rmdir (directory)
        let cmd = format!("rm \"{}\"", smb_path);
        match self.run_smbclient_command(&cmd) {
            Ok(_) => Ok(()),
            Err(_) => {
                // Might be a directory
                let cmd = format!("rmdir \"{}\"", smb_path);
                self.run_smbclient_command(&cmd)?;
                Ok(())
            }
        }
    }

    async fn create_directory(&self, path: &VirtualPath) -> CfkResult<Entry> {
        let smb_path = self.to_smb_posix_path(path);
        let cmd = format!("mkdir \"{}\"", smb_path);
        self.run_smbclient_command(&cmd)?;

        Ok(Entry {
            path: path.clone(),
            kind: EntryKind::Directory,
            metadata: Metadata::new(),
        })
    }

    async fn copy(&self, from: &VirtualPath, to: &VirtualPath, _options: &CopyOptions) -> CfkResult<Entry> {
        if self.config.version == SmbVersion::Smb1 {
            return Err(CfkError::Unsupported("SMB1 doesn't support server-side copy".into()));
        }

        // smbclient does not have a native server-side copy command,
        // so we download then re-upload.
        let from_path = self.to_smb_posix_path(from);
        let to_path = self.to_smb_posix_path(to);

        let tmp_dir = std::env::temp_dir();
        let tmp_file = tmp_dir.join(format!("cfk_smb_copy_{}", std::process::id()));
        let tmp_path_str = tmp_file.display().to_string();

        // Download source
        let cmd = format!("get \"{}\" \"{}\"", from_path, tmp_path_str);
        self.run_smbclient_command(&cmd)?;

        // Upload to destination
        let cmd = format!("put \"{}\" \"{}\"", tmp_path_str, to_path);
        let result = self.run_smbclient_command(&cmd);
        let _ = std::fs::remove_file(&tmp_file);
        result?;

        self.get_metadata(to).await
    }

    async fn rename(&self, from: &VirtualPath, to: &VirtualPath, _options: &MoveOptions) -> CfkResult<Entry> {
        let from_path = self.to_smb_posix_path(from);
        let to_path = self.to_smb_posix_path(to);

        let cmd = format!("rename \"{}\" \"{}\"", from_path, to_path);
        self.run_smbclient_command(&cmd)?;

        self.get_metadata(to).await
    }

    async fn get_space_info(&self) -> CfkResult<SpaceInfo> {
        // smbclient `du` command can provide space info in some cases
        // but it's not reliable; return unknown.
        Ok(SpaceInfo::unknown())
    }
}

/// SMB file attributes
#[derive(Debug, Clone, Copy, Default)]
pub struct SmbFileAttributes(u32);

impl SmbFileAttributes {
    pub const READONLY: u32 = 0x0001;
    pub const HIDDEN: u32 = 0x0002;
    pub const SYSTEM: u32 = 0x0004;
    pub const DIRECTORY: u32 = 0x0010;
    pub const ARCHIVE: u32 = 0x0020;
    pub const NORMAL: u32 = 0x0080;
    pub const TEMPORARY: u32 = 0x0100;
    pub const SPARSE: u32 = 0x0200;
    pub const REPARSE_POINT: u32 = 0x0400;
    pub const COMPRESSED: u32 = 0x0800;
    pub const ENCRYPTED: u32 = 0x4000;

    /// Returns true if the directory attribute flag is set.
    pub fn is_directory(&self) -> bool {
        self.0 & Self::DIRECTORY != 0
    }

    /// Returns true if the hidden attribute flag is set.
    pub fn is_hidden(&self) -> bool {
        self.0 & Self::HIDDEN != 0
    }

    /// Returns true if the read-only attribute flag is set.
    pub fn is_readonly(&self) -> bool {
        self.0 & Self::READONLY != 0
    }

    /// Returns true if the reparse point (symlink) attribute flag is set.
    pub fn is_symlink(&self) -> bool {
        self.0 & Self::REPARSE_POINT != 0
    }
}

/// SMB file information
#[derive(Debug, Clone, Default)]
pub struct SmbFileInfo {
    /// Windows FILETIME for creation
    pub creation_time: u64,
    /// Windows FILETIME for last access
    pub last_access_time: u64,
    /// Windows FILETIME for last write
    pub last_write_time: u64,
    /// Windows FILETIME for change
    pub change_time: u64,
    /// File attribute flags
    pub attributes: SmbFileAttributes,
    /// Allocation size on disk
    pub allocation_size: u64,
    /// Logical end-of-file position (file size)
    pub end_of_file: u64,
    /// Unique file identifier
    pub file_id: u64,
}

impl SmbFileInfo {
    /// Convert Windows FILETIME to Unix timestamp.
    ///
    /// FILETIME is 100-nanosecond intervals since Jan 1, 1601.
    /// Unix epoch is Jan 1, 1970.
    fn filetime_to_unix(ft: u64) -> Option<i64> {
        const FILETIME_UNIX_DIFF: u64 = 116444736000000000;
        if ft > FILETIME_UNIX_DIFF {
            Some(((ft - FILETIME_UNIX_DIFF) / 10000000) as i64)
        } else {
            None
        }
    }

    /// Convert this SMB file info into a CFK Entry.
    pub fn to_entry(&self, backend_id: &str, path: &str) -> Entry {
        let kind = if self.attributes.is_directory() {
            EntryKind::Directory
        } else if self.attributes.is_symlink() {
            EntryKind::Symlink
        } else {
            EntryKind::File
        };

        let mut metadata = Metadata::default();
        metadata.size = Some(self.end_of_file);

        if let Some(ts) = Self::filetime_to_unix(self.last_write_time) {
            metadata.modified = chrono::DateTime::from_timestamp(ts, 0);
        }
        if let Some(ts) = Self::filetime_to_unix(self.creation_time) {
            metadata.created = chrono::DateTime::from_timestamp(ts, 0);
        }

        metadata.custom.insert(
            "readonly".to_string(),
            self.attributes.is_readonly().to_string(),
        );
        metadata.custom.insert(
            "hidden".to_string(),
            self.attributes.is_hidden().to_string(),
        );

        Entry {
            path: VirtualPath::new(backend_id, path),
            kind,
            metadata,
        }
    }
}

/// Helper to use system mount
impl SmbBackend {
    /// Mount using system mount.cifs (Linux) or mount_smbfs (macOS)
    pub fn mount_system(&self, mount_point: &PathBuf) -> CfkResult<()> {
        let source = format!("//{}/{}", self.config.server, self.config.share);

        #[cfg(target_os = "linux")]
        {
            let (username, password) = match &self.config.auth {
                SmbAuth::Anonymous => ("guest".to_string(), String::new()),
                SmbAuth::Ntlm { username, password, .. } => (username.clone(), password.clone()),
                SmbAuth::Kerberos { .. } => {
                    return Err(CfkError::Unsupported(
                        "Kerberos mount requires system configuration".into(),
                    ))
                }
            };

            let options = format!(
                "username={},password={},vers={}",
                username,
                password,
                match self.config.version {
                    SmbVersion::Smb1 => "1.0",
                    SmbVersion::Smb2 => "2.0",
                    SmbVersion::Smb21 => "2.1",
                    SmbVersion::Smb3 | SmbVersion::Smb302 | SmbVersion::Smb311 => "3.0",
                }
            );

            let status = Command::new("mount")
                .args([
                    "-t", "cifs",
                    "-o", &options,
                    &source,
                    mount_point.to_str().unwrap_or("/mnt"),
                ])
                .status()
                .map_err(|e| CfkError::Network(format!("Failed to run mount: {}", e)))?;

            if !status.success() {
                return Err(CfkError::ProviderApi {
                    provider: "smb".into(),
                    message: "mount.cifs failed".into(),
                });
            }
        }

        #[cfg(target_os = "macos")]
        {
            let status = Command::new("mount_smbfs")
                .args([&source, mount_point.to_str().unwrap_or("/mnt")])
                .status()
                .map_err(|e| CfkError::Network(format!("Failed to run mount_smbfs: {}", e)))?;

            if !status.success() {
                return Err(CfkError::ProviderApi {
                    provider: "smb".into(),
                    message: "mount_smbfs failed".into(),
                });
            }
        }

        #[cfg(not(any(target_os = "linux", target_os = "macos")))]
        {
            return Err(CfkError::Unsupported(
                "System SMB mount not supported on this platform".into(),
            ));
        }

        Ok(())
    }
}
