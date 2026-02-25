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
│   ├── test.json
│   └── medium-test.json
├── benchmark/
│   ├── run.sh
│   ├── generate_data.py
│   └── results/
└── README.md
```

---

## Features

- **Document Parsing**: JSON array, single JSON, plain text, new format with metadata wrapper
- **Text Chunking**: 512 words per chunk, 50 word overlap
- **Embedding Generation**: 384-dimensional vectors (FNV hash-based for benchmarking)
- **Test Data Generation**: Python script for realistic test data (100-10,000 docs)
- **Statistics**: Processing time, throughput, latency, document/chunk counts
- **Docker Support**: Multi-stage builds for all languages

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
./zig-out/bin/vdi-zig ../test-data/test.json
```

### Test Data Generation

Generate realistic test data for benchmarking:

```bash
# Small dataset (100 docs, ~200KB)
python3 benchmark/generate_data.py --small --output test-data/small-test.json

# Medium dataset (500 docs, ~2.8MB) - default for benchmark
python3 benchmark/generate_data.py --medium --output test-data/medium-test.json

# Large dataset (1000 docs, ~5.6MB)
python3 benchmark/generate_data.py --docs 1000 --output test-data/large-test.json

# Custom size
python3 benchmark/generate_data.py --docs 2000 --min-words 200 --max-words 3000
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

### Benchmark Results (500 docs, 924 chunks, 2.8MB)

| Metric | Go | **Rust** | **Zig** 🏆 |
|--------|-----|----------|-----------|
| **Throughput** | 23,157 chunks/s | 30,832 chunks/s | **36,162 chunks/s** |
| **Avg Latency** | 0.043ms | 0.032ms | **0.028ms** |
| **Processing Time** | 0.040s | 0.030s | **0.026s** |
| **Speedup vs Go** | 1.0x | 1.33x | **1.56x** |

### Language Comparison

| Aspect | Go | Rust | Zig |
|--------|-----|------|-----|
| **Performance** | Good (baseline) | Better (1.33x) | **Best (1.56x)** |
| **Memory Model** | Garbage Collection | Ownership + Borrowing | Manual Management |
| **Code Complexity** | Simple (205 lines) | Moderate (243 lines) | Complex (176 lines) |
| **Build Time** | Fastest | Slowest | Fast |
| **Binary Size** | Medium | Small | Small |
| **API Stability** | Stable | Stable | Changing (0.15) |

### Key Insights

- **Zig** wins with manual memory management and zero GC overhead
- **Rust** provides good balance of safety and performance  
- **Go** is easiest to write but suffers from GC pressure
- **Test data size matters**: Larger datasets show clearer performance differences

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
