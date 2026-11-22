package appconfighttp

import (
	"log/slog"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

// RegisterStaticRoutes 当 staticDir 非空且为存在的目录时，在 /admin 与 /admin/*filepath
// 托管管理后台 SPA 静态构建产物；未知安全子路径自动回退至 index.html，并严格防范路径穿越。
func RegisterStaticRoutes(router *gin.Engine, staticDir string) bool {
	dir := strings.TrimSpace(staticDir)
	if dir == "" {
		return false
	}
	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		slog.Warn("ADMIN_STATIC_DIR does not exist or is not a directory; skipping admin static routes", "dir", dir)
		return false
	}
	absRoot, err := filepath.Abs(dir)
	if err != nil {
		slog.Warn("resolve ADMIN_STATIC_DIR failed; skipping admin static routes", "dir", dir, "error", err)
		return false
	}
	evalRoot, err := filepath.EvalSymlinks(absRoot)
	if err != nil {
		evalRoot = absRoot
	}

	serve := func(c *gin.Context) {
		rawParam := c.Param("filepath")
		if hasTraversalAttempt(rawParam, c.Request.URL.RawPath, c.Request.URL.Path) {
			c.AbortWithStatus(http.StatusForbidden)
			return
		}

		cleaned := strings.TrimPrefix(path.Clean("/"+rawParam), "/")
		if cleaned == "" || cleaned == "." {
			serveIndexHTML(c, absRoot, evalRoot)
			return
		}

		candidate := filepath.Join(absRoot, filepath.FromSlash(cleaned))
		if !isWithinRoot(absRoot, candidate) {
			c.AbortWithStatus(http.StatusForbidden)
			return
		}

		stat, err := os.Stat(candidate)
		if err != nil {
			if os.IsNotExist(err) {
				serveIndexHTML(c, absRoot, evalRoot)
				return
			}
			c.AbortWithStatus(http.StatusNotFound)
			return
		}
		if stat.IsDir() {
			serveIndexHTML(c, absRoot, evalRoot)
			return
		}

		resolved, err := filepath.EvalSymlinks(candidate)
		if err != nil || !isWithinRoot(evalRoot, resolved) {
			c.AbortWithStatus(http.StatusForbidden)
			return
		}

		if cleaned == "index.html" {
			c.Header("Cache-Control", "no-cache")
		}
		serveFileContent(c, resolved)
	}

	router.GET("/admin", serve)
	router.HEAD("/admin", serve)
	router.GET("/admin/*filepath", serve)
	router.HEAD("/admin/*filepath", serve)
	return true
}

func serveIndexHTML(c *gin.Context, absRoot, evalRoot string) {
	indexPath := filepath.Join(absRoot, "index.html")
	resolved, err := filepath.EvalSymlinks(indexPath)
	if err != nil || !isWithinRoot(evalRoot, resolved) {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	c.Header("Cache-Control", "no-cache")
	serveFileContent(c, resolved)
}

func serveFileContent(c *gin.Context, filePath string) {
	file, err := os.Open(filePath)
	if err != nil {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	defer func() { _ = file.Close() }()

	stat, err := file.Stat()
	if err != nil || stat.IsDir() {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	http.ServeContent(c.Writer, c.Request, stat.Name(), stat.ModTime(), file)
}

func hasTraversalAttempt(param, rawPath, urlPath string) bool {
	for _, value := range []string{param, rawPath, urlPath} {
		if value == "" {
			continue
		}
		if strings.ContainsRune(value, '\x00') || strings.Contains(value, "\\") {
			return true
		}
		lower := strings.ToLower(value)
		if strings.Contains(lower, "%2e%2e") || strings.Contains(lower, "%5c") || strings.Contains(lower, "%00") {
			return true
		}
		for _, segment := range strings.Split(value, "/") {
			if segment == ".." {
				return true
			}
		}
	}
	return false
}

func isWithinRoot(root, target string) bool {
	rel, err := filepath.Rel(root, target)
	if err != nil {
		return false
	}
	if rel == "." {
		return true
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return false
	}
	return !filepath.IsAbs(rel)
}
