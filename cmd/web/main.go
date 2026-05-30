// Web entrypoint serves the Flutter web build, JSON API, and WebDAV endpoints.
package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"remote-storage/go/webapi"
)

func main() {
	listenAddr := flag.String("listen", ":8080", "HTTP listen address")
	staticRoot := flag.String("static-root", filepath.Join("build", "web"), "Flutter web build directory")
	flag.Parse()

	server := webapi.NewServer(webapi.Options{StaticRoot: *staticRoot})
	httpServer := &http.Server{
		Addr:              *listenAddr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("[web] listening on %s", *listenAddr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[web] listen failed: %v", err)
		}
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	<-signals

	if err := httpServer.Close(); err != nil {
		log.Printf("[web] close server: %v", err)
	}
	if err := server.Close(); err != nil {
		log.Printf("[web] cleanup: %v", err)
	}
}
