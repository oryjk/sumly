package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/bootstrap"
)

const defaultShutdownTimeout = 15 * time.Second

func main() {
	if err := run(); err != nil {
		slog.Error("server exited with error", "error", err)
		os.Exit(1)
	}
}

func run() error {
	signalCtx, stopSignals := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stopSignals()

	config, err := bootstrap.LoadConfig()
	if err != nil {
		return fmt.Errorf("load configuration: %w", err)
	}
	dependencies, closeDependencies, err := bootstrap.BuildDependencies(signalCtx, config)
	if err != nil {
		return fmt.Errorf("build dependencies: %w", err)
	}
	defer closeDependencies()

	server := &http.Server{
		Addr:              config.HTTPAddr,
		Handler:           bootstrap.NewRouter(dependencies),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	addr := server.Addr
	if addr == "" {
		addr = ":http"
	}
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("listen %s: %w", addr, err)
	}

	slog.Info("starting HTTP server", "address", config.HTTPAddr, "environment", config.AppEnvironment)
	return serveWithGracefulShutdown(signalCtx, server, listener, defaultShutdownTimeout)
}

func serveWithGracefulShutdown(ctx context.Context, server *http.Server, listener net.Listener, shutdownTimeout time.Duration) error {
	if shutdownTimeout <= 0 {
		shutdownTimeout = defaultShutdownTimeout
	}
	errCh := make(chan error, 1)
	go func() {
		err := server.Serve(listener)
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
			return
		}
		errCh <- nil
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		slog.Info("shutdown signal received, draining HTTP server", "timeout", shutdownTimeout)
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		shutdownErr := server.Shutdown(shutdownCtx)
		serveErr := <-errCh
		if shutdownErr != nil {
			return fmt.Errorf("shutdown HTTP server: %w", shutdownErr)
		}
		return serveErr
	}
}
