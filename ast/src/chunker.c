#include "chunker.h"
#include <string.h>

// Find a declaration's body node. Checks the node itself, then descends one level
// into named children to unwrap nodes like `export_statement` (TS/JS) that carry
// the real declaration and its `body` field one level down.
static TSNode find_body(TSNode node) {
    TSNode body = ts_node_child_by_field_name(node, "body", 4);
    if (!ts_node_is_null(body)) return body;

    uint32_t n = ts_node_named_child_count(node);
    for (uint32_t i = 0; i < n; i++) {
        TSNode inner = ts_node_child_by_field_name(ts_node_named_child(node, i), "body", 4);
        if (!ts_node_is_null(inner)) return inner;
    }
    return body; // null
}

ChunkResult extract_chunks(const TSLanguage *language, const ChunkConfig *config, const char *source, uint32_t length) {
    // Initialize the parser and set the parser language
    TSParser *parser = ts_parser_new();
    ts_parser_set_language(parser, language);

    // Parse the source code and get the root node
    TSTree *tree = ts_parser_parse_string(parser, NULL, source, length);
    TSNode root = ts_tree_root_node(tree);

    uint32_t capacity = 16;
    Chunk *chunks = malloc(capacity * sizeof(Chunk));
    uint32_t count = 0;

    uint32_t child_count = ts_node_child_count(root);

    // Traverse the syntax tree and extract chunks based on the specified node types
    for (uint32_t i = 0; i < child_count; i++) {
        TSNode child = ts_node_child(root, i);
        const char *type = ts_node_type(child);

        for (uint32_t j = 0; j < config->node_type_count; j++) {
            if (strcmp(type, config->node_types[j]) == 0) {
                // Increase capacity if needed
                if (count == capacity) {
                    capacity *= 2;
                    chunks = realloc(chunks, capacity * sizeof(Chunk));
                }

                uint32_t start_byte = ts_node_start_byte(child);
                TSNode body = find_body(child);

                chunks[count].start_line = ts_node_start_point(child).row;
                chunks[count].end_line = ts_node_end_point(child).row;
                chunks[count].start_byte = start_byte;
                // Signature is [node start .. body start). No body node (imports, aliases,
                // prototypes, or grammars without a `body` field) => sentinel; caller falls back.
                chunks[count].sig_end_byte = ts_node_is_null(body) ? start_byte : ts_node_start_byte(body);
                count++;
                break;
            }
        }
    }

    ts_tree_delete(tree);
    ts_parser_delete(parser);

    return (ChunkResult){.chunks = chunks, .count = count};
}

void free_chunk_result(ChunkResult result) {
    free(result.chunks);
}
