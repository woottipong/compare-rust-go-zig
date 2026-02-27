package main

import (
	"context"
	"flag"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
)

func main() {
	port := flag.String("port", "8080", "listen port")
	duration := flag.Int("duration", 0, "run duration in seconds (0 = run until interrupted)")
	flag.Parse()

	stats := newStats()
	hub := newHub(stats)
	go hub.run()

	app := fiber.New(fiber.Config{
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	})

	// WebSocket upgrade middleware — only /ws
	app.Use("/ws", func(c *fiber.Ctx) error {
		if websocket.IsWebSocketUpgrade(c) {
			return c.Next()
		}
		return fiber.ErrUpgradeRequired
	})

	app.Get("/ws", websocket.New(func(c *websocket.Conn) {
		serveWs(hub, c)
	}))

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.SendStatus(fiber.StatusOK)
	})

	log.Printf("websocket-public-chat (profile-a): listening on :%s", *port)

	if *duration > 0 {
		go func() {
			time.Sleep(time.Duration(*duration) * time.Second)
			_ = app.ShutdownWithContext(context.Background())
		}()
	}

	if err := app.Listen(":" + *port); err != nil {
		log.Fatalf("server error: %v", err)
	}

	stats.printStats()
}
