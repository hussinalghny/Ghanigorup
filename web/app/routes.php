<?php
declare(strict_types=1);

use App\Controllers\AdminController as A;
use App\Controllers\AuthController as Au;
use App\Controllers\ContentController as Ct;
use App\Controllers\DeviceController as Dv;
use App\Controllers\HandoverController as H;
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
$r->get('/banners', [P::class, 'banners']);
$r->get('/notifications', [P::class, 'notifications']);
$r->post('/notifications/feed', [P::class, 'notifications']);
$r->post('/devices', [Dv::class, 'register']);
$r->delete('/devices', [Dv::class, 'remove']);

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
$r->post('/admin/orders/{id:\d+}/handover', [H::class, 'create']);
$r->get('/admin/handovers', [H::class, 'index']);
$r->get('/admin/handovers/board', [H::class, 'board']);
$r->get('/admin/handovers/{id:\d+}/signature', [H::class, 'signature']);
$r->get('/admin/staff', [A::class, 'staffList']);

$r->get('/admin/banners', [Ct::class, 'banners']);
$r->post('/admin/banners', [Ct::class, 'saveBanner']);
$r->post('/admin/banners/sort', [Ct::class, 'sortBanners']);
$r->patch('/admin/banners/{id:\d+}', [Ct::class, 'saveBanner']);
$r->delete('/admin/banners/{id:\d+}', [Ct::class, 'deleteBanner']);
$r->post('/admin/banners/{id:\d+}/image', [Ct::class, 'bannerImage']);

$r->get('/admin/brands', [Ct::class, 'brands']);
$r->post('/admin/brands', [Ct::class, 'saveBrand']);
$r->post('/admin/brands/sync', [Ct::class, 'syncBrands']);
$r->patch('/admin/brands/{id:\d+}', [Ct::class, 'saveBrand']);
$r->delete('/admin/brands/{id:\d+}', [Ct::class, 'deleteBrand']);
$r->post('/admin/brands/{id:\d+}/logo', [Ct::class, 'brandLogo']);

$r->get('/admin/notifications', [Ct::class, 'notifications']);
$r->post('/admin/notifications', [Ct::class, 'sendNotification']);
$r->delete('/admin/notifications/{id:\d+}', [Ct::class, 'deleteNotification']);

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
$r->post('/admin/settings/image', [Ct::class, 'settingImage']);
$r->get('/admin/firebase', [Ct::class, 'firebase']);
$r->post('/admin/firebase', [Ct::class, 'saveFirebase']);
$r->delete('/admin/firebase', [Ct::class, 'deleteFirebase']);
$r->post('/admin/firebase/test', [Ct::class, 'testFirebase']);
$r->post('/admin/import', [A::class, 'import']);
$r->get('/admin/export', [A::class, 'export']);
$r->get('/admin/audit', [A::class, 'audit']);
$r->post('/admin/cache/clear', [A::class, 'clearCache']);

return $r;
