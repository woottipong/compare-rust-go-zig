package main

import (
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
)

type RateLimiter struct {
	clients map[string]*ClientLimiter
	mu      sync.RWMutex
}

type ClientLimiter struct {
	count     int64
	lastReset int64
}

func NewRateLimiter() *RateLimiter {
	return &RateLimiter{
		clients: make(map[string]*ClientLimiter),
	}
}

func (rl *RateLimiter) Allow(clientIP string, limit int64, window time.Duration) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now().Unix()

	limiter, exists := rl.clients[clientIP]
	if !exists || now-limiter.lastReset >= int64(window.Seconds()) {
		limiter = &ClientLimiter{
			count:     0,
			lastReset: now,
		}
		rl.clients[clientIP] = limiter
	}

	if limiter.count >= limit {
		return false
	}

	limiter.count++
	return true
}

type Gateway struct {
	targetURL   string
	rateLimiter *RateLimiter
}

func NewGateway(targetURL string) *Gateway {
	return &Gateway{
		targetURL:   targetURL,
		rateLimiter: NewRateLimiter(),
	}
}

func (g *Gateway) JWTMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Skip JWT for public endpoints
		if strings.HasPrefix(c.Path(), "/public/") || c.Path() == "/health" {
			return c.Next()
		}

		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Missing authorization header",
			})
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		if tokenString == authHeader {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid authorization header format",
			})
		}

		// Simple JWT validation for benchmarking
		if tokenString != "valid-test-token" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid token",
			})
		}

		// Add user info to context
		c.Locals("user_id", "test-user")
		return c.Next()
	}
}

func (g *Gateway) CustomRateLimitMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		clientIP := c.IP()

		if !g.rateLimiter.Allow(clientIP, 100, time.Minute) {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded",
			})
		}

		return c.Next()
	}
}

func (g *Gateway) ProxyMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Modify request headers
		c.Request().Header.Set("X-Forwarded-Host", c.Hostname())
		c.Request().Header.Set("X-Real-IP", c.IP())
		c.Request().Header.Set("X-Forwarded-For", c.IP())

		// For demo, return simple response instead of actual proxy
		return c.JSON(fiber.Map{
			"message":   "Gateway received request",
			"method":    c.Method(),
			"path":      c.Path(),
			"target":    g.targetURL,
			"user_id":   c.Locals("user_id"),
			"timestamp": time.Now().Unix(),
		})
	}
}

func (g *Gateway) HealthCheck(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"status":    "OK",
		"timestamp": time.Now().Unix(),
	})
}

func (g *Gateway) PublicInfo(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"message":   "Public information",
		"timestamp": time.Now().Unix(),
	})
}

func (g *Gateway) ProtectedData(c *fiber.Ctx) error {
	userID := c.Locals("user_id")
	return c.JSON(fiber.Map{
		"message":   "Protected data",
		"user_id":   userID,
		"timestamp": time.Now().Unix(),
	})
}

func (g *Gateway) SetupRoutes() *fiber.App {
	app := fiber.New(fiber.Config{
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
		IdleTimeout:  10 * time.Second,
	})

	// Custom rate limiting (in addition to Fiber's limiter)
	app.Use(g.CustomRateLimitMiddleware())

	// JWT middleware
	app.Use(g.JWTMiddleware())

	// Health check
	app.Get("/health", g.HealthCheck)

	// Public endpoints
	app.Get("/public/info", g.PublicInfo)

	// Protected endpoints
	app.Get("/api/protected", g.ProtectedData)

	// API routes with proxy
	app.All("/api/*", g.ProxyMiddleware())

	// Fallback for all other routes
	app.All("/*", g.ProxyMiddleware())

	return app
}

func main() {
	if len(os.Args) != 3 {
		fmt.Printf("Usage: %s <listen_addr> <target_url>\n", os.Args[0])
		fmt.Printf("Example: %s :8080 http://localhost:3000\n", os.Args[0])
		os.Exit(1)
	}

	listenAddr := os.Args[1]
	targetURL := os.Args[2]

	gateway := NewGateway(targetURL)
	app := gateway.SetupRoutes()

	log.Printf("Starting Fiber gateway on %s -> %s", listenAddr, targetURL)

	// Add port if not specified
	if !strings.Contains(listenAddr, ":") {
		listenAddr = ":" + listenAddr
	}

	if err := app.Listen(listenAddr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
