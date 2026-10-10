<?php
declare(strict_types=1);

namespace App;

final class Router
{
    private array $routes = [];

    public function add(string $method, string $pattern, callable|array $handler): self
    {
        $regex = '#^' . preg_replace_callback(
            '#\{([a-z_]+)(?::([^}]+))?\}#i',
            fn($m) => '(?P<' . $m[1] . '>' . (($m[2] ?? '') !== '' ? $m[2] : '[^/]+') . ')',
            $pattern
        ) . '$#';
        $this->routes[] = [$method, $regex, $handler, $pattern];
        return $this;
    }

    public function get(string $p, callable|array $h): self { return $this->add('GET', $p, $h); }
    public function post(string $p, callable|array $h): self { return $this->add('POST', $p, $h); }
    public function patch(string $p, callable|array $h): self { return $this->add('PATCH', $p, $h); }
    public function put(string $p, callable|array $h): self { return $this->add('PUT', $p, $h); }
    public function delete(string $p, callable|array $h): self { return $this->add('DELETE', $p, $h); }

    public function list(): array
    {
        return array_map(fn($r) => $r[0] . ' ' . $r[3], $this->routes);
    }

    public function dispatch(Request $req, string $path): void
    {
        $allowed = [];
        foreach ($this->routes as [$m, $re, $h]) {
            if (!preg_match($re, $path, $mm)) continue;
            if ($m !== $req->method) { $allowed[] = $m; continue; }
            $req->params = array_filter($mm, 'is_string', ARRAY_FILTER_USE_KEY);
            if (is_array($h)) {
                [$cls, $fn] = $h;
                (new $cls())->$fn($req);
            } else {
                $h($req);
            }
            return;
        }
        if ($allowed) {
            header('Allow: ' . implode(', ', array_unique($allowed)));
            throw new HttpError(405, 'method_not_allowed', 'الطريقة غير مسموحة');
        }
        throw new HttpError(404, 'not_found', 'المسار غير موجود');
    }
}
