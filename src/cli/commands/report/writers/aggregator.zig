/// Facade — re-exports ReportData for writer sub-modules that import ../aggregator.zig.
pub const LanguageStat = @import("../aggregator/aggregator.zig").LanguageStat;
pub const ReportData = @import("../aggregator/aggregator.zig").ReportData;
