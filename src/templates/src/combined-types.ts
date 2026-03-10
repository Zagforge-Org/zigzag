// src/templates/src/combined-types.ts

export interface CombinedLanguage {
    name: string;
    files: number;
    lines: number;
    size_bytes: number;
}

export interface CombinedFile {
    path: string;
    root_path: string;
    size: number;
    lines: number;
    language: string;
}

export interface CombinedBinary {
    path: string;
    size: number;
}

export interface CombinedPathSummary {
    source_files: number;
    binary_files: number;
    total_lines: number;
    total_size_bytes: number;
    languages: CombinedLanguage[];
}

export interface CombinedPathReport {
    root_path: string;
    summary: CombinedPathSummary;
    files: CombinedFile[];
    binaries: CombinedBinary[];
}

export interface CombinedGlobalSummary {
    source_files: number;
    binary_files: number;
    total_lines: number;
    total_size_bytes: number;
}

export interface CombinedMeta {
    combined: boolean;
    path_count: number;
    successful_paths: number;
    failed_paths: number;
    file_count: number;
    generated_at: string;
    version: string;
    watch_mode?: boolean;
    sse_url?: string;
}

export interface CombinedReport {
    meta: CombinedMeta;
    summary: CombinedGlobalSummary;
    paths: CombinedPathReport[];
}

declare global {
    interface Window {
        COMBINED_REPORT: CombinedReport;
    }
}
