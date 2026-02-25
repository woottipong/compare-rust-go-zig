package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"strings"
	"sync"
	"time"
)

const (
	defaultPort       = "8080"
	defaultBackends   = "http://localhost:3001,http://localhost:3002,http://localhost:3003"
	defaultHealthPath = "/health"
	defaultTimeout    = 5 * time.Second
)

type Backend struct {
	URL       string
	Weight    int
	Healthy   bool
	LastCheck time.Time
}

type LoadBalancer struct {
	backends []*Backend
	mu       sync.RWMutex
	index    uint32
}

func NewLoadBalancer(backendURLs []string) *LoadBalancer {
	backends := make([]*Backend, len(backendURLs))
	for i, url := range backendURLs {
		backends[i] = &Backend{URL: url, Weight: 1, Healthy: true}
	}
	return &LoadBalancer{backends: backends}
}

func (lb *LoadBalancer) getBackend() *Backend {
	lb.mu.Lock()
	defer lb.mu.Unlock()

	n := uint32(len(lb.backends))
	for i := uint32(0); i < n; i++ {
		idx := lb.index % n
		lb.index++
		if lb.backends[idx].Healthy {
			return lb.backends[idx]
		}
	}
	return nil
}

func (lb *LoadBalancer) checkHealth(healthPath string, timeout time.Duration) {
	for {
		time.Sleep(2 * time.Second)
		lb.mu.RLock()
		backends := make([]*Backend, len(lb.backends))
		copy(backends, lb.backends)
		lb.mu.RUnlock()

		for _, b := range backends {
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			req, _ := http.NewRequestWithContext(ctx, "GET", b.URL+healthPath, nil)
			resp, err := http.DefaultClient.Do(req)
			cancel()

			lb.mu.Lock()
			b.Healthy = err == nil && resp != nil && resp.StatusCode < 500
			b.LastCheck = time.Now()
			if resp != nil {
				resp.Body.Close()
			}
			lb.mu.Unlock()
		}
	}
}

func (lb *LoadBalancer) StartHealthChecker(healthPath string, timeout time.Duration) {
	go lb.checkHealth(healthPath, timeout)
}

type ProxyHandler struct {
	lb    *LoadBalancer
	proxy *httputil.ReverseProxy
}

func newProxyHandler(lb *LoadBalancer) *ProxyHandler {
	h := &ProxyHandler{lb: lb}
	h.proxy = &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			backend := lb.getBackend()
			if backend == nil {
				return
			}
			req.URL.Scheme = "http"
			req.URL.Host = backend.URL[len("http://"):]
			req.Host = req.URL.Host
		},
		Transport: &http.Transport{
			DialContext:         (&net.Dialer{Timeout: defaultTimeout}).DialContext,
			TLSHandshakeTimeout: defaultTimeout,
			MaxIdleConns:        200,
			MaxIdleConnsPerHost: 50,
			IdleConnTimeout:     30 * time.Second,
		},
	}
	return h
}

func (h *ProxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.lb.getBackend() == nil {
		http.Error(w, "No healthy backends", http.StatusServiceUnavailable)
		return
	}
	h.proxy.ServeHTTP(w, r)
}

func main() {
	port := flag.String("port", defaultPort, "Proxy listen port")
	backends := flag.String("backends", defaultBackends, "Comma-separated backend URLs")
	healthPath := flag.String("health-path", defaultHealthPath, "Health check path")
	flag.Parse()

	backendURLs := parseBackends(*backends)
	if len(backendURLs) == 0 {
		log.Fatal("No backends specified")
	}

	lb := NewLoadBalancer(backendURLs)
	lb.StartHealthChecker(*healthPath, defaultTimeout)

	handler := newProxyHandler(lb)

	fmt.Printf("Reverse Proxy starting on :%s\n", *port)
	fmt.Printf("Backends: %s\n", *backends)
	fmt.Printf("Health check path: %s\n", *healthPath)

	if err := http.ListenAndServe(":"+*port, handler); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

func parseBackends(s string) []string {
	var urls []string
	for _, u := range strings.Split(s, ",") {
		u = strings.TrimSpace(u)
		if u != "" {
			urls = append(urls, u)
		}
	}
	return urls
}
