/// Facade — re-exports ReportData for writer sub-modules that import ../aggregator.zig.
pub const LanguageStat = @import("../aggregator/ReportData.zig").LanguageStat;
pub const ReportData = @import("../aggregator/ReportData.zig");
