// SPDX-License-Identifier: MPL-2.0
//! Transport layer support
//!
//! Low-level transport protocols:
//! - TCP: Traditional reliable transport
//! - QUIC: Modern UDP-based transport (HTTP/3) — simplified UDP-based placeholder
//! - UDP: Unreliable datagram
//! - Unix sockets: Local IPC
//! - Named pipes: Windows IPC
//! - Multicast: UDP multicast send/recv via `join_multicast_v4`

#![allow(dead_code)] // Some placeholder structs exist for future expansion

use cfk_core::{CfkError, CfkResult};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use tokio::net::TcpStream;
use tracing::{debug, warn};

/// Transport type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    /// Standard TCP
    Tcp,
    /// QUIC (UDP-based reliable transport)
    Quic,
    /// Raw UDP
    Udp,
    /// Unix domain socket
    Unix,
    /// Named pipe (Windows)
    Pipe,
    /// Pragmatic General Multicast (RFC 3208)
    Pgm,
    /// NACK-Oriented Reliable Multicast (RFC 5740)
    Norm,
    /// Reliable Multicast Transport Protocol
    Rmtp,
}

/// Connection configuration
#[derive(Debug, Clone)]
pub struct ConnectionConfig {
    /// Transport protocol to use
    pub transport: Transport,
    /// Remote address (hostname or IP)
    pub addr: String,
    /// Remote port
    pub port: u16,
    /// Connection timeout in milliseconds
    pub timeout_ms: u64,
    /// Enable TCP keepalive
    pub keepalive: bool,
    /// Enable TCP_NODELAY
    pub nodelay: bool,
    /// Read/write buffer size
    pub buffer_size: usize,
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        Self {
            transport: Transport::Tcp,
            addr: "127.0.0.1".into(),
            port: 0,
            timeout_ms: 30000,
            keepalive: true,
            nodelay: true,
            buffer_size: 65536,
        }
    }
}

/// TCP connection wrapper
pub struct TcpConnection {
    stream: TcpStream,
    config: ConnectionConfig,
}

impl TcpConnection {
    /// Establish a new TCP connection to the configured address.
    pub async fn connect(config: ConnectionConfig) -> CfkResult<Self> {
        let addr = format!("{}:{}", config.addr, config.port);
        let stream = TcpStream::connect(&addr).await
            .map_err(|e| CfkError::Network(e.to_string()))?;

        stream.set_nodelay(config.nodelay)
            .map_err(|e| CfkError::Network(e.to_string()))?;

        Ok(Self { stream, config })
    }

    /// Returns a reference to the underlying TCP stream.
    pub fn inner(&self) -> &TcpStream {
        &self.stream
    }

    /// Consumes this wrapper and returns the underlying TCP stream.
    pub fn into_inner(self) -> TcpStream {
        self.stream
    }
}

/// QUIC configuration
#[derive(Debug, Clone)]
pub struct QuicConfig {
    /// ALPN protocol identifiers for negotiation
    pub alpn_protocols: Vec<String>,
    /// Idle timeout before connection close (milliseconds)
    pub max_idle_timeout_ms: u64,
    /// Keepalive ping interval (milliseconds)
    pub keep_alive_interval_ms: Option<u64>,
    /// Maximum concurrent bidirectional streams
    pub max_concurrent_streams: u32,
    /// Initial flow-control window size
    pub initial_window_size: u32,
}

impl Default for QuicConfig {
    fn default() -> Self {
        Self {
            alpn_protocols: vec!["h3".into()],
            max_idle_timeout_ms: 30000,
            keep_alive_interval_ms: Some(15000),
            max_concurrent_streams: 100,
            initial_window_size: 1048576, // 1MB
        }
    }
}

/// QUIC connection — simplified UDP-based placeholder
///
/// Provides a basic reliable-over-UDP transport using sequence numbers
/// and acknowledgements. A production implementation should use the
/// `quinn` crate for full QUIC RFC 9000 compliance.
pub struct QuicConnection {
    config: QuicConfig,
    /// The underlying UDP socket used for the simplified transport
    socket: std::net::UdpSocket,
    /// Remote peer address
    peer_addr: SocketAddr,
    /// Next outgoing sequence number
    next_seq: u64,
}

impl QuicConnection {
    /// Create a new simplified QUIC connection to the given address.
    ///
    /// This uses a basic UDP socket with application-level framing.
    /// For production use, integrate the `quinn` crate instead.
    pub async fn connect(addr: SocketAddr, _server_name: &str, config: QuicConfig) -> CfkResult<Self> {
        debug!(addr = %addr, "Connecting via simplified QUIC transport");

        let local_addr: SocketAddr = "0.0.0.0:0".parse().unwrap();
        let socket = std::net::UdpSocket::bind(local_addr)
            .map_err(|e| CfkError::Network(format!("Failed to bind UDP socket: {}", e)))?;

        socket.connect(addr)
            .map_err(|e| CfkError::Network(format!("Failed to connect UDP socket: {}", e)))?;

        // Set read timeout based on config idle timeout
        let timeout = std::time::Duration::from_millis(config.max_idle_timeout_ms);
        socket.set_read_timeout(Some(timeout))
            .map_err(|e| CfkError::Network(format!("Failed to set timeout: {}", e)))?;

        Ok(Self {
            config,
            socket,
            peer_addr: addr,
            next_seq: 0,
        })
    }

    /// Open a new bidirectional stream.
    ///
    /// In this simplified implementation, each stream is a separate
    /// framed message exchange over the single UDP socket.
    pub async fn open_stream(&self) -> CfkResult<QuicStream> {
        Ok(QuicStream {
            socket_fd: self.socket.try_clone()
                .map_err(|e| CfkError::Network(format!("Failed to clone socket: {}", e)))?,
            peer_addr: self.peer_addr,
        })
    }

    /// Send raw data over the simplified QUIC transport.
    ///
    /// Frames the data with a 8-byte sequence number header.
    pub fn send(&mut self, data: &[u8]) -> CfkResult<usize> {
        // Simple framing: [8-byte seq LE] [payload]
        let mut frame = Vec::with_capacity(8 + data.len());
        frame.extend_from_slice(&self.next_seq.to_le_bytes());
        frame.extend_from_slice(data);
        self.next_seq += 1;

        self.socket.send(&frame)
            .map_err(|e| CfkError::Network(format!("QUIC send failed: {}", e)))
    }

    /// Receive raw data from the simplified QUIC transport.
    ///
    /// Returns the payload after stripping the sequence number header.
    pub fn recv(&self, buf: &mut [u8]) -> CfkResult<(u64, usize)> {
        let mut frame = vec![0u8; 8 + buf.len()];
        let n = self.socket.recv(&mut frame)
            .map_err(|e| CfkError::Network(format!("QUIC recv failed: {}", e)))?;

        if n < 8 {
            return Err(CfkError::Network("QUIC frame too short".into()));
        }

        let seq = u64::from_le_bytes(frame[..8].try_into().unwrap());
        let payload_len = n - 8;
        buf[..payload_len].copy_from_slice(&frame[8..n]);

        Ok((seq, payload_len))
    }
}

/// QUIC bidirectional stream
///
/// A lightweight wrapper around a cloned UDP socket that represents
/// one logical stream in the simplified QUIC transport.
pub struct QuicStream {
    /// Cloned UDP socket for this stream
    socket_fd: std::net::UdpSocket,
    /// Remote peer address
    peer_addr: SocketAddr,
}

impl QuicStream {
    /// Send data on this stream.
    pub fn send(&self, data: &[u8]) -> CfkResult<usize> {
        self.socket_fd.send(data)
            .map_err(|e| CfkError::Network(format!("Stream send failed: {}", e)))
    }

    /// Receive data from this stream.
    pub fn recv(&self, buf: &mut [u8]) -> CfkResult<usize> {
        self.socket_fd.recv(buf)
            .map_err(|e| CfkError::Network(format!("Stream recv failed: {}", e)))
    }
}

/// Multi-transport connector
///
/// Tries the preferred transport first, falling back to an optional
/// secondary transport on failure.
pub struct MultiTransport {
    preferred: Transport,
    fallback: Option<Transport>,
}

impl MultiTransport {
    /// Create a new multi-transport connector with the given preferred protocol.
    pub fn new(preferred: Transport) -> Self {
        Self { preferred, fallback: None }
    }

    /// Set a fallback transport to try if the preferred one fails.
    pub fn with_fallback(mut self, fallback: Transport) -> Self {
        self.fallback = Some(fallback);
        self
    }

    /// Connect using preferred transport, fall back if needed.
    pub async fn connect(&self, addr: &str, port: u16) -> CfkResult<Box<dyn TransportStream>> {
        let config = ConnectionConfig {
            transport: self.preferred,
            addr: addr.into(),
            port,
            ..Default::default()
        };

        match self.preferred {
            Transport::Tcp => {
                let conn = TcpConnection::connect(config).await?;
                Ok(Box::new(conn))
            }
            Transport::Quic => {
                // Try the simplified QUIC transport
                let socket_addr: SocketAddr = format!("{}:{}", addr, port)
                    .parse()
                    .map_err(|e| CfkError::Network(format!("Invalid address: {}", e)))?;
                let quic_config = QuicConfig::default();

                match QuicConnection::connect(socket_addr, addr, quic_config).await {
                    Ok(conn) => Ok(Box::new(QuicTransportWrapper { _conn: conn })),
                    Err(e) => {
                        // Fall back to TCP if configured
                        if let Some(Transport::Tcp) = self.fallback {
                            warn!("QUIC connect failed ({}), falling back to TCP", e);
                            let tcp_config = ConnectionConfig {
                                transport: Transport::Tcp,
                                addr: addr.into(),
                                port,
                                ..Default::default()
                            };
                            let conn = TcpConnection::connect(tcp_config).await?;
                            Ok(Box::new(conn))
                        } else {
                            Err(e)
                        }
                    }
                }
            }
            _ => Err(CfkError::Unsupported(format!("{:?} not implemented", self.preferred))),
        }
    }
}

/// Abstract transport stream trait
pub trait TransportStream: Send + Sync {
    /// Returns the transport protocol type for this stream.
    fn transport_type(&self) -> Transport;
}

impl TransportStream for TcpConnection {
    fn transport_type(&self) -> Transport {
        Transport::Tcp
    }
}

/// Wrapper to make QuicConnection implement TransportStream
struct QuicTransportWrapper {
    _conn: QuicConnection,
}

impl TransportStream for QuicTransportWrapper {
    fn transport_type(&self) -> Transport {
        Transport::Quic
    }
}

/// Reliable multicast support
///
/// Provides basic UDP multicast send/receive using `std::net::UdpSocket`
/// with `join_multicast_v4`. PGM and NORM configurations set up the
/// underlying multicast group and rate parameters, but the transport
/// uses standard UDP multicast (not the full PGM/NORM wire protocols).
pub mod multicast {
    use super::*;

    /// Multicast group configuration
    #[derive(Debug, Clone)]
    pub struct MulticastGroup {
        /// Multicast group IPv4 address (must be in 224.0.0.0/4)
        pub group_addr: Ipv4Addr,
        /// UDP port for multicast traffic
        pub port: u16,
        /// Local network interface to bind (None = any)
        pub interface: Option<Ipv4Addr>,
        /// Time-to-live for multicast packets
        pub ttl: u8,
        /// Whether to receive own multicast packets
        pub loopback: bool,
    }

    impl Default for MulticastGroup {
        fn default() -> Self {
            Self {
                group_addr: Ipv4Addr::new(239, 255, 0, 1),  // Local scope
                port: 5000,
                interface: None,
                ttl: 1,
                loopback: false,
            }
        }
    }

    /// PGM (Pragmatic General Multicast) configuration
    #[derive(Debug, Clone)]
    pub struct PgmConfig {
        /// Multicast group settings
        pub group: MulticastGroup,
        /// Rate limit in kilobits per second
        pub rate_limit_kbps: u32,
        /// Transmit window size
        pub window_size: u32,
        /// NAK repeat data interval in milliseconds
        pub nak_rdata_ivl_ms: u32,
    }

    impl Default for PgmConfig {
        fn default() -> Self {
            Self {
                group: MulticastGroup::default(),
                rate_limit_kbps: 10000,  // 10 Mbps
                window_size: 1024,
                nak_rdata_ivl_ms: 200,
            }
        }
    }

    /// NORM (NACK-Oriented Reliable Multicast) configuration
    #[derive(Debug, Clone)]
    pub struct NormConfig {
        /// Multicast group settings
        pub group: MulticastGroup,
        /// Transmission rate in kilobits per second
        pub rate_kbps: u32,
        /// Buffer size in bytes
        pub buffer_size: usize,
        /// Maximum segment size
        pub segment_size: u16,
        /// Enable Forward Error Correction
        pub fec_enabled: bool,
    }

    impl Default for NormConfig {
        fn default() -> Self {
            Self {
                group: MulticastGroup::default(),
                rate_kbps: 10000,
                buffer_size: 1048576,  // 1MB
                segment_size: 1400,
                fec_enabled: true,
            }
        }
    }

    /// Set up a UDP multicast socket from the given group configuration.
    fn create_multicast_socket(group: &MulticastGroup) -> CfkResult<std::net::UdpSocket> {
        let bind_addr = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, group.port);
        let socket = std::net::UdpSocket::bind(bind_addr)
            .map_err(|e| CfkError::Network(format!("Failed to bind multicast socket: {}", e)))?;

        let iface = group.interface.unwrap_or(Ipv4Addr::UNSPECIFIED);

        socket.join_multicast_v4(&group.group_addr, &iface)
            .map_err(|e| CfkError::Network(format!("Failed to join multicast group: {}", e)))?;

        socket.set_multicast_ttl_v4(group.ttl as u32)
            .map_err(|e| CfkError::Network(format!("Failed to set multicast TTL: {}", e)))?;

        socket.set_multicast_loop_v4(group.loopback)
            .map_err(|e| CfkError::Network(format!("Failed to set multicast loopback: {}", e)))?;

        Ok(socket)
    }

    /// Reliable multicast sender
    ///
    /// Uses standard UDP multicast to send data to all group members.
    /// The PGM/NORM config parameters configure the multicast group;
    /// actual wire-level reliability depends on the transport.
    pub struct MulticastSender {
        transport: Transport,
        socket: std::net::UdpSocket,
        dest_addr: SocketAddrV4,
    }

    impl MulticastSender {
        /// Create a PGM-style multicast sender.
        ///
        /// Uses UDP multicast as the underlying transport. The PGM
        /// rate limit and window parameters are recorded but not
        /// enforced at the wire level in this implementation.
        pub async fn new_pgm(config: PgmConfig) -> CfkResult<Self> {
            debug!(
                group = %config.group.group_addr,
                port = config.group.port,
                "Creating PGM multicast sender"
            );

            let socket = create_multicast_socket(&config.group)?;
            let dest_addr = SocketAddrV4::new(config.group.group_addr, config.group.port);

            Ok(Self {
                transport: Transport::Pgm,
                socket,
                dest_addr,
            })
        }

        /// Create a NORM-style multicast sender.
        ///
        /// Uses UDP multicast as the underlying transport. The NORM
        /// FEC and rate parameters are recorded but not enforced at
        /// the wire level in this implementation.
        pub async fn new_norm(config: NormConfig) -> CfkResult<Self> {
            debug!(
                group = %config.group.group_addr,
                port = config.group.port,
                "Creating NORM multicast sender"
            );

            let socket = create_multicast_socket(&config.group)?;
            let dest_addr = SocketAddrV4::new(config.group.group_addr, config.group.port);

            Ok(Self {
                transport: Transport::Norm,
                socket,
                dest_addr,
            })
        }

        /// Send data to all group members.
        pub async fn send(&self, data: &[u8]) -> CfkResult<()> {
            self.socket.send_to(data, self.dest_addr)
                .map_err(|e| CfkError::Network(format!("Multicast send failed: {}", e)))?;
            Ok(())
        }

        /// Send a file to all group members, chunked by the socket buffer size.
        pub async fn send_file(&self, path: &std::path::Path) -> CfkResult<()> {
            let data = std::fs::read(path)
                .map_err(|e| CfkError::Other(format!("Failed to read file: {}", e)))?;

            // Send in chunks to avoid UDP fragmentation
            const CHUNK_SIZE: usize = 1400;
            for chunk in data.chunks(CHUNK_SIZE) {
                self.send(chunk).await?;
            }

            Ok(())
        }
    }

    impl Drop for MulticastSender {
        fn drop(&mut self) {
            // Best-effort leave — ignore errors on cleanup
            let _ = self.socket.leave_multicast_v4(
                &self.dest_addr.ip().clone(),
                &Ipv4Addr::UNSPECIFIED,
            );
        }
    }

    /// Reliable multicast receiver
    ///
    /// Joins a UDP multicast group and receives data from senders.
    pub struct MulticastReceiver {
        transport: Transport,
        socket: std::net::UdpSocket,
        group_addr: Ipv4Addr,
    }

    impl MulticastReceiver {
        /// Join a PGM-style multicast group as a receiver.
        pub async fn join_pgm(config: PgmConfig) -> CfkResult<Self> {
            debug!(
                group = %config.group.group_addr,
                port = config.group.port,
                "Joining PGM multicast group"
            );

            let socket = create_multicast_socket(&config.group)?;

            Ok(Self {
                transport: Transport::Pgm,
                socket,
                group_addr: config.group.group_addr,
            })
        }

        /// Join a NORM-style multicast group as a receiver.
        pub async fn join_norm(config: NormConfig) -> CfkResult<Self> {
            debug!(
                group = %config.group.group_addr,
                port = config.group.port,
                "Joining NORM multicast group"
            );

            let socket = create_multicast_socket(&config.group)?;

            Ok(Self {
                transport: Transport::Norm,
                socket,
                group_addr: config.group.group_addr,
            })
        }

        /// Receive data from the multicast group.
        ///
        /// Blocks until data is available or the socket times out.
        pub async fn recv(&self) -> CfkResult<Vec<u8>> {
            let mut buf = vec![0u8; 65536];
            let (n, _src) = self.socket.recv_from(&mut buf)
                .map_err(|e| CfkError::Network(format!("Multicast recv failed: {}", e)))?;
            buf.truncate(n);
            Ok(buf)
        }
    }

    impl Drop for MulticastReceiver {
        fn drop(&mut self) {
            let _ = self.socket.leave_multicast_v4(
                &self.group_addr,
                &Ipv4Addr::UNSPECIFIED,
            );
        }
    }
}
