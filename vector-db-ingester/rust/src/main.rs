use serde::{Deserialize, Serialize};
use std::time::Instant;

const CHUNK_SIZE: usize = 512;
const CHUNK_OVERLAP: usize = 50;
const EMBEDDING_DIM: usize = 384;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Config {
    input_file: String,
    batch_size: usize,
    dim_size: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            input_file: "test.json".to_string(),
            batch_size: 32,
            dim_size: 384,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Document {
    id: String,
    #[serde(rename = "content")]
    content: String,
    #[serde(rename = "type", default)]
    doc_type: String,
}

#[derive(Debug, Clone)]
struct Chunk {
    text: String,
    start_idx: usize,
    end_idx: usize,
    embedding: Vec<f32>,
}

#[derive(Debug, Clone)]
struct Stats {
    total_docs: usize,
    total_chunks: usize,
    processing_ns: u64,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_chunks == 0 {
            return 0.0;
        }
        (self.processing_ns as f64 / self.total_chunks as f64) / 1e6
    }

    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 {
            return 0.0;
        }
        (self.total_chunks as f64) / (self.processing_ns as f64 / 1e9)
    }
}

fn print_config(cfg: &Config) {
    println!("--- Configuration ---");
    println!("Input file: {}", cfg.input_file);
    println!("Batch size: {}", cfg.batch_size);
    println!("Embedding dimension: {}", cfg.dim_size);
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total documents: {}", s.total_docs);
    println!("Total chunks: {}", s.total_chunks);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1e9);
    println!("Average latency: {:.3}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} chunks/sec", s.throughput());
}

// Simple FNV hash
fn hash_string(s: &str) -> u64 {
    let mut h: u64 = 14695981039346656037; // FNV offset basis
    for byte in s.as_bytes() {
        h ^= *byte as u64;
        h = h.wrapping_mul(1099511628211); // FNV prime
    }
    h
}

// Generate simple embedding (same as Go version)
fn simple_embedding(text: &str, dim: usize) -> Vec<f32> {
    let text_hash = hash_string(text);
    let mut embedding = vec![0.0; dim];
    
    for i in 0..dim {
        embedding[i] = ((text_hash >> (i % 32)) & 0xFF) as f32 / 255.0;
    }
    
    embedding
}

// Split text into overlapping chunks
fn chunk_text(text: &str, chunk_size: usize, overlap: usize) -> Vec<Chunk> {
    let words: Vec<&str> = text.split_whitespace().collect();
    if words.is_empty() {
        return vec![];
    }
    
    let mut chunks: Vec<Chunk> = vec![];
    
    let mut i = 0;
    while i < words.len() {
        let end = (i + chunk_size).min(words.len());
        let chunk_text = words[i..end].join(" ");
        
        chunks.push(Chunk {
            text: chunk_text.clone(),
            start_idx: i,
            end_idx: end,
            embedding: simple_embedding(&chunk_text, EMBEDDING_DIM),
        });
        
        if end >= words.len() {
            break;
        }
        
        i += chunk_size - overlap;
    }
    
    chunks
}

// Parse input file (new format with metadata wrapper, or JSON array, or single document, or plain text)
fn parse_input_file(filename: &str) -> Result<Vec<Document>, String> {
    let data = std::fs::read(filename)
        .map_err(|e| format!("failed to read file: {}", e))?;
    
    // Try new format: {"metadata": {...}, "documents": [...]}
    #[derive(Deserialize)]
    struct NewFormat {
        documents: Vec<Document>,
    }
    if let Ok(new_format) = serde_json::from_slice::<NewFormat>(&data) {
        if !new_format.documents.is_empty() {
            return Ok(new_format.documents);
        }
    }
    
    // Try JSON array (old format)
    if let Ok(docs) = serde_json::from_slice::<Vec<Document>>(&data) {
        return Ok(docs);
    }
    
    // Try single document
    if let Ok(doc) = serde_json::from_slice::<Document>(&data) {
        return Ok(vec![doc]);
    }
    
    // Try plain text
    let content = String::from_utf8_lossy(&data);
    if !content.contains('{') {
        return Ok(vec![Document {
            id: "doc-1".to_string(),
            content: content.to_string(),
            doc_type: "txt".to_string(),
        }]);
    }
    
    Err("failed to parse input file".to_string())
}

fn main() {
    // Parse args
    let mut cfg = Config::default();
    
    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-input" | "--input" => {
                if i + 1 < args.len() {
                    cfg.input_file = args[i + 1].clone();
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "-batch" | "--batch" => {
                if i + 1 < args.len() {
                    cfg.batch_size = args[i + 1].parse().unwrap_or(32);
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "-dim" | "--dim" => {
                if i + 1 < args.len() {
                    cfg.dim_size = args[i + 1].parse().unwrap_or(384);
                    i += 2;
                } else {
                    i += 1;
                }
            }
            _ => i += 1,
        }
    }
    
    // Print config
    print_config(&cfg);
    
    // Start timer
    let start = Instant::now();
    
    // Parse input file
    let docs = match parse_input_file(&cfg.input_file) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("Error parsing input: {}", e);
            std::process::exit(1);
        }
    };
    
    // Process documents
    let mut all_chunks: Vec<Chunk> = vec![];
    for doc in &docs {
        let chunks = chunk_text(&doc.content, CHUNK_SIZE, CHUNK_OVERLAP);
        for chunk in chunks {
            all_chunks.push(Chunk {
                text: format!("{}: {}", doc.id, chunk.text),
                start_idx: chunk.start_idx,
                end_idx: chunk.end_idx,
                embedding: chunk.embedding,
            });
        }
    }
    
    let processing_time = start.elapsed();
    
    // Calculate stats
    let stats = Stats {
        total_docs: docs.len(),
        total_chunks: all_chunks.len(),
        processing_ns: processing_time.as_nanos() as u64,
    };
    
    // Print stats
    print_stats(&stats);
    
    // Explicitly flush stdout
    use std::io::Write;
    let _ = std::io::stdout().flush();
}
