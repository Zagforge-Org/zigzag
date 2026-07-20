//! HTML report writer public surface. Implementation is split across:
//!   json.zig      - JSON section writers for the dashboard payload
//!   dashboard.zig - the self-contained HTML dashboards
//!   content.zig   - source-content sidecars and the watch-mode stamp
const dashboard = @import("dashboard.zig");
const content = @import("content.zig");

pub const writeHtmlReport = dashboard.writeHtmlReport;
pub const writeCombinedHtmlReport = dashboard.writeCombinedHtmlReport;
pub const CombinedPathData = dashboard.CombinedPathData;

pub const writeContentJson = content.writeContentJson;
pub const writeCombinedContentJson = content.writeCombinedContentJson;
pub const writeContentFiles = content.writeContentFiles;
pub const writeChangedContentFiles = content.writeChangedContentFiles;
pub const writeCombinedContentFiles = content.writeCombinedContentFiles;
pub const writeCombinedChangedContentFiles = content.writeCombinedChangedContentFiles;
pub const writeStampFile = content.writeStampFile;
pub const CombinedContentPath = content.CombinedContentPath;
