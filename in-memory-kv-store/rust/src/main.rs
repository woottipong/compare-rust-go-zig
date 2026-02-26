use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Instant;
use clap::Parser;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(short, long, default_value = "10000")]
    operations: usize,
}

struct KVStore {
    data: Arc<RwLock<HashMap<String, String>>>,
}

impl KVStore {
    fn new() -> Self {
        Self {
            data: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    fn set(&self, key: String, value: String) {
        let mut data = self.data.write().unwrap();
        data.insert(key, value);
    }

    fn get(&self, key: &str) -> Option<String> {
        let data = self.data.read().unwrap();
        data.get(key).cloned()
    }

    fn delete(&self, key: &str) -> bool {
        let mut data = self.data.write().unwrap();
        data.remove(key).is_some()
    }
}

struct Stats {
    total_ops: usize,
    processing_ns: u128,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_ops == 0 {
            return 0.0;
        }
        self.processing_ns as f64 / 1_000_000.0 / self.total_ops as f64
    }

    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 {
            return 0.0;
        }
        self.total_ops as f64 * 1_000_000_000.0 / self.processing_ns as f64
    }
}

fn print_config(num_ops: usize) {
    println!("Configuration:");
    println!("  Operations: {}", num_ops);
    println!("  Store type: In-memory KV Store");
    println!();
}

fn print_stats(stats: &Stats) {
    println!("--- Statistics ---");
    println!("Total operations: {}", stats.total_ops);
    println!("Processing time: {:.3}s", stats.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", stats.avg_latency_ms());
    println!("Throughput: {:.0} ops/sec", stats.throughput());
}

fn generate_test_data(num_ops: usize) -> (Vec<String>, Vec<String>) {
    let mut keys = Vec::with_capacity(num_ops);
    let mut values = Vec::with_capacity(num_ops);

    let key_patterns = vec![
        "user:{}:name", "session:{}:token", "product:{}:price",
        "cache:page:{}", "temp:calc:{}", "config:app:{}",
        "auth:user:{}", "cart:item:{}", "order:{}:status",
        "inventory:{}:count", "log:{}:entry", "metric:{}:value",
        "short", "id:{}", "very_long_key_name_with_descriptors:{}",
        "api:response:{}", "db:query:{}", "file:temp:{}",
    ];

    let value_patterns = vec![
        "John Doe", "active", "true", "false", "123.45",
        r#"{"name":"product","price":99.99,"stock":50}"#,
        r#"{"user_id":12345,"session":"abc123xyz","expires":3600}"#,
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ",
        "<html><body><h1>Page Content</h1></body></html>",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
        "result:42.5:calculation_complete", "pending", "completed", "failed",
        "1", "2", "3", "4", "5", "10", "100", "1000",
        "small_value", "medium_sized_value_with_more_content", "very_large_value_that_contains_much_more_text_and_data_to_simulate_real_world_storage_requirements",
        "2024-02-26T18:18:00Z", "admin", "user", "guest",
    ];

    for i in 0..num_ops {
        let key_pattern = &key_patterns[i % key_patterns.len()];
        let value_pattern = &value_patterns[i % value_patterns.len()];

        let key = if key_pattern.contains("{}") {
            key_pattern.replace("{}", &i.to_string())
        } else {
            format!("{}_{}", key_pattern, i)
        };

        let value = if value_pattern.contains("{}") {
            value_pattern.replace("{}", &i.to_string())
        } else {
            value_pattern.to_string()
        };

        keys.push(key);
        values.push(value);
    }

    (keys, values)
}

fn run_benchmark(num_ops: usize) -> Stats {
    let kv = KVStore::new();

    // Generate realistic test data
    let (keys, values) = generate_test_data(num_ops);

    let start = Instant::now();

    // SET operations
    for i in 0..num_ops {
        kv.set(keys[i].clone(), values[i].clone());
    }

    // GET operations
    for i in 0..num_ops {
        kv.get(&keys[i]);
    }

    // DELETE operations (half of them)
    for i in 0..num_ops/2 {
        kv.delete(&keys[i]);
    }

    let elapsed = start.elapsed();

    Stats {
        total_ops: num_ops*2 + num_ops/2, // SET + GET + DELETE
        processing_ns: elapsed.as_nanos(),
    }
}

fn main() {
    let args = Args::parse();

    print_config(args.operations);
    let stats = run_benchmark(args.operations);
    print_stats(&stats);
}
