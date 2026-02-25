#!/usr/bin/env python3
"""
Vector DB Ingester Test Data Generator
Generates realistic test data for benchmarking vector database ingestion
"""

import json
import random
import math
from datetime import datetime

# Sample content templates
TECH_TOPICS = [
    "artificial intelligence and machine learning algorithms",
    "cloud computing infrastructure and distributed systems",
    "cybersecurity threats and network security protocols",
    "database management systems and query optimization",
    "software development methodologies and best practices",
    "microservices architecture and container orchestration",
    "data science analytics and visualization techniques",
    "blockchain technology and cryptocurrency systems",
    "internet of things devices and edge computing",
    "natural language processing and text mining",
    "computer vision and image recognition systems",
    "mobile application development and user experience",
    "devops automation and continuous integration",
    "big data processing and streaming analytics",
    "quantum computing and advanced algorithms"
]

COMPANY_NAMES = [
    "TechCorp Solutions", "DataFlow Systems", "CloudNet Technologies", 
    "SecureBit Innovations", "DevOps Masters", "AI Research Labs",
    "Quantum Computing Inc", "IoT Solutions Ltd", "Blockchain Dynamics",
    "MobileFirst Development", "Analytics Pro", "CyberShield Systems"
]

PROJECT_TYPES = ["research", "production", "prototype", "legacy", "experimental"]

def generate_sentence(topic, min_words=10, max_words=25):
    """Generate a realistic sentence about a technical topic"""
    words = topic.split()
    base_words = len(words)
    
    # Add technical terms and connectors
    connectors = [
        "enables", "provides", "facilitates", "optimizes", "enhances",
        "improves", "streamlines", "automates", "secures", "scales"
    ]
    
    technical_terms = [
        "performance", "scalability", "reliability", "efficiency", "security",
        "integration", "deployment", "monitoring", "analytics", "optimization"
    ]
    
    sentence_words = words.copy()
    
    # Add random technical content
    while len(sentence_words) < random.randint(min_words, max_words):
        if random.random() < 0.6:
            sentence_words.append(random.choice(connectors))
        if random.random() < 0.4:
            sentence_words.append(random.choice(technical_terms))
        if random.random() < 0.3:
            sentence_words.append("through")
        if random.random() < 0.3:
            sentence_words.append("with")
        if random.random() < 0.2:
            sentence_words.append("advanced")
    
    # Ensure we have the right length
    while len(sentence_words) < min_words:
        sentence_words.append(random.choice(technical_terms))
    
    return " ".join(sentence_words[:max_words]) + "." if sentence_words[-1][-1] != "." else " ".join(sentence_words[:max_words])

def generate_paragraph(topic, num_sentences=3):
    """Generate a paragraph on a technical topic"""
    sentences = []
    for _ in range(num_sentences):
        sentences.append(generate_sentence(topic))
    return " ".join(sentences)

def generate_document(doc_id, target_words):
    """Generate a single document with realistic content"""
    # Choose random topics
    num_topics = min(5, max(1, target_words // 100))
    topics = random.sample(TECH_TOPICS, num_topics)
    
    # Generate content
    content_parts = []
    remaining_words = target_words
    
    for i, topic in enumerate(topics):
        if i == len(topics) - 1:
            # Last topic gets remaining words
            sentences_needed = max(2, remaining_words // 20)
        else:
            sentences_needed = random.randint(2, 4)
        
        paragraph = generate_paragraph(topic, sentences_needed)
        content_parts.append(paragraph)
        
        # Rough word count estimation
        remaining_words -= len(paragraph.split())
        if remaining_words <= 0:
            break
    
    content = " ".join(content_parts)
    
    # Trim to exact word count
    words = content.split()
    if len(words) > target_words:
        content = " ".join(words[:target_words])
    
    # Add metadata
    doc = {
        "id": f"doc-{doc_id:06d}",
        "content": content,
        "type": random.choice(["pdf", "docx", "txt", "md", "html"]),
        "metadata": {
            "source": random.choice(["wikipedia", "github", "stackoverflow", "medium", "arxiv"]),
            "language": random.choice(["en", "th", "ja", "ko", "zh"]),
            "company": random.choice(COMPANY_NAMES),
            "project_type": random.choice(PROJECT_TYPES),
            "created_at": f"2024-{random.randint(1,12):02d}-{random.randint(1,28):02d}",
            "word_count": len(content.split())
        }
    }
    
    return doc

def generate_test_data(num_docs=1000, min_words=100, max_words=5000):
    """Generate test dataset"""
    print(f"Generating {num_docs} documents...")
    
    documents = []
    total_words = 0
    
    for i in range(num_docs):
        # Variable word count for realistic distribution
        if i < num_docs * 0.6:  # 60% short docs
            target_words = random.randint(min_words, 500)
        elif i < num_docs * 0.9:  # 30% medium docs
            target_words = random.randint(500, 1500)
        else:  # 10% long docs
            target_words = random.randint(1500, max_words)
        
        doc = generate_document(i + 1, target_words)
        documents.append(doc)
        total_words += len(doc["content"].split())
        
        if (i + 1) % 100 == 0:
            print(f"  Generated {i + 1}/{num_docs} documents...")
    
    # Calculate statistics
    avg_words = total_words / num_docs
    estimated_chunks = 0
    
    for doc in documents:
        word_count = doc["metadata"]["word_count"]
        # Estimate chunks (512 words per chunk, 50 overlap)
        if word_count <= 512:
            estimated_chunks += 1
        else:
            chunks = math.ceil((word_count - 512) / (512 - 50)) + 1
            estimated_chunks += chunks
    
    dataset = {
        "metadata": {
            "total_documents": num_docs,
            "total_words": total_words,
            "average_words_per_doc": avg_words,
            "estimated_chunks": estimated_chunks,
            "generated_at": datetime.now().isoformat(),
            "chunk_size": 512,
            "chunk_overlap": 50
        },
        "documents": documents
    }
    
    return dataset

def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Generate test data for Vector DB Ingester")
    parser.add_argument("--docs", type=int, default=1000, help="Number of documents to generate")
    parser.add_argument("--min-words", type=int, default=100, help="Minimum words per document")
    parser.add_argument("--max-words", type=int, default=5000, help="Maximum words per document")
    parser.add_argument("--output", type=str, default="test-data/large-test.json", help="Output file path")
    parser.add_argument("--small", action="store_true", help="Generate small test dataset (100 docs)")
    parser.add_argument("--medium", action="store_true", help="Generate medium test dataset (500 docs)")
    
    args = parser.parse_args()
    
    # Adjust size based on flags
    if args.small:
        num_docs = 100
        args.min_words = 50
        args.max_words = 1000
    elif args.medium:
        num_docs = 500
    else:
        num_docs = args.docs
    
    # Generate data
    dataset = generate_test_data(num_docs, args.min_words, args.max_words)
    
    # Create output directory
    import os
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    
    # Save to file
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(dataset, f, indent=2, ensure_ascii=False)
    
    # Print statistics
    metadata = dataset["metadata"]
    print(f"\n✅ Test data generated successfully!")
    print(f"📁 Output: {args.output}")
    print(f"📊 Statistics:")
    print(f"   Documents: {metadata['total_documents']:,}")
    print(f"   Total words: {metadata['total_words']:,}")
    print(f"   Avg words/doc: {metadata['average_words_per_doc']:.1f}")
    print(f"   Estimated chunks: {metadata['estimated_chunks']:,}")
    print(f"   File size: {os.path.getsize(args.output) / 1024 / 1024:.1f} MB")

if __name__ == "__main__":
    main()
