package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"time"
)

func main() {
	port := flag.String("port", "8080", "listen port")
	duration := flag.Int("duration", 0, "run duration in seconds (0 = run until interrupted)")
	flag.Parse()

	stats := newStats()
	hub := newHub(stats)
	go hub.run()

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		serveWs(hub, w, r)
	})
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	srv := &http.Server{
		Addr:    ":" + *port,
		Handler: mux,
	}

	log.Printf("websocket-public-chat: listening on :%s", *port)

	if *duration > 0 {
		go func() {
			time.Sleep(time.Duration(*duration) * time.Second)
			srv.Shutdown(context.Background())
		}()
	}

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}

	stats.printStats()
}
