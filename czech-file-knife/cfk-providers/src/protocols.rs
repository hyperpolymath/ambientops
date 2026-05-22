// SPDX-License-Identifier: MPL-2.0
//! Exotic protocol support
//!
//! Additional protocols beyond standard cloud/file systems:
//! - NNTP/NNTPS: Usenet
//! - Gopher/Gopher+: Pre-web protocol
//! - Gemini: Modern minimalist protocol
//! - RTSP: Streaming
//! - BitTorrent: P2P file sharing
//! - DAT/Hypercore: P2P versioned data
//! - Freenet: Anonymous storage
//! - I2P: Anonymous network
//! - Tor: Onion services
//! - MTP: Mobile devices
//! - AFP: Apple Filing
//! - DLNA/UPnP: Media discovery

use cfk_core::{CfkError, CfkResult};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::time::Duration;

/// Protocol capabilities
#[derive(Debug, Clone, Default)]
pub struct ProtocolInfo {
    /// Human-readable protocol name
    pub name: &'static str,
    /// URI scheme identifier
    pub scheme: &'static str,
    /// Default TCP/UDP port
    pub default_port: u16,
    /// Whether the protocol uses encryption by default
    pub encrypted: bool,
    /// Whether the protocol supports uploading
    pub bidirectional: bool,
    /// Whether the protocol supports media streaming
    pub streaming: bool,
    /// Whether the protocol allows anonymous access
    pub anonymous: bool,
}

/// Supported exotic protocols
pub const PROTOCOLS: &[ProtocolInfo] = &[
    ProtocolInfo {
        name: "Usenet (NNTP)",
        scheme: "nntp",
        default_port: 119,
        encrypted: false,
        bidirectional: true,
        streaming: false,
        anonymous: false,
    },
    ProtocolInfo {
        name: "Usenet Secure (NNTPS)",
        scheme: "nntps",
        default_port: 563,
        encrypted: true,
        bidirectional: true,
        streaming: false,
        anonymous: false,
    },
    ProtocolInfo {
        name: "Gopher",
        scheme: "gopher",
        default_port: 70,
        encrypted: false,
        bidirectional: false,
        streaming: false,
        anonymous: true,
    },
    ProtocolInfo {
        name: "Gemini",
        scheme: "gemini",
        default_port: 1965,
        encrypted: true,
        bidirectional: false,
        streaming: false,
        anonymous: true,
    },
    ProtocolInfo {
        name: "RTSP (Streaming)",
        scheme: "rtsp",
        default_port: 554,
        encrypted: false,
        bidirectional: false,
        streaming: true,
        anonymous: false,
    },
    ProtocolInfo {
        name: "BitTorrent",
        scheme: "magnet",
        default_port: 6881,
        encrypted: false,
        bidirectional: true,
        streaming: false,
        anonymous: false,
    },
    ProtocolInfo {
        name: "DAT/Hypercore",
        scheme: "dat",
        default_port: 3282,
        encrypted: true,
        bidirectional: true,
        streaming: true,
        anonymous: false,
    },
    ProtocolInfo {
        name: "Freenet",
        scheme: "freenet",
        default_port: 8888,
        encrypted: true,
        bidirectional: true,
        streaming: false,
        anonymous: true,
    },
    ProtocolInfo {
        name: "I2P",
        scheme: "i2p",
        default_port: 7657,
        encrypted: true,
        bidirectional: true,
        streaming: false,
        anonymous: true,
    },
    ProtocolInfo {
        name: "Tor Onion",
        scheme: "onion",
        default_port: 9050,
        encrypted: true,
        bidirectional: true,
        streaming: false,
        anonymous: true,
    },
    ProtocolInfo {
        name: "MTP (Mobile)",
        scheme: "mtp",
        default_port: 0,
        encrypted: false,
        bidirectional: true,
        streaming: false,
        anonymous: false,
    },
    ProtocolInfo {
        name: "AFP (Apple)",
        scheme: "afp",
        default_port: 548,
        encrypted: false,
        bidirectional: true,
        streaming: false,
        anonymous: false,
    },
    ProtocolInfo {
        name: "DLNA/UPnP",
        scheme: "dlna",
        default_port: 1900,
        encrypted: false,
        bidirectional: false,
        streaming: true,
        anonymous: false,
    },
    ProtocolInfo {
        name: "Matrix",
        scheme: "matrix",
        default_port: 8448,
        encrypted: true,
        bidirectional: true,
        streaming: false,
        anonymous: false,
    },
];

/// Find protocol info by scheme
pub fn get_protocol(scheme: &str) -> Option<&'static ProtocolInfo> {
    PROTOCOLS.iter().find(|p| p.scheme == scheme)
}

/// List all supported protocol schemes
pub fn list_schemes() -> Vec<&'static str> {
    PROTOCOLS.iter().map(|p| p.scheme).collect()
}

/// Default TCP connect timeout
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(15);

/// Gopher protocol client
///
/// Implements the Gopher protocol (RFC 1436). Gopher is a simple
/// text-based protocol: the client connects via TCP, sends a selector
/// string followed by CR-LF, and reads the server's response until
/// the connection closes.
pub mod gopher {
    use super::*;

    /// Gopher item types (RFC 1436 Section 3.8)
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum ItemType {
        /// Type 0: Plain text file
        TextFile,
        /// Type 1: Gopher directory/menu
        Directory,
        /// Type 2: CSO phone-book server
        CsoServer,
        /// Type 3: Error message
        Error,
        /// Type 4: BinHex-encoded file
        BinHex,
        /// Type 5: DOS binary archive
        DosBinary,
        /// Type 6: UUEncoded text
        UuEncoded,
        /// Type 7: Index-search server
        IndexSearch,
        /// Type 8: Telnet session pointer
        Telnet,
        /// Type 9: Binary file
        Binary,
        /// Type +: Redundant server
        Mirror,
        /// Type g: GIF image
        Gif,
        /// Type I: Generic image
        Image,
        /// Type h: HTML document
        Html,
        /// Type i: Informational message (displayed, not selectable)
        Info,
        /// Type s: Sound file
        Sound,
    }

    impl ItemType {
        /// Parse a single-character item type code into an ItemType variant.
        pub fn from_char(c: char) -> Option<Self> {
            match c {
                '0' => Some(Self::TextFile),
                '1' => Some(Self::Directory),
                '2' => Some(Self::CsoServer),
                '3' => Some(Self::Error),
                '4' => Some(Self::BinHex),
                '5' => Some(Self::DosBinary),
                '6' => Some(Self::UuEncoded),
                '7' => Some(Self::IndexSearch),
                '8' => Some(Self::Telnet),
                '9' => Some(Self::Binary),
                '+' => Some(Self::Mirror),
                'g' => Some(Self::Gif),
                'I' => Some(Self::Image),
                'h' => Some(Self::Html),
                'i' => Some(Self::Info),
                's' => Some(Self::Sound),
                _ => None,
            }
        }
    }

    /// A single entry in a Gopher directory listing
    #[derive(Debug, Clone)]
    pub struct GopherEntry {
        /// Item type code
        pub item_type: ItemType,
        /// Display text shown to the user
        pub display: String,
        /// Selector string to fetch this item
        pub selector: String,
        /// Hostname of the server for this item
        pub host: String,
        /// Port of the server for this item
        pub port: u16,
    }

    /// Fetch a resource from a Gopher server.
    ///
    /// Parses a `gopher://host[:port][/type][selector]` URL.
    /// Connects via TCP, sends the selector with CR-LF, and reads
    /// the full response.
    pub async fn fetch(url: &str) -> CfkResult<Vec<u8>> {
        // Parse gopher URL
        let url = url.strip_prefix("gopher://").unwrap_or(url);

        // Split host[:port] from selector
        let (hostport, selector) = match url.find('/') {
            Some(idx) => (&url[..idx], &url[idx + 1..]),
            None => (url, ""),
        };

        let (host, port) = match hostport.rsplit_once(':') {
            Some((h, p)) => (h, p.parse::<u16>().unwrap_or(70)),
            None => (hostport, 70),
        };

        // The first character after / may be a type indicator; skip it
        // for the selector sent to the server
        let selector = if selector.len() > 1 && selector.as_bytes()[0].is_ascii_alphanumeric() {
            // First char is the type indicator (0-9, g, h, I, etc.)
            &selector[1..]
        } else {
            selector
        };

        let addr = format!("{}:{}", host, port);
        let mut stream = TcpStream::connect_timeout(
            &addr.parse().map_err(|e| CfkError::Network(format!("Invalid address: {}", e)))?,
            DEFAULT_TIMEOUT,
        ).map_err(|e| CfkError::Network(format!("Gopher connect failed: {}", e)))?;

        stream.set_read_timeout(Some(DEFAULT_TIMEOUT))
            .map_err(|e| CfkError::Network(format!("Set timeout failed: {}", e)))?;

        // Send selector + CRLF
        write!(stream, "{}\r\n", selector)
            .map_err(|e| CfkError::Network(format!("Gopher send failed: {}", e)))?;

        // Read entire response
        let mut response = Vec::new();
        stream.read_to_end(&mut response)
            .map_err(|e| CfkError::Network(format!("Gopher read failed: {}", e)))?;

        Ok(response)
    }

    /// Parse a Gopher directory listing (type 1 response).
    ///
    /// Each line in a Gopher menu has the format:
    /// `<type><display>\t<selector>\t<host>\t<port>\r\n`
    ///
    /// The listing is terminated by a line containing only `.`
    pub fn parse_directory(data: &[u8]) -> Vec<GopherEntry> {
        let text = String::from_utf8_lossy(data);
        let mut entries = Vec::new();

        for line in text.lines() {
            // End-of-listing marker
            if line == "." {
                break;
            }

            if line.is_empty() {
                continue;
            }

            // First character is the item type
            let type_char = line.chars().next().unwrap_or('i');
            let item_type = match ItemType::from_char(type_char) {
                Some(t) => t,
                None => continue, // Skip unknown types
            };

            // Rest of line is tab-separated: display, selector, host, port
            let rest = &line[type_char.len_utf8()..];
            let fields: Vec<&str> = rest.split('\t').collect();

            if fields.len() < 4 {
                // Malformed line; try to salvage what we can
                entries.push(GopherEntry {
                    item_type,
                    display: fields.first().unwrap_or(&"").to_string(),
                    selector: fields.get(1).unwrap_or(&"").to_string(),
                    host: fields.get(2).unwrap_or(&"").to_string(),
                    port: fields.get(3).and_then(|p| p.trim().parse().ok()).unwrap_or(70),
                });
                continue;
            }

            entries.push(GopherEntry {
                item_type,
                display: fields[0].to_string(),
                selector: fields[1].to_string(),
                host: fields[2].to_string(),
                port: fields[3].trim().parse().unwrap_or(70),
            });
        }

        entries
    }
}

/// Gemini protocol client
///
/// Implements the Gemini protocol (gemini://geminiprotocol.net/).
/// Gemini uses TLS on port 1965. The client sends the full URL
/// followed by CR-LF, and the server responds with a status line
/// (`<status> <meta>\r\n`) followed by the body.
pub mod gemini {
    use super::*;

    /// Gemini response status code categories
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Status {
        /// 1x: Input required from the user
        Input = 10,
        /// 2x: Success — body follows
        Success = 20,
        /// 3x: Redirect — follow the URL in meta
        Redirect = 30,
        /// 4x: Temporary failure
        TemporaryFailure = 40,
        /// 5x: Permanent failure
        PermanentFailure = 50,
        /// 6x: Client certificate required
        ClientCertRequired = 60,
    }

    impl Status {
        /// Parse a two-digit status code into a Status category.
        pub fn from_code(code: u8) -> Option<Self> {
            match code / 10 {
                1 => Some(Self::Input),
                2 => Some(Self::Success),
                3 => Some(Self::Redirect),
                4 => Some(Self::TemporaryFailure),
                5 => Some(Self::PermanentFailure),
                6 => Some(Self::ClientCertRequired),
                _ => None,
            }
        }
    }

    /// Fetch a Gemini URL and return (status, meta, body).
    ///
    /// Connects via TLS to the server on port 1965, sends the URL,
    /// and parses the response. Uses native-tls with certificate
    /// verification disabled (Gemini servers commonly use self-signed
    /// certificates — this is by design in the Gemini protocol).
    pub async fn fetch(url: &str) -> CfkResult<(Status, String, Vec<u8>)> {
        // Parse the URL
        let url_str = if url.starts_with("gemini://") {
            url.to_string()
        } else {
            format!("gemini://{}", url)
        };

        let parsed = url::Url::parse(&url_str)
            .map_err(|e| CfkError::InvalidPath(format!("Invalid Gemini URL: {}", e)))?;

        let host = parsed.host_str()
            .ok_or_else(|| CfkError::InvalidPath("Missing host in Gemini URL".into()))?;
        let port = parsed.port().unwrap_or(1965);
        let addr = format!("{}:{}", host, port);

        // Connect via TCP
        let tcp_stream = TcpStream::connect_timeout(
            &addr.parse().map_err(|e| CfkError::Network(format!("Invalid address: {}", e)))?,
            DEFAULT_TIMEOUT,
        ).map_err(|e| CfkError::Network(format!("Gemini TCP connect failed: {}", e)))?;

        tcp_stream.set_read_timeout(Some(DEFAULT_TIMEOUT))
            .map_err(|e| CfkError::Network(format!("Set timeout failed: {}", e)))?;

        // Set up TLS — Gemini uses self-signed certs commonly,
        // so we accept invalid certificates (TOFU model)
        let connector = native_tls::TlsConnector::builder()
            .danger_accept_invalid_certs(true)
            .danger_accept_invalid_hostnames(true)
            .build()
            .map_err(|e| CfkError::Network(format!("TLS setup failed: {}", e)))?;

        let mut tls_stream = connector.connect(host, tcp_stream)
            .map_err(|e| CfkError::Network(format!("TLS handshake failed: {}", e)))?;

        // Send the URL + CRLF
        write!(tls_stream, "{}\r\n", url_str)
            .map_err(|e| CfkError::Network(format!("Gemini send failed: {}", e)))?;

        // Read the response header (first line: "<status> <meta>\r\n")
        let mut reader = BufReader::new(&mut tls_stream);
        let mut header_line = String::new();
        reader.read_line(&mut header_line)
            .map_err(|e| CfkError::Network(format!("Gemini header read failed: {}", e)))?;

        let header_line = header_line.trim_end_matches('\n').trim_end_matches('\r');

        // Parse status code (first two characters)
        if header_line.len() < 2 {
            return Err(CfkError::ProviderApi {
                provider: "gemini".into(),
                message: "Response header too short".into(),
            });
        }

        let status_code: u8 = header_line[..2].parse().map_err(|_| {
            CfkError::ProviderApi {
                provider: "gemini".into(),
                message: format!("Invalid status code: {}", &header_line[..2]),
            }
        })?;

        let status = Status::from_code(status_code).ok_or_else(|| {
            CfkError::ProviderApi {
                provider: "gemini".into(),
                message: format!("Unknown status category: {}", status_code),
            }
        })?;

        // Meta is everything after the status code and space
        let meta = if header_line.len() > 3 {
            header_line[3..].to_string()
        } else {
            String::new()
        };

        // Read the body (only present for 2x responses)
        let mut body = Vec::new();
        if status == Status::Success {
            reader.read_to_end(&mut body)
                .map_err(|e| CfkError::Network(format!("Gemini body read failed: {}", e)))?;
        }

        Ok((status, meta, body))
    }
}

/// NNTP (Network News Transfer Protocol) client
///
/// Implements basic NNTP commands (RFC 3977). NNTP is a text-based
/// protocol where the client sends commands and the server responds
/// with a three-digit status code followed by text.
pub mod nntp {
    use super::*;

    /// A Usenet article
    #[derive(Debug, Clone)]
    pub struct Article {
        /// Message-ID header
        pub message_id: String,
        /// Subject header
        pub subject: String,
        /// From header
        pub from: String,
        /// Date header
        pub date: String,
        /// List of newsgroups this article was posted to
        pub newsgroups: Vec<String>,
        /// Article body text
        pub body: String,
    }

    /// An active NNTP connection to a Usenet server
    pub struct NntpClient {
        reader: BufReader<TcpStream>,
        writer: TcpStream,
    }

    impl NntpClient {
        /// Read a single response line from the server.
        fn read_line(&mut self) -> CfkResult<String> {
            let mut line = String::new();
            self.reader.read_line(&mut line)
                .map_err(|e| CfkError::Network(format!("NNTP read failed: {}", e)))?;
            Ok(line.trim_end_matches('\n').trim_end_matches('\r').to_string())
        }

        /// Read a multi-line response terminated by a line containing only `.`.
        fn read_multiline(&mut self) -> CfkResult<Vec<String>> {
            let mut lines = Vec::new();
            loop {
                let line = self.read_line()?;
                if line == "." {
                    break;
                }
                // Dot-stuffing: lines starting with ".." have the leading dot removed
                let content = if line.starts_with("..") {
                    line[1..].to_string()
                } else {
                    line
                };
                lines.push(content);
            }
            Ok(lines)
        }

        /// Send a command to the server.
        fn send_command(&mut self, cmd: &str) -> CfkResult<()> {
            write!(self.writer, "{}\r\n", cmd)
                .map_err(|e| CfkError::Network(format!("NNTP send failed: {}", e)))
        }

        /// Send a command and read the response status line.
        fn command(&mut self, cmd: &str) -> CfkResult<(u16, String)> {
            self.send_command(cmd)?;
            let response = self.read_line()?;
            parse_response(&response)
        }

        /// Select a newsgroup.
        ///
        /// Returns (estimated_count, low_watermark, high_watermark).
        pub fn group(&mut self, name: &str) -> CfkResult<(u64, u64, u64)> {
            let (code, text) = self.command(&format!("GROUP {}", name))?;
            if code != 211 {
                return Err(CfkError::ProviderApi {
                    provider: "nntp".into(),
                    message: format!("GROUP failed ({}): {}", code, text),
                });
            }

            // Response: "211 count low high groupname"
            let parts: Vec<&str> = text.split_whitespace().collect();
            if parts.len() < 3 {
                return Err(CfkError::ProviderApi {
                    provider: "nntp".into(),
                    message: "Malformed GROUP response".into(),
                });
            }

            let count = parts[0].parse::<u64>().unwrap_or(0);
            let low = parts[1].parse::<u64>().unwrap_or(0);
            let high = parts[2].parse::<u64>().unwrap_or(0);

            Ok((count, low, high))
        }

        /// Retrieve an article by its number or message-id.
        pub fn article(&mut self, id: &str) -> CfkResult<Article> {
            let (code, _text) = self.command(&format!("ARTICLE {}", id))?;
            if code != 220 {
                return Err(CfkError::NotFound(format!("Article not found: {}", id)));
            }

            // Read multi-line response (headers + blank line + body)
            let lines = self.read_multiline()?;

            let mut message_id = String::new();
            let mut subject = String::new();
            let mut from = String::new();
            let mut date = String::new();
            let mut newsgroups = Vec::new();
            let mut in_body = false;
            let mut body_lines = Vec::new();

            for line in &lines {
                if in_body {
                    body_lines.push(line.as_str());
                    continue;
                }

                if line.is_empty() {
                    in_body = true;
                    continue;
                }

                // Parse headers (case-insensitive)
                let lower = line.to_lowercase();
                if let Some(_) = lower.strip_prefix("message-id:") {
                    message_id = line[11..].trim().to_string();
                } else if let Some(_) = lower.strip_prefix("subject:") {
                    subject = line[8..].trim().to_string();
                } else if let Some(_) = lower.strip_prefix("from:") {
                    from = line[5..].trim().to_string();
                } else if let Some(_) = lower.strip_prefix("date:") {
                    date = line[5..].trim().to_string();
                } else if let Some(_) = lower.strip_prefix("newsgroups:") {
                    let groups_str = line[11..].trim();
                    newsgroups = groups_str.split(',').map(|g| g.trim().to_string()).collect();
                }
            }

            Ok(Article {
                message_id,
                subject,
                from,
                date,
                newsgroups,
                body: body_lines.join("\n"),
            })
        }

        /// List active newsgroups matching an optional wildmat pattern.
        pub fn list_active(&mut self, wildmat: Option<&str>) -> CfkResult<Vec<String>> {
            let cmd = match wildmat {
                Some(pat) => format!("LIST ACTIVE {}", pat),
                None => "LIST ACTIVE".to_string(),
            };
            let (code, _text) = self.command(&cmd)?;
            if code != 215 {
                return Err(CfkError::ProviderApi {
                    provider: "nntp".into(),
                    message: "LIST ACTIVE failed".into(),
                });
            }

            let lines = self.read_multiline()?;
            let groups: Vec<String> = lines.iter()
                .filter_map(|line| {
                    line.split_whitespace().next().map(String::from)
                })
                .collect();

            Ok(groups)
        }

        /// Quit the NNTP session cleanly.
        pub fn quit(&mut self) -> CfkResult<()> {
            let _ = self.command("QUIT");
            Ok(())
        }
    }

    /// Parse an NNTP response line into (status_code, rest_of_line).
    fn parse_response(line: &str) -> CfkResult<(u16, String)> {
        if line.len() < 3 {
            return Err(CfkError::ProviderApi {
                provider: "nntp".into(),
                message: format!("Response too short: {}", line),
            });
        }

        let code: u16 = line[..3].parse().map_err(|_| {
            CfkError::ProviderApi {
                provider: "nntp".into(),
                message: format!("Invalid status code: {}", &line[..3]),
            }
        })?;

        let text = if line.len() > 4 { line[4..].to_string() } else { String::new() };
        Ok((code, text))
    }

    /// Connect to an NNTP server and return a client handle.
    ///
    /// Reads and validates the server greeting (200 or 201).
    /// The `_tls` parameter is currently unused; for NNTPS, use port 563
    /// with a TLS wrapper externally.
    pub async fn connect(host: &str, port: u16, _tls: bool) -> CfkResult<NntpClient> {
        let addr = format!("{}:{}", host, port);
        let stream = TcpStream::connect_timeout(
            &addr.parse().map_err(|e| CfkError::Network(format!("Invalid address: {}", e)))?,
            DEFAULT_TIMEOUT,
        ).map_err(|e| CfkError::Network(format!("NNTP connect failed: {}", e)))?;

        stream.set_read_timeout(Some(DEFAULT_TIMEOUT))
            .map_err(|e| CfkError::Network(format!("Set timeout failed: {}", e)))?;

        let writer = stream.try_clone()
            .map_err(|e| CfkError::Network(format!("Failed to clone socket: {}", e)))?;

        let mut client = NntpClient {
            reader: BufReader::new(stream),
            writer,
        };

        // Read server greeting
        let greeting = client.read_line()?;
        let (code, _text) = parse_response(&greeting)?;

        // 200 = posting allowed, 201 = posting not allowed, both are OK
        if code != 200 && code != 201 {
            return Err(CfkError::ProviderApi {
                provider: "nntp".into(),
                message: format!("Unexpected greeting: {}", greeting),
            });
        }

        Ok(client)
    }

    /// Convenience function to list newsgroups from a server.
    pub async fn list_groups(host: &str, port: u16) -> CfkResult<Vec<String>> {
        let mut client = connect(host, port, false).await?;
        let groups = client.list_active(None)?;
        let _ = client.quit();
        Ok(groups)
    }
}
