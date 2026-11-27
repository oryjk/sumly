package main

import (
	"context"
	"net"
	"net/http"
	"sync/atomic"
	"testing"
	"time"
)

func TestServeWithGracefulShutdownDrainsInFlightRequestsAndRunsCleanup(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer listener.Close()

	requestStarted := make(chan struct{})
	releaseRequest := make(chan struct{})

	server := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			close(requestStarted)
			<-releaseRequest
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("drained"))
		}),
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var cleanedUp atomic.Bool
	done := make(chan error, 1)
	go func() {
		defer cleanedUp.Store(true)
		done <- serveWithGracefulShutdown(ctx, server, listener, 5*time.Second)
	}()

	respCh := make(chan *http.Response, 1)
	errCh := make(chan error, 1)
	go func() {
		resp, reqErr := http.Get("http://" + listener.Addr().String() + "/slow")
		if reqErr != nil {
			errCh <- reqErr
			return
		}
		respCh <- resp
	}()

	select {
	case <-requestStarted:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for request to reach handler")
	}

	// 触发停机信号（模拟 SIGINT/SIGTERM）
	cancel()

	// 给 server.Shutdown 一点时间进入排空状态，再放行在途请求
	time.Sleep(50 * time.Millisecond)
	close(releaseRequest)

	select {
	case reqErr := <-errCh:
		t.Fatalf("in-flight request failed during shutdown: %v", reqErr)
	case resp := <-respCh:
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("in-flight response status = %d, want 200", resp.StatusCode)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for in-flight response")
	}

	select {
	case serveErr := <-done:
		if serveErr != nil {
			t.Fatalf("serveWithGracefulShutdown returned error: %v", serveErr)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for server shutdown")
	}

	if !cleanedUp.Load() {
		t.Fatal("expected deferred cleanup to execute after shutdown")
	}
}

func TestServeWithGracefulShutdownReturnsServeError(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	_ = listener.Close()

	server := &http.Server{Handler: http.NewServeMux()}
	if err := serveWithGracefulShutdown(context.Background(), server, listener, time.Second); err == nil {
		t.Fatal("expected error from closed listener")
	}
}
