//! Z6 Core Module
//!
//! This is the main module that exports all Z6 components.

pub const Arena = @import("arena.zig").Arena;
pub const Pool = @import("pool.zig").Pool;
pub const Memory = @import("memory.zig").Memory;
pub const PRNG = @import("prng.zig").PRNG;
pub const VU = @import("vu.zig").VU;
pub const VUState = @import("vu.zig").VUState;
pub const Scheduler = @import("scheduler.zig").Scheduler;
pub const SchedulerConfig = @import("scheduler.zig").SchedulerConfig;
pub const EventQueue = @import("event_queue.zig").EventQueue;

// Event model
pub const Event = @import("event.zig").Event;
pub const EventHeader = @import("event.zig").EventHeader;
pub const EventType = @import("event.zig").EventType;
pub const EventLog = @import("event_log.zig").EventLog;

// Event log constants and types
pub const EventLogHeader = @import("event_log.zig").Header;
pub const EventLogFooter = @import("event_log.zig").Footer;
pub const EVENT_LOG_MAGIC_NUMBER = @import("event_log.zig").MAGIC_NUMBER;
pub const EVENT_LOG_MAX_EVENTS = @import("event_log.zig").MAX_EVENTS;

// Protocol interface
pub const Protocol = @import("protocol.zig").Protocol;
pub const Target = @import("protocol.zig").Target;
pub const Method = @import("protocol.zig").Method;
pub const Header = @import("protocol.zig").Header;
pub const RequestId = @import("protocol.zig").RequestId;
pub const Request = @import("protocol.zig").Request;
pub const ProtocolError = @import("protocol.zig").ProtocolError;
pub const NetworkError = @import("protocol.zig").NetworkError;
pub const Status = @import("protocol.zig").Status;
pub const Response = @import("protocol.zig").Response;
pub const ConnectionId = @import("protocol.zig").ConnectionId;
pub const CompletionResult = @import("protocol.zig").CompletionResult;
pub const Completion = @import("protocol.zig").Completion;
pub const CompletionQueue = @import("protocol.zig").CompletionQueue;
pub const ProtocolConfig = @import("protocol.zig").ProtocolConfig;
pub const HTTPConfig = @import("protocol.zig").HTTPConfig;
pub const HTTPVersion = @import("protocol.zig").HTTPVersion;
pub const ProtocolHandler = @import("protocol.zig").ProtocolHandler;

// HTTP/1.1 Parser
pub const HTTP1Parser = @import("http1_parser.zig").HTTP1Parser;
pub const ParseResult = @import("http1_parser.zig").ParseResult;
pub const ParserError = @import("http1_parser.zig").ParserError;

// HTTP/1.1 Handler
pub const HTTP1Handler = @import("http1_handler.zig").HTTP1Handler;
pub const createHTTP1Handler = @import("http1_handler.zig").createHandler;

// Scenario Parser
pub const Scenario = @import("scenario.zig").Scenario;
pub const ScenarioParser = @import("scenario.zig").ScenarioParser;
pub const ScenarioError = @import("scenario.zig").ScenarioError;
pub const RequestDef = @import("scenario.zig").RequestDef;
pub const ScenarioRuntime = @import("scenario.zig").Runtime;
pub const ScenarioTarget = @import("scenario.zig").ScenarioTarget;

// CLI Module
pub const ExitCode = @import("cli.zig").ExitCode;
pub const OutputFormat = @import("cli.zig").OutputFormat;
pub const ProgressIndicator = @import("cli.zig").ProgressIndicator;
pub const SignalHandler = @import("cli.zig").SignalHandler;

// Output Formatters
pub const TestResult = @import("output.zig").TestResult;
pub const formatJSON = @import("output.zig").formatJSON;
pub const formatCSV = @import("output.zig").formatCSV;
pub const formatCSVHeader = @import("output.zig").formatCSVHeader;
pub const formatSummary = @import("output.zig").formatSummary;

// HTTP/2 Frame Parser
pub const HTTP2FrameParser = @import("http2_frame.zig").HTTP2FrameParser;
pub const HTTP2FrameType = @import("http2_frame.zig").FrameType;
pub const HTTP2Frame = @import("http2_frame.zig").Frame;
pub const HTTP2FrameHeader = @import("http2_frame.zig").FrameHeader;
pub const HTTP2FrameError = @import("http2_frame.zig").FrameError;
pub const HTTP2SettingsParameter = @import("http2_frame.zig").SettingsParameter;
pub const HTTP2FrameFlags = @import("http2_frame.zig").FrameFlags;
pub const HTTP2PriorityPayload = @import("http2_frame.zig").PriorityPayload;
pub const HTTP2GoawayPayload = @import("http2_frame.zig").GoawayPayload;
pub const HTTP2HeadersPayload = @import("http2_frame.zig").HeadersPayload;
pub const HTTP2ContinuationPayload = @import("http2_frame.zig").ContinuationPayload;
pub const HTTP2ErrorCode = @import("http2_frame.zig").ErrorCode;
pub const HTTP2_CONNECTION_PREFACE = @import("http2_frame.zig").CONNECTION_PREFACE;

// HTTP/2 Frame Serialization
pub const HTTP2Settings = @import("http2_frame.zig").Settings;
pub const serializeFrameHeader = @import("http2_frame.zig").serializeFrameHeader;
pub const serializeSettingsFrame = @import("http2_frame.zig").serializeSettingsFrame;
pub const serializeSettingsAck = @import("http2_frame.zig").serializeSettingsAck;
pub const serializeDataFrame = @import("http2_frame.zig").serializeDataFrame;
pub const serializeHeadersFrame = @import("http2_frame.zig").serializeHeadersFrame;
pub const serializePingFrame = @import("http2_frame.zig").serializePingFrame;
pub const serializeWindowUpdateFrame = @import("http2_frame.zig").serializeWindowUpdateFrame;
pub const serializeGoawayFrame = @import("http2_frame.zig").serializeGoawayFrame;
pub const serializeRstStreamFrame = @import("http2_frame.zig").serializeRstStreamFrame;

// HPACK Header Compression
pub const HPACKEncoder = @import("http2_hpack.zig").HPACKEncoder;
pub const HPACKDecoder = @import("http2_hpack.zig").HPACKDecoder;
pub const HPACKHeader = @import("http2_hpack.zig").Header;
pub const HPACKError = @import("http2_hpack.zig").HPACKError;
pub const encodeRequestHeaders = @import("http2_hpack.zig").encodeRequestHeaders;

// HTTP/2 Handler
pub const HTTP2Handler = @import("http2_handler.zig").HTTP2Handler;
pub const HTTP2Error = @import("http2_handler.zig").HTTP2Error;
pub const createHTTP2Handler = @import("http2_handler.zig").createHandler;
pub const HTTP2_MAX_CONNECTIONS = @import("http2_handler.zig").MAX_CONNECTIONS;
pub const HTTP2_MAX_STREAMS = @import("http2_handler.zig").MAX_STREAMS;

// VU Execution Engine
pub const VUEngine = @import("vu_engine.zig").VUEngine;
pub const EngineConfig = @import("vu_engine.zig").EngineConfig;
pub const EngineError = @import("vu_engine.zig").EngineError;
pub const VUContext = @import("vu_engine.zig").VUContext;
pub const VU_ENGINE_MAX_VUS = @import("vu_engine.zig").MAX_VUS;
pub const DEFAULT_THINK_TIME_TICKS = @import("vu_engine.zig").DEFAULT_THINK_TIME_TICKS;

// HDR Histogram
pub const HdrHistogram = @import("hdr_histogram.zig").HdrHistogram;
pub const HdrError = @import("hdr_histogram.zig").HdrError;

// Metrics Reducer
pub const MetricsReducer = @import("metrics.zig").MetricsReducer;
pub const Metrics = @import("metrics.zig").Metrics;
pub const RequestMetrics = @import("metrics.zig").RequestMetrics;
pub const LatencyMetrics = @import("metrics.zig").LatencyMetrics;
pub const ThroughputMetrics = @import("metrics.zig").ThroughputMetrics;
pub const ConnectionMetrics = @import("metrics.zig").ConnectionMetrics;
pub const ErrorMetrics = @import("metrics.zig").ErrorMetrics;
pub const RequestPayload = @import("metrics.zig").RequestPayload;
pub const ResponsePayload = @import("metrics.zig").ResponsePayload;
pub const ConnectionPayload = @import("metrics.zig").ConnectionPayload;
pub const reduce = @import("metrics.zig").reduce;
