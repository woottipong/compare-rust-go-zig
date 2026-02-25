use std::time::{Duration, Instant};
use std::sync::mpsc;
use std::thread;
use std::fs::File;
use std::io::Read;

const SAMPLE_RATE: u32 = 16000;
const CHANNELS: u32 = 1;
const BITS_PER_SAMPLE: u32 = 16;
const BYTES_PER_SAMPLE: u32 = BITS_PER_SAMPLE / 8;
const CHUNK_DURATION_MS: u64 = 25;
const OVERLAP_DURATION_MS: u64 = 10;
const INPUT_INTERVAL_MS: u64 = 10;

fn samples_for_ms(duration_ms: u64) -> usize {
    (SAMPLE_RATE as u64 * duration_ms / 1000) as usize
}

fn bytes_for_ms(duration_ms: u64) -> usize {
    samples_for_ms(duration_ms) * CHANNELS as usize * BYTES_PER_SAMPLE as usize
}

struct AudioChunk {
    data: Vec<u8>,
    timestamp: Instant,
    index: usize,
}

struct Stats {
    total_chunks: usize,
    total_latency: Duration,
    processing_time: Duration,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_chunks == 0 {
            return 0.0;
        }
        (self.total_latency / self.total_chunks as u32).as_secs_f64() * 1000.0
    }

    fn throughput(&self) -> f64 {
        if self.processing_time.is_zero() {
            return 0.0;
        }
        self.total_chunks as f64 / self.processing_time.as_secs_f64()
    }
}

struct AudioChunker {
    chunk_size: usize,
    overlap_size: usize,
    buffer: Vec<u8>,
    buffer_pos: usize,
    chunk_index: usize,
    sender: mpsc::Sender<AudioChunk>,
}

impl AudioChunker {
    fn new() -> (Self, mpsc::Receiver<AudioChunk>) {
        let chunk_size = bytes_for_ms(CHUNK_DURATION_MS);
        let overlap_size = bytes_for_ms(OVERLAP_DURATION_MS);
        let (sender, receiver) = mpsc::channel();
        let chunker = Self {
            chunk_size,
            overlap_size,
            buffer: vec![0u8; chunk_size * 2],
            buffer_pos: 0,
            chunk_index: 0,
            sender,
        };
        (chunker, receiver)
    }

    fn process_audio(&mut self, data: &[u8]) {
        if self.buffer_pos + data.len() > self.buffer.len() {
            self.buffer.resize((self.buffer_pos + data.len()) * 2, 0);
        }
        self.buffer[self.buffer_pos..self.buffer_pos + data.len()].copy_from_slice(data);
        self.buffer_pos += data.len();

        while self.buffer_pos >= self.chunk_size {
            let chunk_data = self.buffer[..self.chunk_size].to_vec();
            if self.sender.send(AudioChunk {
                data: chunk_data,
                timestamp: Instant::now(),
                index: self.chunk_index,
            }).is_err() {
                break;
            }
            self.chunk_index += 1;

            let remaining = self.buffer_pos - self.chunk_size;
            self.buffer.copy_within(self.chunk_size - self.overlap_size..self.buffer_pos, 0);
            self.buffer_pos = remaining + self.overlap_size;
        }
    }
}

fn read_wav_file(filename: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let mut file = File::open(filename)
        .map_err(|e| format!("open {}: {}", filename, e))?;
    let mut header = [0u8; 44];
    file.read_exact(&mut header)
        .map_err(|e| format!("read WAV header: {}", e))?;
    let mut data = Vec::new();
    file.read_to_end(&mut data)?;
    Ok(data)
}

fn print_config(audio_data_len: usize) {
    println!("Audio data size: {} bytes", audio_data_len);
    println!("Chunk size: {} bytes ({}ms)", bytes_for_ms(CHUNK_DURATION_MS), CHUNK_DURATION_MS);
    println!("Overlap size: {} bytes ({}ms)", bytes_for_ms(OVERLAP_DURATION_MS), OVERLAP_DURATION_MS);
}

fn simulate_realtime_input(audio_data: &[u8], chunker: &mut AudioChunker) {
    let bytes_per_interval = bytes_for_ms(INPUT_INTERVAL_MS);
    let interval = Duration::from_millis(INPUT_INTERVAL_MS);

    for chunk_start in (0..audio_data.len()).step_by(bytes_per_interval) {
        let chunk_end = (chunk_start + bytes_per_interval).min(audio_data.len());
        chunker.process_audio(&audio_data[chunk_start..chunk_end]);
        thread::sleep(interval);
    }
}

fn start_processor(receiver: mpsc::Receiver<AudioChunk>) -> thread::JoinHandle<Stats> {
    thread::spawn(move || {
        let mut stats = Stats { total_chunks: 0, total_latency: Duration::ZERO, processing_time: Duration::ZERO };
        for chunk in receiver {
            let latency = chunk.timestamp.elapsed();
            stats.total_latency += latency;
            stats.total_chunks += 1;
            if stats.total_chunks <= 5 || stats.total_chunks % 20 == 0 {
                println!("Chunk {}: {} bytes, latency: {:.3}ms",
                    chunk.index, chunk.data.len(), latency.as_secs_f64() * 1000.0);
            }
        }
        stats
    })
}

fn print_stats(stats: &Stats) {
    println!("\n--- Statistics ---");
    println!("Total chunks: {}", stats.total_chunks);
    println!("Processing time: {:.3}s", stats.processing_time.as_secs_f64());
    println!("Average latency: {:.3}ms", stats.avg_latency_ms());
    println!("Throughput: {:.2} chunks/sec", stats.throughput());
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: realtime-audio-chunker <input.wav>");
        std::process::exit(1);
    }
    let input_file = &args[1];

    let audio_data = read_wav_file(input_file)?;
    println!("Processing audio file: {}", input_file);
    print_config(audio_data.len());

    let (mut chunker, receiver) = AudioChunker::new();
    let processor = start_processor(receiver);

    let start_time = Instant::now();
    simulate_realtime_input(&audio_data, &mut chunker);
    drop(chunker);

    let mut stats = processor.join().unwrap();
    stats.processing_time = start_time.elapsed();

    if stats.total_chunks > 0 {
        print_stats(&stats);
    }

    Ok(())
}
