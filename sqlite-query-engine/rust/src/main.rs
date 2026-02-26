use std::fs;
use std::time::Instant;

struct Stats {
    total_processed: u64,
    processing_ns: u128,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_processed == 0 {
            return 0.0;
        }
        self.processing_ns as f64 / 1_000_000.0 / self.total_processed as f64
    }

    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 {
            return 0.0;
        }
        self.total_processed as f64 * 1_000_000_000.0 / self.processing_ns as f64
    }
}

fn parse_args() -> Result<(String, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let input = if args.len() > 1 {
        args[1].clone()
    } else {
        "/data/metrics.db".to_string()
    };
    let repeats = if args.len() > 2 {
        args[2]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        1000
    };
    if repeats == 0 {
        return Err("repeats must be positive integer".to_string());
    }
    Ok((input, repeats))
}

/// Decode a SQLite varint from data[off..]. Returns (value, bytes_consumed).
fn read_varint(data: &[u8], off: usize) -> (u64, usize) {
    let mut n: u64 = 0;
    for i in 0..9 {
        let b = data[off + i];
        if i == 8 {
            return ((n << 8) | b as u64, 9);
        }
        n = (n << 7) | (b & 0x7f) as u64;
        if b & 0x80 == 0 {
            return (n, i + 1);
        }
    }
    (n, 9)
}

/// Byte size of a SQLite record column given its serial type.
fn col_size(t: u64) -> usize {
    match t {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        4 => 4,
        5 => 6,
        6 => 8,
        7 => 8,
        8 | 9 => 0,
        t if t >= 12 => {
            if t % 2 == 0 {
                ((t - 12) / 2) as usize
            } else {
                ((t - 13) / 2) as usize
            }
        }
        _ => 0,
    }
}

/// Read a SQLite integer column of the given serial type.
fn read_int_col(data: &[u8], off: usize, t: u64) -> i64 {
    match t {
        1 => data[off] as i8 as i64,
        2 => i16::from_be_bytes([data[off], data[off + 1]]) as i64,
        3 => {
            let v = (data[off] as u32) << 16
                | (data[off + 1] as u32) << 8
                | data[off + 2] as u32;
            let v = if v & 0x800000 != 0 { v | 0xff000000 } else { v };
            v as i32 as i64
        }
        4 => i32::from_be_bytes([data[off], data[off + 1], data[off + 2], data[off + 3]]) as i64,
        5 => {
            let v = (data[off] as u64) << 40
                | (data[off + 1] as u64) << 32
                | (data[off + 2] as u64) << 24
                | (data[off + 3] as u64) << 16
                | (data[off + 4] as u64) << 8
                | data[off + 5] as u64;
            let v = if v & (1 << 47) != 0 {
                v | 0xffff000000000000
            } else {
                v
            };
            v as i64
        }
        6 => i64::from_be_bytes([
            data[off],
            data[off + 1],
            data[off + 2],
            data[off + 3],
            data[off + 4],
            data[off + 5],
            data[off + 6],
            data[off + 7],
        ]),
        8 => 0,
        9 => 1,
        _ => 0,
    }
}

fn page_base(page_num: u32, page_size: u32) -> usize {
    (page_num as u64 - 1) as usize * page_size as usize
}

fn page_header_off(page_num: u32, page_size: u32) -> usize {
    let base = page_base(page_num, page_size);
    if page_num == 1 {
        base + 100
    } else {
        base
    }
}

/// DFS from page_num, appending all leaf page numbers to leaves.
fn collect_leaf_pages(data: &[u8], page_size: u32, page_num: u32, leaves: &mut Vec<u32>) {
    let h_off = page_header_off(page_num, page_size);
    let p_base = page_base(page_num, page_size);
    let page_type = data[h_off];
    let num_cells = u16::from_be_bytes([data[h_off + 3], data[h_off + 4]]) as usize;

    match page_type {
        0x0d => {
            // leaf table
            leaves.push(page_num);
        }
        0x05 => {
            // interior table — cell ptr array starts at h_off+12
            for i in 0..num_cells {
                let ptr_off = h_off + 12 + i * 2;
                let cell_off =
                    p_base + u16::from_be_bytes([data[ptr_off], data[ptr_off + 1]]) as usize;
                let child = u32::from_be_bytes([
                    data[cell_off],
                    data[cell_off + 1],
                    data[cell_off + 2],
                    data[cell_off + 3],
                ]);
                collect_leaf_pages(data, page_size, child, leaves);
            }
            // rightmost child at h_off+8
            let right = u32::from_be_bytes([
                data[h_off + 8],
                data[h_off + 9],
                data[h_off + 10],
                data[h_off + 11],
            ]);
            collect_leaf_pages(data, page_size, right, leaves);
        }
        _ => {}
    }
}

/// Scan sqlite_schema (page 1) to find the root page of table_name.
fn find_table_root(data: &[u8], table_name: &str) -> Result<u32, String> {
    let h_off = 100usize; // page 1 B-tree header after file header
    let num_cells = u16::from_be_bytes([data[h_off + 3], data[h_off + 4]]) as usize;

    for i in 0..num_cells {
        let ptr_off = h_off + 8 + i * 2;
        // page 1 cell offsets are from file start (page base = 0)
        let mut cell_off = u16::from_be_bytes([data[ptr_off], data[ptr_off + 1]]) as usize;

        // skip payload_size varint
        let (_, n) = read_varint(data, cell_off);
        cell_off += n;
        // skip rowid varint
        let (_, n) = read_varint(data, cell_off);
        cell_off += n;

        // record header
        let h_start = cell_off;
        let (h_len, n) = read_varint(data, cell_off);
        cell_off += n;
        let h_end = h_start + h_len as usize;

        // sqlite_schema: type, name, tbl_name, rootpage, sql
        let mut types = [0u64; 5];
        let mut tmp = cell_off;
        for j in 0..5 {
            if tmp >= h_end {
                break;
            }
            let (t, tn) = read_varint(data, tmp);
            types[j] = t;
            tmp += tn;
        }

        let mut val_off = h_end;
        val_off += col_size(types[0]); // skip col[0]: type TEXT

        // col[1]: name TEXT
        let name_len = col_size(types[1]);
        let name = std::str::from_utf8(&data[val_off..val_off + name_len]).unwrap_or("");
        val_off += name_len;

        if name == table_name {
            val_off += col_size(types[2]); // skip col[2]: tbl_name TEXT
            let root = read_int_col(data, val_off, types[3]);
            return Ok(root as u32);
        }
    }
    Err(format!("table not found: {}", table_name))
}

/// Scan all leaf_pages repeats times, counting rows where cpu_pct > 80.0.
/// Returns rows_scanned + matching_rows.
fn query(data: &[u8], page_size: u32, leaf_pages: &[u32], repeats: usize) -> u64 {
    let mut rows_scanned: u64 = 0;
    let mut matching_rows: u64 = 0;

    for _ in 0..repeats {
        for &page_num in leaf_pages {
            let h_off = page_header_off(page_num, page_size);
            let p_base = page_base(page_num, page_size);
            let num_cells = u16::from_be_bytes([data[h_off + 3], data[h_off + 4]]) as usize;

            for i in 0..num_cells {
                let ptr_off = h_off + 8 + i * 2;
                let mut cell_off =
                    p_base + u16::from_be_bytes([data[ptr_off], data[ptr_off + 1]]) as usize;

                // skip payload_size varint
                let (_, n) = read_varint(data, cell_off);
                cell_off += n;
                // skip rowid varint
                let (_, n) = read_varint(data, cell_off);
                cell_off += n;

                // record header
                let h_start = cell_off;
                let (h_len, n) = read_varint(data, cell_off);
                cell_off += n;
                let h_end = h_start + h_len as usize;

                // col[0] type (hostname TEXT)
                let (t0, _) = read_varint(data, cell_off);

                // cpu_pct is immediately after hostname in the value area
                let cpu_off = h_end + col_size(t0);
                let cpu_bits = u64::from_be_bytes([
                    data[cpu_off],
                    data[cpu_off + 1],
                    data[cpu_off + 2],
                    data[cpu_off + 3],
                    data[cpu_off + 4],
                    data[cpu_off + 5],
                    data[cpu_off + 6],
                    data[cpu_off + 7],
                ]);
                let cpu = f64::from_bits(cpu_bits);

                rows_scanned += 1;
                if cpu > 80.0 {
                    matching_rows += 1;
                }
            }
        }
    }

    rows_scanned + matching_rows
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!(
        "Processing time: {:.3}s",
        s.processing_ns as f64 / 1_000_000_000.0
    );
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (input, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let data = fs::read(&input).unwrap_or_else(|e| {
        eprintln!("Error: read {input}: {e}");
        std::process::exit(1);
    });

    if data.len() < 100 {
        eprintln!("Error: file too small");
        std::process::exit(1);
    }

    let raw_page_size = u16::from_be_bytes([data[16], data[17]]);
    let page_size = if raw_page_size == 1 {
        65536u32
    } else {
        raw_page_size as u32
    };

    let root_page = find_table_root(&data, "metrics").unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let mut leaf_pages = Vec::new();
    collect_leaf_pages(&data, page_size, root_page, &mut leaf_pages);
    if leaf_pages.is_empty() {
        eprintln!("Error: no leaf pages found");
        std::process::exit(1);
    }

    let start = Instant::now();
    let total = query(&data, page_size, &leaf_pages, repeats);
    let s = Stats {
        total_processed: total,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&s);
}
