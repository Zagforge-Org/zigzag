/// Facade — re-exports the public surface used by runner.zig and watch.zig.
pub const ReportData = @import("report/aggregator/aggregator.zig").ReportData;
pub const resolveOutputPath = @import("report/paths/paths.zig").resolveOutputPath;
pub const deriveJsonPath = @import("report/paths/paths.zig").deriveJsonPath;
pub const deriveHtmlPath = @import("report/paths/paths.zig").deriveHtmlPath;
pub const deriveLlmPath = @import("report/paths/paths.zig").deriveLlmPath;
pub const writeReport = @import("report/writers/markdown/markdown.zig").writeReport;
pub const writeJsonReport = @import("report/writers/json/json.zig").writeJsonReport;
pub const writeHtmlReport = @import("report/writers/html/html.zig").writeHtmlReport;
pub const writeLlmReport = @import("report/writers/llm/llm.zig").writeLlmReport;
pub const buildSsePayload = @import("report/writers/sse/sse.zig").buildSsePayload;
