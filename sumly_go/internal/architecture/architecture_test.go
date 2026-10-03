package architecture_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"reflect"
	"runtime"
	"strconv"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

func TestMarketReadAndWriteCapabilitiesStaySeparate(t *testing.T) {
	for _, value := range []any{(*postgres.Reader)(nil), (*application.GoldQuery)(nil), (*ports.GoldReadStore)(nil)} {
		typ := reflect.TypeOf(value)
		if typ.Elem().Kind() == reflect.Interface {
			typ = typ.Elem()
		}
		for i := 0; i < typ.NumMethod(); i++ {
			name := typ.Method(i).Name
			for _, prefix := range []string{"Save", "Prune", "Seed", "Collect", "Sample", "Try", "Finish"} {
				if strings.HasPrefix(name, prefix) {
					t.Errorf("reader %s exposes mutation %s", typ, name)
				}
			}
		}
	}
	for _, value := range []any{(*postgres.Writer)(nil), (*application.GoldCollector)(nil), (*ports.GoldWriteStore)(nil)} {
		typ := reflect.TypeOf(value)
		if typ.Elem().Kind() == reflect.Interface {
			typ = typ.Elem()
		}
		for i := 0; i < typ.NumMethod(); i++ {
			name := typ.Method(i).Name
			if strings.HasPrefix(name, "Get") || strings.HasPrefix(name, "Load") || name == "SyncHistory" {
				t.Errorf("writer %s exposes query %s", typ, name)
			}
		}
	}
}
func TestHexagonalCoreImportsAndMarketDependencies(t *testing.T) {
	_, source, _, _ := runtime.Caller(0)
	root := filepath.Dir(filepath.Dir(source))
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		parts := strings.Split(filepath.ToSlash(rel), "/")
		if len(parts) < 3 {
			return nil
		}
		layer := parts[1]
		if layer != "domain" && layer != "application" && layer != "ports" {
			return nil
		}
		file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
		if err != nil {
			return err
		}
		for _, imp := range file.Imports {
			name, err := strconv.Unquote(imp.Path.Value)
			if err != nil {
				return err
			}
			if strings.Contains(name, "/adapters/") || strings.Contains(name, "/bootstrap") || strings.HasPrefix(name, "github.com/") || strings.HasPrefix(name, "golang.org/") || ((layer == "domain" || layer == "ports") && strings.Contains(name, "/application")) {
				t.Errorf("core dependency violation %s -> %s", rel, name)
			}
			if parts[0] == "holdings" && layer == "application" && name == "encoding/json" {
				t.Errorf("holdings application owns JSON encoding: %s", rel)
			}
		}
		if parts[0] != "market" || layer != "application" {
			return nil
		}
		ast.Inspect(file, func(node ast.Node) bool {
			spec, ok := node.(*ast.TypeSpec)
			if !ok {
				return true
			}
			if spec.Name.Name != "GoldQuery" && spec.Name.Name != "GoldCollector" {
				return true
			}
			model, ok := spec.Type.(*ast.StructType)
			if !ok {
				return true
			}
			for _, field := range model.Fields.List {
				selector, ok := field.Type.(*ast.SelectorExpr)
				if ok {
					name := selector.Sel.Name
					if spec.Name.Name == "GoldQuery" && name != "GoldReadStore" {
						t.Errorf("GoldQuery depends on %s", name)
					}
					if spec.Name.Name == "GoldCollector" && (strings.Contains(name, "Reader") || strings.Contains(name, "ReadStore")) {
						t.Errorf("GoldCollector depends on reader %s", name)
					}
				}
				ptr, ok := field.Type.(*ast.StarExpr)
				if ok {
					if typ, ok := ptr.X.(*ast.Ident); ok && (typ.Name == "GoldQuery" || typ.Name == "GoldCollector") {
						t.Errorf("%s directly depends on %s", spec.Name.Name, typ.Name)
					}
				}
			}
			return true
		})
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
