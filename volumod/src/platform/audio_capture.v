// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VoluMod Platform Capture — PipeWire / PulseAudio audio capture integration.
//
// Detects the active Linux audio system (PipeWire preferred, PulseAudio fallback)
// and spawns `pw-record` or `parec` to capture system audio into an AudioBuffer
// that the VoluMod processing pipeline consumes.  Loopback capture is supported
// via PipeWire's monitor sources or PulseAudio's `.monitor` sinks.
//
// Architecture:
//   detect_audio_system() -> AudioSystem enum
//   PlatformCapture wraps the subprocess handle and ring-buffer
//   start_capture()  -> spawns pw-record / parec, feeds ring buffer
//   read_buffer()    -> drains ring buffer into core.AudioBuffer
//   stop_capture()   -> kills subprocess, cleans up

module platform

import os
import ..core

// ────────────────────────────────────────────────────────────────────
// Audio System Detection
// ────────────────────────────────────────────────────────────────────

// AudioSystem represents which Linux audio subsystem is available.
pub enum AudioSystem {
	pipewire    // PipeWire (preferred — modern, low-latency)
	pulseaudio  // PulseAudio (fallback — widespread, stable)
	none        // Neither found — capture unavailable
}

// detect_audio_system probes the host for PipeWire first, then PulseAudio.
// Returns the best available AudioSystem variant.
//
// Detection strategy:
//   1. Run `pw-cli info 0` — if exit-code 0, PipeWire is running.
//   2. Run `pactl info`    — if exit-code 0, PulseAudio is running.
//   3. Otherwise return .none.
pub fn detect_audio_system() AudioSystem {
	// Attempt PipeWire detection via pw-cli
	pw_result := os.execute('pw-cli info 0 2>/dev/null')
	if pw_result.exit_code == 0 {
		return .pipewire
	}

	// Attempt PulseAudio detection via pactl
	pa_result := os.execute('pactl info 2>/dev/null')
	if pa_result.exit_code == 0 {
		return .pulseaudio
	}

	return .none
}

// audio_system_name returns a human-readable name for the audio system.
pub fn audio_system_name(system AudioSystem) string {
	return match system {
		.pipewire { 'PipeWire' }
		.pulseaudio { 'PulseAudio' }
		.none { 'None' }
	}
}

// ────────────────────────────────────────────────────────────────────
// Device Enumeration (real system queries)
// ────────────────────────────────────────────────────────────────────

// enumerate_pipewire_sinks lists PipeWire output sinks via `pw-cli list-objects`.
// Returns a list of AudioDevice structs populated from actual system state.
fn enumerate_pipewire_sinks() []AudioDevice {
	mut devices := []AudioDevice{}

	// List audio sinks (output devices)
	result := os.execute('pw-cli list-objects Node 2>/dev/null')
	if result.exit_code != 0 {
		return devices
	}

	// Parse pw-cli output for sink nodes.
	// Each node block contains id, node.name, node.description, media.class.
	// We look for Audio/Sink nodes (output) and Audio/Source nodes (input).
	mut current_id := ''
	mut current_name := ''
	mut current_class := ''

	for line in result.output.split_into_lines() {
		trimmed := line.trim_space()

		if trimmed.starts_with('id ') {
			// Flush previous device if it was a sink
			if current_id.len > 0 && current_class.contains('Sink') {
				devices << AudioDevice{
					id: 'pw_sink_${current_id}'
					name: if current_name.len > 0 { current_name } else { 'PipeWire Sink ${current_id}' }
					device_type: .output
					is_default: false
					sample_rates: [u32(44100), 48000, 96000]
					max_channels: 2
					min_buffer_size: 64
					max_buffer_size: 4096
				}
			}
			// Start new device block
			current_id = trimmed.all_after('id ').trim_space().split(',')[0] or { '' }
			current_name = ''
			current_class = ''
		} else if trimmed.starts_with('node.description') || trimmed.starts_with('node.name') {
			// Extract the quoted value
			if trimmed.contains('=') {
				val := trimmed.all_after('=').trim_space().trim('"')
				if current_name.len == 0 {
					current_name = val
				}
			}
		} else if trimmed.starts_with('media.class') {
			if trimmed.contains('=') {
				current_class = trimmed.all_after('=').trim_space().trim('"')
			}
		}
	}

	// Flush last device
	if current_id.len > 0 && current_class.contains('Sink') {
		devices << AudioDevice{
			id: 'pw_sink_${current_id}'
			name: if current_name.len > 0 { current_name } else { 'PipeWire Sink ${current_id}' }
			device_type: .output
			is_default: false
			sample_rates: [u32(44100), 48000, 96000]
			max_channels: 2
			min_buffer_size: 64
			max_buffer_size: 4096
		}
	}

	return devices
}

// enumerate_pulseaudio_sinks lists PulseAudio sinks via `pactl list short sinks`.
fn enumerate_pulseaudio_sinks() []AudioDevice {
	mut devices := []AudioDevice{}

	result := os.execute('pactl list short sinks 2>/dev/null')
	if result.exit_code != 0 {
		return devices
	}

	// pactl list short sinks output format:
	//   <index>\t<name>\t<module>\t<sample-spec>\t<state>
	for line in result.output.split_into_lines() {
		parts := line.split('\t')
		if parts.len >= 2 {
			sink_index := parts[0].trim_space()
			sink_name := parts[1].trim_space()

			devices << AudioDevice{
				id: 'pa_sink_${sink_index}'
				name: sink_name
				device_type: .output
				is_default: false
				sample_rates: [u32(44100), 48000]
				max_channels: 2
				min_buffer_size: 128
				max_buffer_size: 4096
			}
		}
	}

	return devices
}

// get_default_monitor_source returns the monitor source name for loopback capture.
// PipeWire: uses the default sink's monitor port.
// PulseAudio: appends ".monitor" to the default sink name.
fn get_default_monitor_source(system AudioSystem) string {
	match system {
		.pipewire {
			// PipeWire exposes monitors via pw-record --target <node-id>
			// Get default sink node id
			result := os.execute("pw-dump 2>/dev/null | grep -A5 '\"default.audio.sink\"' | head -1")
			if result.exit_code == 0 && result.output.len > 0 {
				// Fallback: use the special "@DEFAULT_AUDIO_SINK@" target
				return '@DEFAULT_AUDIO_SINK@'
			}
			return '@DEFAULT_AUDIO_SINK@'
		}
		.pulseaudio {
			// Get the default sink name, then append .monitor
			result := os.execute('pactl get-default-sink 2>/dev/null')
			if result.exit_code == 0 {
				sink_name := result.output.trim_space()
				if sink_name.len > 0 {
					return '${sink_name}.monitor'
				}
			}
			// Fallback to a common default
			return 'alsa_output.pci-0000_00_1f.3.analog-stereo.monitor'
		}
		.none {
			return ''
		}
	}
}

// ────────────────────────────────────────────────────────────────────
// Audio Device Types (original types retained for compatibility)
// ────────────────────────────────────────────────────────────────────

// AudioDeviceType represents the type of audio device.
pub enum AudioDeviceType {
	output    // Playback device (speakers, headphones)
	input     // Recording device (microphone)
	loopback  // System audio capture (monitor source)
}

// AudioDevice represents an audio device discovered on the system.
pub struct AudioDevice {
pub:
	id              string
	name            string
	device_type     AudioDeviceType
	is_default      bool
	sample_rates    []u32
	max_channels    u8
	min_buffer_size u32
	max_buffer_size u32
}

// AudioStreamConfig holds audio stream configuration for capture.
pub struct AudioStreamConfig {
pub mut:
	sample_rate   u32
	channels      u8
	buffer_size   u32
	bit_depth     u8
	interleaved   bool
}

// default_stream_config returns sensible defaults for audio capture.
// 48 kHz / stereo / 512-frame buffer / 32-bit float / interleaved.
pub fn default_stream_config() AudioStreamConfig {
	return AudioStreamConfig{
		sample_rate: 48000
		channels: 2
		buffer_size: 512
		bit_depth: 32
		interleaved: true
	}
}

// AudioCallback is called for each captured audio buffer, providing both
// the raw input from the capture source and a mutable output buffer for
// the processed result.
pub type AudioCallback = fn (mut input core.AudioBuffer, mut output core.AudioBuffer)

// ────────────────────────────────────────────────────────────────────
// Capture State Machine
// ────────────────────────────────────────────────────────────────────

// AudioCaptureState represents the lifecycle state of a capture stream.
pub enum AudioCaptureState {
	stopped    // No capture subprocess running
	starting   // Spawning capture subprocess
	running    // Actively capturing audio
	stopping   // Tearing down capture subprocess
	error      // An error occurred — see error_message
}

// ────────────────────────────────────────────────────────────────────
// Ring Buffer — lock-free(ish) circular sample buffer
// ────────────────────────────────────────────────────────────────────

// RingBuffer is a fixed-size circular buffer of f32 samples.
// The capture subprocess writes raw PCM into this buffer;
// the processing thread drains it via read_buffer().
struct RingBuffer {
mut:
	data       []f32
	capacity   int
	write_pos  int
	read_pos   int
	count      int   // Number of samples currently buffered
}

// new_ring_buffer allocates a ring buffer with the given capacity in samples.
fn new_ring_buffer(capacity int) RingBuffer {
	return RingBuffer{
		data: []f32{len: capacity, init: 0.0}
		capacity: capacity
		write_pos: 0
		read_pos: 0
		count: 0
	}
}

// write_samples appends samples to the ring buffer.
// If the buffer is full, the oldest samples are silently overwritten
// (lossy — acceptable for real-time audio where stale data is worse
// than dropped data).
fn (mut rb RingBuffer) write_samples(samples []f32) int {
	mut written := 0
	for s in samples {
		rb.data[rb.write_pos] = s
		rb.write_pos = (rb.write_pos + 1) % rb.capacity
		if rb.count < rb.capacity {
			rb.count += 1
		} else {
			// Overwrite oldest — advance read_pos
			rb.read_pos = (rb.read_pos + 1) % rb.capacity
		}
		written += 1
	}
	return written
}

// read_samples drains up to `max_samples` from the ring buffer into a
// new slice. Returns an empty slice if the buffer is empty.
fn (mut rb RingBuffer) read_samples(max_samples int) []f32 {
	actual := if max_samples < rb.count { max_samples } else { rb.count }
	if actual == 0 {
		return []f32{}
	}

	mut result := []f32{len: actual}
	for i in 0 .. actual {
		result[i] = rb.data[rb.read_pos]
		rb.read_pos = (rb.read_pos + 1) % rb.capacity
	}
	rb.count -= actual
	return result
}

// available returns the number of samples available to read.
fn (rb &RingBuffer) available() int {
	return rb.count
}

// reset zeroes the buffer and resets pointers.
fn (mut rb RingBuffer) reset() {
	rb.write_pos = 0
	rb.read_pos = 0
	rb.count = 0
}

// ────────────────────────────────────────────────────────────────────
// PlatformCapture — the real capture engine
// ────────────────────────────────────────────────────────────────────

// PlatformCapture manages a subprocess-based audio capture pipeline.
// It detects PipeWire or PulseAudio, spawns the appropriate recorder,
// reads raw PCM from its stdout, and feeds a ring buffer that the
// VoluMod processing loop drains via read_buffer().
pub struct PlatformCapture {
pub mut:
	state          AudioCaptureState
	config         AudioStreamConfig
	audio_system   AudioSystem
	error_message  string
	// Path to the temporary FIFO / file used for capture data exchange
	capture_path   string
mut:
	ring           RingBuffer
	// Process handle for pw-record / parec subprocess
	capture_pid    int
	monitor_source string
}

// new_platform_capture creates a new PlatformCapture instance.
// It immediately detects the available audio system but does not start
// capturing until start_capture() is called.
pub fn new_platform_capture() PlatformCapture {
	system := detect_audio_system()
	cfg := default_stream_config()

	// Ring buffer holds 1 second of audio at the configured rate
	ring_capacity := int(cfg.sample_rate) * int(cfg.channels)

	return PlatformCapture{
		state: .stopped
		config: cfg
		audio_system: system
		error_message: ''
		capture_path: '/tmp/volumod_capture.raw'
		ring: new_ring_buffer(ring_capacity)
		capture_pid: 0
		monitor_source: get_default_monitor_source(system)
	}
}

// build_capture_command constructs the shell command for the detected
// audio system.  Both `pw-record` and `parec` are told to output raw
// 32-bit-float little-endian PCM to a named file that we poll.
//
// PipeWire command:
//   pw-record --target=@DEFAULT_AUDIO_SINK@ \
//             --format=f32 --rate=48000 --channels=2 <path>
//
// PulseAudio command:
//   parec --format=float32le --rate=48000 --channels=2 \
//         -d <monitor-source> > <path>
fn (pc &PlatformCapture) build_capture_command() string {
	rate := pc.config.sample_rate
	channels := pc.config.channels

	match pc.audio_system {
		.pipewire {
			return 'pw-record --target=${pc.monitor_source} --format=f32 --rate=${rate} --channels=${channels} ${pc.capture_path}'
		}
		.pulseaudio {
			return 'parec --format=float32le --rate=${rate} --channels=${channels} -d ${pc.monitor_source} > ${pc.capture_path}'
		}
		.none {
			return ''
		}
	}
}

// start_capture begins audio capture from the system's loopback/monitor
// source.  On success the state transitions to .running and the capture
// subprocess PID is stored for later teardown.
//
// Returns true if capture started successfully, false otherwise (with
// error_message populated).
pub fn (mut pc PlatformCapture) start_capture() bool {
	if pc.state == .running {
		return true
	}

	if pc.audio_system == .none {
		pc.state = .error
		pc.error_message = 'No audio system detected (neither PipeWire nor PulseAudio found)'
		return false
	}

	pc.state = .starting

	// Remove stale capture file
	os.rm(pc.capture_path) or {}

	// Build and spawn the capture command in the background
	cmd := pc.build_capture_command()
	if cmd.len == 0 {
		pc.state = .error
		pc.error_message = 'Failed to build capture command'
		return false
	}

	// Spawn the capture process in the background via sh -c "... &"
	// and record its PID for later teardown.
	bg_cmd := '${cmd} & echo $$!'
	spawn_result := os.execute('sh -c \'${bg_cmd}\' 2>/dev/null')

	if spawn_result.exit_code != 0 {
		pc.state = .error
		pc.error_message = 'Failed to spawn capture process: ${spawn_result.output}'
		return false
	}

	// Parse PID from the spawn output
	pid_str := spawn_result.output.trim_space()
	pc.capture_pid = pid_str.int()

	// Reset ring buffer for fresh capture
	pc.ring.reset()

	pc.state = .running
	return true
}

// poll_capture reads any new raw PCM data from the capture file and
// feeds it into the internal ring buffer.  This should be called
// periodically from the processing loop (e.g., once per buffer cycle).
//
// Returns the number of new samples ingested.
pub fn (mut pc PlatformCapture) poll_capture() int {
	if pc.state != .running {
		return 0
	}

	// Read raw bytes from the capture file
	raw_bytes := os.read_bytes(pc.capture_path) or { return 0 }
	if raw_bytes.len == 0 {
		return 0
	}

	// Convert raw bytes to f32 samples (little-endian IEEE 754)
	// Each sample is 4 bytes (32-bit float)
	num_samples := raw_bytes.len / 4
	if num_samples == 0 {
		return 0
	}

	mut samples := []f32{len: num_samples}
	for i in 0 .. num_samples {
		offset := i * 4
		if offset + 4 <= raw_bytes.len {
			// Reinterpret 4 bytes as little-endian f32
			bits := u32(raw_bytes[offset]) |
				(u32(raw_bytes[offset + 1]) << 8) |
				(u32(raw_bytes[offset + 2]) << 16) |
				(u32(raw_bytes[offset + 3]) << 24)
			unsafe {
				samples[i] = *(&f32(&bits))
			}
		}
	}

	return pc.ring.write_samples(samples)
}

// read_buffer drains the ring buffer into a core.AudioBuffer suitable
// for the VoluMod processing pipeline.
//
// If fewer than `frame_count * channels` samples are available, the
// returned buffer is zero-padded (silence-filled) to maintain the
// expected frame count — this prevents downstream buffer-size
// assumptions from breaking.
pub fn (mut pc PlatformCapture) read_buffer(frame_count u32) core.AudioBuffer {
	total_samples := int(frame_count) * int(pc.config.channels)
	raw := pc.ring.read_samples(total_samples)

	mut buf := core.new_audio_buffer(pc.config.sample_rate, pc.config.channels, frame_count)

	// Copy available samples into the AudioBuffer
	copy_len := if raw.len < buf.samples.len { raw.len } else { buf.samples.len }
	for i in 0 .. copy_len {
		buf.samples[i] = raw[i]
	}
	// Remaining samples stay at 0.0 (silence padding)

	return buf
}

// stop_capture terminates the capture subprocess and cleans up resources.
pub fn (mut pc PlatformCapture) stop_capture() bool {
	if pc.state == .stopped {
		return true
	}

	pc.state = .stopping

	// Kill the capture subprocess if we have a PID
	if pc.capture_pid > 0 {
		os.execute('kill ${pc.capture_pid} 2>/dev/null')
		pc.capture_pid = 0
	}

	// Clean up the capture file
	os.rm(pc.capture_path) or {}

	// Reset ring buffer
	pc.ring.reset()

	pc.state = .stopped
	return true
}

// is_running returns whether capture is actively running.
pub fn (pc &PlatformCapture) is_running() bool {
	return pc.state == .running
}

// get_latency_ms returns the estimated capture latency in milliseconds.
// This accounts for the buffer size and sample rate.
pub fn (pc &PlatformCapture) get_latency_ms() f32 {
	if pc.config.sample_rate == 0 {
		return 0.0
	}
	return f32(pc.config.buffer_size) / f32(pc.config.sample_rate) * 1000.0
}

// buffered_frames returns how many complete frames are currently in the
// ring buffer, available for read_buffer().
pub fn (pc &PlatformCapture) buffered_frames() u32 {
	if pc.config.channels == 0 {
		return 0
	}
	return u32(pc.ring.available() / int(pc.config.channels))
}

// ────────────────────────────────────────────────────────────────────
// Legacy AudioCapture API (retained for backward compatibility)
// ────────────────────────────────────────────────────────────────────
// The original stub types are preserved so that existing code referencing
// AudioCapture / SystemAudioCapture continues to compile.  Internally
// they now delegate to PlatformCapture for real audio I/O.

// AudioCapture provides cross-platform audio capture and playback.
// Legacy wrapper — new code should use PlatformCapture directly.
pub struct AudioCapture {
pub mut:
	state          AudioCaptureState
	config         AudioStreamConfig
	output_device  ?AudioDevice
	input_device   ?AudioDevice
	error_message  string
mut:
	callback       ?AudioCallback
	platform       PlatformCapture
}

// new_audio_capture creates a new audio capture instance backed by
// real PipeWire / PulseAudio integration.
pub fn new_audio_capture() AudioCapture {
	return AudioCapture{
		state: .stopped
		config: default_stream_config()
		output_device: none
		input_device: none
		error_message: ''
		callback: none
		platform: new_platform_capture()
	}
}

// enumerate_devices lists available audio devices by querying the
// detected audio system (PipeWire or PulseAudio).  Falls back to
// a minimal set of placeholder devices if neither system provides
// usable output.
pub fn (ac &AudioCapture) enumerate_devices() []AudioDevice {
	mut devices := []AudioDevice{}

	match ac.platform.audio_system {
		.pipewire {
			devices = enumerate_pipewire_sinks()
		}
		.pulseaudio {
			devices = enumerate_pulseaudio_sinks()
		}
		.none {}
	}

	// If real enumeration returned nothing, provide a minimal fallback
	// so that callers always have at least one device to select.
	if devices.len == 0 {
		devices << AudioDevice{
			id: 'default_output'
			name: 'Default Output Device'
			device_type: .output
			is_default: true
			sample_rates: [u32(44100), 48000, 96000]
			max_channels: 2
			min_buffer_size: 64
			max_buffer_size: 4096
		}
	}

	// Always add a loopback device for system audio capture
	devices << AudioDevice{
		id: 'system_loopback'
		name: 'System Audio (Loopback via ${audio_system_name(ac.platform.audio_system)})'
		device_type: .loopback
		is_default: false
		sample_rates: [u32(44100), 48000]
		max_channels: 2
		min_buffer_size: 256
		max_buffer_size: 4096
	}

	return devices
}

// set_output_device sets the output device by ID.
pub fn (mut ac AudioCapture) set_output_device(device_id string) bool {
	devices := ac.enumerate_devices()
	for d in devices {
		if d.id == device_id && (d.device_type == .output) {
			ac.output_device = d
			return true
		}
	}
	return false
}

// set_input_device sets the input device by ID.
pub fn (mut ac AudioCapture) set_input_device(device_id string) bool {
	devices := ac.enumerate_devices()
	for d in devices {
		if d.id == device_id && (d.device_type == .input || d.device_type == .loopback) {
			ac.input_device = d
			return true
		}
	}
	return false
}

// set_callback sets the audio processing callback that is invoked for
// each captured buffer.
pub fn (mut ac AudioCapture) set_callback(callback AudioCallback) {
	ac.callback = callback
}

// start begins audio streaming by launching the platform capture
// subprocess.
pub fn (mut ac AudioCapture) start() bool {
	if ac.state == .running {
		return true
	}

	ac.state = .starting

	// Start the real platform capture
	if !ac.platform.start_capture() {
		ac.state = .error
		ac.error_message = ac.platform.error_message
		return false
	}

	ac.state = .running
	return true
}

// stop stops audio streaming and kills the capture subprocess.
pub fn (mut ac AudioCapture) stop() bool {
	if ac.state == .stopped {
		return true
	}

	ac.state = .stopping
	ac.platform.stop_capture()
	ac.state = .stopped
	return true
}

// is_running returns whether the capture stream is active.
pub fn (ac &AudioCapture) is_running() bool {
	return ac.state == .running
}

// get_latency returns the current audio latency in milliseconds.
pub fn (ac &AudioCapture) get_latency() f32 {
	return ac.platform.get_latency_ms()
}

// ────────────────────────────────────────────────────────────────────
// SystemAudioCapture — system-wide capture (loopback/passthrough)
// ────────────────────────────────────────────────────────────────────

// CaptureMode defines how system audio is captured and routed.
pub enum CaptureMode {
	loopback     // Capture system audio output (read-only)
	inject       // Inject processed audio back into the system
	passthrough  // Capture, process, and re-inject (full pipeline)
}

// SystemAudioCapture provides system-wide audio capture by wrapping
// AudioCapture with loopback-specific configuration.
pub struct SystemAudioCapture {
	AudioCapture
pub mut:
	capture_mode  CaptureMode
}

// new_system_audio_capture creates a system-wide audio capture instance
// with the specified mode.
pub fn new_system_audio_capture(mode CaptureMode) SystemAudioCapture {
	return SystemAudioCapture{
		AudioCapture: new_audio_capture()
		capture_mode: mode
	}
}

// start_system_capture begins system-wide audio capture via loopback.
// Selects the appropriate monitor source based on the detected audio
// system and starts the capture subprocess.
pub fn (mut sac SystemAudioCapture) start_system_capture() bool {
	// Configure for loopback capture
	sac.set_input_device('system_loopback')
	sac.set_output_device('default_output')

	return sac.start()
}
