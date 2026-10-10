<?php
declare(strict_types=1);

use App\Controllers\AdminController as A;
use App\Controllers\AuthController as Au;
use App\Controllers\OrderController as O;
use App\Controllers\PublicController as P;
use App\Router;

$r = new Router();

// ---------- عام ----------
$r->get('/health', [P::class, 'health']);
$r->get('/settings', [P::class, 'settings']);
$r->get('/categories', [P::class, 'categories']);
$r->get('/brands', [P::class, 'brands']);
$r->get('/equipment', [P::class, 'equipment']);
$r->get('/equipment/{slug:[a-z0-9\-]+}', [P::class, 'show']);
$r->get('/equipment/{slug:[a-z0-9\-]+}/availability', [P::class, 'availability']);
$r->get('/kits', [P::class, 'kits']);
$r->get('/app/config', [P::class, 'appConfig']);

// ---------- الطلبات ----------
$r->post('/orders', [O::class, 'create']);
$r->get('/orders/track', [O::class, 'track']);

// ---------- الحساب ----------
$r->post('/auth/register', [Au::class, 'register']);
$r->post('/auth/login', [Au::class, 'login']);
$r->post('/auth/logout', [Au::class, 'logout']);
$r->get('/auth/me', [Au::class, 'me']);
$r->patch('/auth/me', [Au::class, 'updateMe']);
$r->post('/auth/password', [Au::class, 'password']);
$r->delete('/auth/me', [Au::class, 'deleteMe']);
$r->post('/auth/delete-account', [Au::class, 'deleteByCredentials']);

$r->get('/me/orders', [O::class, 'mine']);
$r->get('/me/orders/{ref:GG-[A-Z0-9]+}', [O::class, 'mineOne']);
$r->post('/me/orders/{ref:GG-[A-Z0-9]+}/cancel', [O::class, 'cancel']);
$r->get('/me/favorites', [O::class, 'favorites']);
$r->post('/me/favorites/{slug:[a-z0-9\-]+}', [O::class, 'favAdd']);
$r->delete('/me/favorites/{slug:[a-z0-9\-]+}', [O::class, 'favRemove']);

// ---------- لوحة التحكم ----------
$r->get('/admin/stats', [A::class, 'stats']);
$r->get('/admin/system', [A::class, 'system']);
$r->get('/admin/orders', [A::class, 'orders']);
$r->get('/admin/orders/{id:\d+}', [A::class, 'order']);
$r->patch('/admin/orders/{id:\d+}', [A::class, 'updateOrder']);

$r->get('/admin/equipment', [A::class, 'equipment']);
$r->post('/admin/equipment', [A::class, 'createEquipment']);
$r->get('/admin/equipment/{id:\d+}', [A::class, 'showEquipment']);
$r->patch('/admin/equipment/{id:\d+}', [A::class, 'updateEquipment']);
$r->delete('/admin/equipment/{id:\d+}', [A::class, 'deleteEquipment']);
$r->post('/admin/equipment/{id:\d+}/image', [A::class, 'uploadImage']);
$r->delete('/admin/gallery/{img:\d+}', [A::class, 'deleteGalleryImage']);

$r->get('/admin/categories', [A::class, 'categories']);
$r->post('/admin/categories', [A::class, 'saveCategory']);
$r->patch('/admin/categories/{id:\d+}', [A::class, 'saveCategory']);
$r->delete('/admin/categories/{id:\d+}', [A::class, 'deleteCategory']);

$r->get('/admin/kits', [A::class, 'kits']);
$r->post('/admin/kits', [A::class, 'saveKit']);
$r->patch('/admin/kits/{id:\d+}', [A::class, 'saveKit']);
$r->delete('/admin/kits/{id:\d+}', [A::class, 'deleteKit']);

$r->get('/admin/users', [A::class, 'users']);
$r->post('/admin/users', [A::class, 'createUser']);
$r->patch('/admin/users/{id:\d+}', [A::class, 'updateUser']);

$r->get('/admin/settings', [A::class, 'settings']);
$r->put('/admin/settings', [A::class, 'saveSettings']);
$r->post('/admin/import', [A::class, 'import']);
$r->get('/admin/export', [A::class, 'export']);
$r->get('/admin/audit', [A::class, 'audit']);
$r->post('/admin/cache/clear', [A::class, 'clearCache']);

return $r;
