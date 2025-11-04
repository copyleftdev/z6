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
