export interface ReportLanguage {
    name: string;
    files: number;
    lines: number;
    size: number;
}

export interface ReportSummary {
    source_files: number;
    total_lines: number;
    binary_files: number;
    total_size_bytes: number;
    languages: ReportLanguage[];
}

export interface ReportFile {
    path: string;
    lines: number;
    size: number;
    language: string;
}

export interface ReportBinary {
    path: string;
    size: number;
}

export interface ReportMeta {
    root_path: string;
    generated_at: string;
    version: string;
    watch_mode: boolean;
    sse_url?: string; // absolute SSE endpoint URL, embedded when --watch --html active
}

export interface Report {
    meta: ReportMeta;
    summary: ReportSummary;
    files: ReportFile[];
    binaries: ReportBinary[];
}

declare global {
    interface Window {
        REPORT: Report;
    }
}
