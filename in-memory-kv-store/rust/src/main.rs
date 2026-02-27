use std::collections::HashMap;
use std::sync::RwLock;
use std::time::Instant;

struct KVStore {
    data: RwLock<HashMap<String, String>>,
}

impl KVStore {
    fn new() -> Self {
        Self { data: RwLock::new(HashMap::new()) }
    }

    fn set(&self, key: String, value: String) {
        self.data.write().unwrap().insert(key, value);
    }

    fn get(&self, key: &str) -> Option<String> {
        self.data.read().unwrap().get(key).cloned()
    }

    fn delete(&self, key: &str) -> bool {
        self.data.write().unwrap().remove(key).is_some()
    }
}

struct Stats {
    total_ops: usize,
    processing_ns: u128,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_ops == 0 { return 0.0; }
        self.processing_ns as f64 / 1_000_000.0 / self.total_ops as f64
    }

    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 { return 0.0; }
        self.total_ops as f64 * 1_000_000_000.0 / self.processing_ns as f64
    }
}

fn parse_args() -> Result<usize, String> {
    let args: Vec<String> = std::env::args().collect();
    let num_ops = args.get(1)
        .map(|v| v.parse::<usize>().map_err(|_| "invalid operations".to_string()))
        .transpose()?
        .unwrap_or(100000);
    if num_ops == 0 { return Err("invalid operations".to_string()); }
    Ok(num_ops)
}

fn print_config(num_ops: usize) {
    println!("Configuration:");
    println!("  Operations: {}", num_ops);
    println!("  Store type: In-memory KV Store");
    println!();
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_ops);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.0} ops/sec", s.throughput());
}

fn generate_test_data(num_ops: usize) -> (Vec<String>, Vec<String>) {
    let key_patterns = [
        "user:{}:name", "session:{}:token", "product:{}:price",
        "cache:page:{}", "temp:calc:{}", "config:app:{}",
        "auth:user:{}", "cart:item:{}", "order:{}:status",
        "inventory:{}:count", "log:{}:entry", "metric:{}:value",
        "short", "id:{}", "very_long_key_name_with_descriptors:{}",
        "api:response:{}", "db:query:{}", "file:temp:{}",
    ];
    let value_patterns = [
        "John Doe", "active", "true", "false", "123.45",
        r#"{"name":"product","price":99.99,"stock":50}"#,
        r#"{"user_id":12345,"session":"abc123xyz","expires":3600}"#,
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload",
        "<html><body><h1>Page Content</h1></body></html>",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
        "result:42.5:done", "pending", "completed", "failed",
        "1", "2", "3", "100",
        "small_value", "medium_sized_value_with_more_content",
        "very_large_value_that_contains_much_more_text_and_data",
        "2024-02-26T18:18:00Z", "admin", "user", "guest",
    ];

    let mut keys = Vec::with_capacity(num_ops);
    let mut values = Vec::with_capacity(num_ops);
    for i in 0..num_ops {
        let pat = key_patterns[i % key_patterns.len()];
        let key = if pat.contains("{}") { pat.replace("{}", &i.to_string()) }
                  else { format!("{}_{}", pat, i) };
        let val = value_patterns[i % value_patterns.len()].to_string();
        keys.push(key);
        values.push(val);
    }
    (keys, values)
}

fn run_benchmark(num_ops: usize) -> Stats {
    let kv = KVStore::new();
    let (keys, values) = generate_test_data(num_ops);

    let start = Instant::now();

    for i in 0..num_ops { kv.set(keys[i].clone(), values[i].clone()); }
    for i in 0..num_ops { kv.get(&keys[i]); }
    for i in 0..num_ops / 2 { kv.delete(&keys[i]); }

    Stats {
        total_ops: num_ops * 2 + num_ops / 2,
        processing_ns: start.elapsed().as_nanos(),
    }
}

fn main() {
    let num_ops = parse_args().unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
    print_config(num_ops);
    let stats = run_benchmark(num_ops);
    print_stats(&stats);
}
