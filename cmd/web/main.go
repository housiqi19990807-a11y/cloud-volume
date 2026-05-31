// Web entrypoint serves the Flutter web build, JSON API, and WebDAV endpoints.
package main

import (
	"flag"
	"path/filepath"

	"remote-storage/go/webapi"
)

func main() {
	listenAddr := flag.String("listen", ":8080", "HTTP listen address")
	staticRoot := flag.String("static-root", filepath.Join("build", "web"), "Flutter web build directory")
	flag.Parse()
	if err := serveWeb(webapi.Options{StaticRoot: *staticRoot}, *listenAddr); err != nil {
		panic(err)
	}
}
