#ifndef CHUNKER_H
#define CHUNKER_H
#include <stdint.h>
#include <tree_sitter/api.h>


typedef struct {
    uint32_t start_line;
    uint32_t end_line;
    uint32_t start_byte;
    uint32_t sig_end_byte; // byte where the body node begins; == start_byte when no AST body (caller falls back)
} Chunk;

typedef struct {
    const char **node_types;
    uint32_t node_type_count;
} ChunkConfig;

typedef struct {
    Chunk *chunks;
    uint32_t count;
} ChunkResult;



ChunkResult extract_chunks(const TSLanguage *language, const ChunkConfig *config, const char *source, uint32_t length);
void free_chunk_result(ChunkResult result);

#endif