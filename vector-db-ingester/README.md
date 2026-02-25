# Vector DB Ingester

A high-performance document processing pipeline that converts documents into vector embeddings for vector databases. This project compares implementations across Go, Rust, and Zig.

## Objective

Build a document ingester that:
1. Reads documents (TXT, JSON, Markdown)
2. Chunks text into overlapping segments
3. Generates vector embeddings
4. Outputs processing statistics

This project focuses on **Memory Management** - handling large document processing efficiently across different memory models.

---

## Project Structure

```
vector-db-ingester/
├── go/
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/
│   │   └── main.rs
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/
│   │   └── main.zig
│   ├── build.zig
│   └── Dockerfile
├── test-data/
│   └── test.json
├── benchmark/
│   └── run.sh
└── README.md
```

---

## Features

- **Document Parsing**: JSON array, single JSON, plain text
- **Text Chunking**: 512 tokens per chunk, 50 token overlap
- **Embedding Generation**: 384-dimensional vectors (hash-based for benchmarking)
- **Statistics**: Processing time, throughput, latency

---

## Build & Run

### Prerequisites

| Language | Requirement |
|----------|-------------|
| Go | Go 1.23+ |
| Rust | Rust 1.85+ |
| Zig | Zig 0.15+ |

### Local Development

**Go:**
```bash
cd go
go build -o vdi-go .
./vdi-go -input ../test-data/test.json
```

**Rust:**
```bash
cd rust
cargo build --release
./target/release/vdi-rust -input ../test-data/test.json
```

**Zig:**
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-0.15.2/zig build -Doptimize=ReleaseFast --run -- -input ../test-data/test.json
```

### Docker

```bash
# Build images
docker build -t vdi-go go/
docker build -t vdi-rust rust/
docker build -t vdi-zig zig/

# Run benchmarks
bash benchmark/run.sh
```

---

## Benchmark

Run benchmark via Docker:

```bash
bash benchmark/run.sh
```

### Metrics

| Metric | Description |
|--------|-------------|
| Processing time | Wall clock time (seconds) |
| Average latency | Time per chunk (ms) |
| Throughput | Chunks per second |
| Binary size | Compiled binary size |

---

## Comparison

| Aspect | Go | Rust | Zig |
|--------|-----|------|-----|
| **Performance** | TBD | TBD | TBD |
| **Binary Size** | TBD | TBD | TBD |
| **Memory** | GC | Ownership | Manual |
| **Lines of Code** | ~150 | ~180 | ~200 |

---

## Notes

### Embedding Approach

This implementation uses hash-based embeddings for fair language comparison:
- Same algorithm across all languages
- No external ML dependencies
- Demonstrates string processing and memory allocation

For production use, replace `simpleEmbedding()` with ONNX Runtime:
- Go: `github.com/yalue/onnxruntime`
- Rust: `ort` crate
- Zig: CGO or subprocess wrapper

### Chunking Strategy

- **Size**: 512 words
- **Overlap**: 50 words
- **Method**: Word-based splitting

---

## License

MIT
