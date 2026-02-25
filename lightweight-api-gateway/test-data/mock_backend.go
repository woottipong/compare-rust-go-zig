package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Usage: %s <port>\n", os.Args[0])
		os.Exit(1)
	}

	port := os.Args[1]
	if !strings.HasPrefix(port, ":") {
		port = ":" + port
	}

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/api/test", func(w http.ResponseWriter, r *http.Request) {
		// Simulate some work
		time.Sleep(1 * time.Millisecond)

		response := fmt.Sprintf(`{
			"message": "Hello from backend",
			"timestamp": %d,
			"path": "%s",
			"method": "%s"
		}`, time.Now().Unix(), r.URL.Path, r.Method)

		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(response))
	})

	http.HandleFunc("/api/protected", func(w http.ResponseWriter, r *http.Request) {
		// This endpoint should be protected by JWT
		response := fmt.Sprintf(`{
			"message": "Protected data",
			"user": "authenticated-user",
			"timestamp": %d
		}`, time.Now().Unix())

		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(response))
	})

	http.HandleFunc("/public/info", func(w http.ResponseWriter, r *http.Request) {
		// This endpoint is public
		response := fmt.Sprintf(`{
			"message": "Public information",
			"timestamp": %d
		}`, time.Now().Unix())

		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(response))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"error": "Not found"}`))
	})

	fmt.Printf("Mock backend starting on port %s\n", port)
	log.Fatal(http.ListenAndServe("0.0.0.0"+port, nil))
}
