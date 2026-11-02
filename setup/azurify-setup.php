<?php
/*
 * AZURIFY Host - post-install setup. Safe to run again.
 *   php azurify-setup.php <panel_dir> <src_dir> <admin_username> <credentials_file>
 *
 * 1. Imports (or updates) the AzuRaya eggs into an "AzuRaya" nest.
 * 2. Removes the stock Minecraft / Rust / Source / Voice nests when no server uses them,
 *    and stops `migrate --seed` from bringing them back.
 * 3. Creates the "dezioapplicationapi" (application) and "dezioclientapi" (client) API keys
 *    for the admin user and writes them to the credentials file.
 * 4. Installs the AZURIFY staff permission system (Admin > Staff).
 */

[$self, $panelDir, $srcDir, $adminUser, $credFile] = array_pad($argv, 5, null);
if (!$panelDir || !$srcDir || !$adminUser || !$credFile) {
    fwrite(STDERR, "usage: php $self <panel_dir> <src_dir> <admin_username> <credentials_file>\n");
    exit(2);
}
$eggsDir = rtrim($srcDir, '/') . '/eggs';

// copy the AZURIFY panel additions (staff gate, controller, view) before Laravel boots
$addDir = rtrim($srcDir, '/') . '/panel';
if (is_dir($addDir)) {
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($addDir, FilesystemIterator::SKIP_DOTS));
    foreach ($it as $file) {
        $dest = $panelDir . '/' . substr($file->getPathname(), strlen($addDir) + 1);
        @mkdir(dirname($dest), 0755, true);
        copy($file->getPathname(), $dest);
    }
}

require $panelDir . '/vendor/autoload.php';
$app = require $panelDir . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Pterodactyl\Models\ApiKey;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;
use Pterodactyl\Services\Api\KeyCreationService;
use Pterodactyl\Services\Eggs\Sharing\EggImporterService;
use Pterodactyl\Services\Eggs\Sharing\EggUpdateImporterService;
use Pterodactyl\Services\Nests\NestCreationService;

const AUTHOR = 'azurifydigitalsolutions@gmail.com';
const NEST_NAME = 'AzuRaya';
const APP_KEY_MEMO = 'dezioapplicationapi';
const CLIENT_KEY_MEMO = 'dezioclientapi';

function say(string $m): void { fwrite(STDOUT, "  $m\n"); }

$failures = [];

// ---------------------------------------------------------------- 1. AzuRaya eggs
try {
    $nest = Nest::query()->where('name', NEST_NAME)->first()
        ?? $app->make(NestCreationService::class)->handle([
            'name' => NEST_NAME,
            'description' => 'AzuRaya websites, dashboards and bots by AZURIFY.',
        ], AUTHOR);

    $files = glob(rtrim($eggsDir, '/') . '/*.json') ?: [];
    if (!$files) {
        $failures[] = "No egg files found in $eggsDir";
    }
    foreach ($files as $path) {
        $name = json_decode(file_get_contents($path), true)['name'] ?? basename($path);
        $upload = new UploadedFile($path, basename($path), 'application/json', null, true);
        $existing = Egg::query()->where('nest_id', $nest->id)->where('name', $name)->first();
        if ($existing) {
            $app->make(EggUpdateImporterService::class)->handle($existing, $upload);
            say("egg updated:  $name");
        } else {
            $app->make(EggImporterService::class)->handle($upload, $nest->id);
            say("egg imported: $name");
        }
    }
} catch (Throwable $e) {
    $failures[] = 'Egg import failed: ' . $e->getMessage();
}

// ---------------------------------------------------------------- 2. remove stock nests
try {
    $stock = Nest::query()->where('author', 'support@pterodactyl.io')->get();
    foreach ($stock as $n) {
        $eggIds = Egg::query()->where('nest_id', $n->id)->pluck('id');
        if (Server::query()->where('nest_id', $n->id)->orWhereIn('egg_id', $eggIds)->exists()) {
            say("kept nest '{$n->name}' (servers still use it)");
            continue;
        }
        DB::transaction(function () use ($n, $eggIds) {
            Egg::query()->whereIn('config_from', $eggIds)->update(['config_from' => null]);
            Egg::query()->whereIn('copy_script_from', $eggIds)->update(['copy_script_from' => null]);
            DB::table('egg_variables')->whereIn('egg_id', $eggIds)->delete();
            Egg::query()->whereIn('id', $eggIds)->delete();
            $n->delete();
        });
        say("removed nest: {$n->name}");
    }

    // panel updates run `migrate --seed`; keep the stock eggs from coming back
    $seeder = $panelDir . '/database/Seeders/DatabaseSeeder.php';
    if (is_file($seeder)) {
        $src = file_get_contents($seeder);
        $patched = str_replace(
            ['        $this->call(NestSeeder::class);', '        $this->call(EggSeeder::class);'],
            ['        // $this->call(NestSeeder::class); // disabled by AZURIFY', '        // $this->call(EggSeeder::class); // disabled by AZURIFY'],
            $src
        );
        if ($patched !== $src) {
            file_put_contents($seeder, $patched);
            say('stock egg seeder disabled');
        }
    }
} catch (Throwable $e) {
    $failures[] = 'Removing stock eggs failed: ' . $e->getMessage();
}

// ---------------------------------------------------------------- 3. API keys
$keys = [];
try {
    $user = User::query()->where('username', $adminUser)->first();
    if (!$user) {
        throw new RuntimeException("admin user '$adminUser' not found");
    }

    $find = fn (int $type, string $memo) => ApiKey::query()
        ->where('user_id', $user->id)->where('key_type', $type)->where('memo', $memo)->first();

    $app_key = $find(ApiKey::TYPE_APPLICATION, APP_KEY_MEMO);
    if (!$app_key) {
        $perms = [];
        foreach (['users', 'allocations', 'database_hosts', 'server_databases', 'eggs', 'locations', 'nests', 'nodes', 'servers'] as $r) {
            $perms["r_$r"] = 3; // read + write
        }
        $app_key = $app->make(KeyCreationService::class)->setKeyType(ApiKey::TYPE_APPLICATION)
            ->handle(['user_id' => $user->id, 'memo' => APP_KEY_MEMO, 'allowed_ips' => []], $perms);
        say('application API key created: ' . APP_KEY_MEMO);
    } else {
        say('application API key already exists: ' . APP_KEY_MEMO);
    }

    $client_key = $find(ApiKey::TYPE_ACCOUNT, CLIENT_KEY_MEMO);
    if (!$client_key) {
        $client_key = $app->make(KeyCreationService::class)->setKeyType(ApiKey::TYPE_ACCOUNT)
            ->handle(['user_id' => $user->id, 'memo' => CLIENT_KEY_MEMO, 'allowed_ips' => []]);
        say('client API key created: ' . CLIENT_KEY_MEMO);
    } else {
        say('client API key already exists: ' . CLIENT_KEY_MEMO);
    }

    $keys[APP_KEY_MEMO] = $app_key->identifier . decrypt($app_key->token);
    $keys[CLIENT_KEY_MEMO] = $client_key->identifier . decrypt($client_key->token);
} catch (Throwable $e) {
    $failures[] = 'API key creation failed: ' . $e->getMessage();
}

// ---------------------------------------------------------------- 4. staff permissions
try {
    if (!Illuminate\Support\Facades\Schema::hasTable('azurify_staff')) {
        Illuminate\Support\Facades\Schema::create('azurify_staff', function (Illuminate\Database\Schema\Blueprint $t) {
            $t->unsignedInteger('user_id')->primary();
            $t->text('permissions');
            $t->timestamps();
            $t->foreign('user_id')->references('id')->on('users')->onDelete('cascade');
        });
        say('staff table created');
    }

    $gate = '\Pterodactyl\Azurify\StaffGate';
    $patches = [
        'app/Http/Middleware/AdminAuthenticate.php' => [
            ["            throw new AccessDeniedHttpException();\n        }\n\n        return \$next(\$request);",
             "            throw new AccessDeniedHttpException();\n        }\n\n        {$gate}::checkAdminRequest(\$request);\n\n        return \$next(\$request);"],
        ],
        'app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php' => [
            ['if ($user->id !== $server->owner_id && !$user->root_admin) {', "if (\$user->id !== \$server->owner_id && !{$gate}::seesAllServers(\$user)) {"],
            ['if (!$user->root_admin || !$request->routeIs($this->except)) {', "if (!{$gate}::seesAllServers(\$user) || !\$request->routeIs(\$this->except)) {"],
        ],
        'app/Http/Controllers/Api/Client/ClientController.php' => [
            ['            if (!$user->root_admin) {', "            if (!{$gate}::seesAllServers(\$user)) {"],
        ],
        'app/Policies/ServerPolicy.php' => [
            ['if ($user->root_admin || $server->owner_id === $user->id) {', "if ({$gate}::seesAllServers(\$user) || \$server->owner_id === \$user->id) {"],
        ],
        'app/Services/Servers/GetUserPermissionsService.php' => [
            ['if ($user->root_admin || $user->id === $server->owner_id) {', "if ({$gate}::seesAllServers(\$user) || \$user->id === \$server->owner_id) {"],
            ['            if ($user->root_admin) {', "            if ({$gate}::seesAllServers(\$user)) {"],
        ],
        'app/Http/Controllers/Api/Remote/SftpAuthenticationController.php' => [
            ['if (!$user->root_admin && $server->owner_id !== $user->id) {', "if (!{$gate}::seesAllServers(\$user) && \$server->owner_id !== \$user->id) {"],
        ],
        'app/Http/Middleware/Api/Application/AuthenticateApplicationUser.php' => [
            ['if (!$user || !$user->root_admin) {', "if (!\$user || !{$gate}::allows(\$user, 'api')) {"],
        ],
        'resources/views/layouts/admin.blade.php' => [
            ['                        <li class="header">SERVICE MANAGEMENT</li>',
             "                        @if({$gate}::isOwner(Auth::user()))\n" .
             "                        <li class=\"{{ ! starts_with(Route::currentRouteName(), 'admin.azurify.staff') ?: 'active' }}\">\n" .
             "                            <a href=\"{{ route('admin.azurify.staff') }}\">\n" .
             "                                <i class=\"fa fa-id-badge\"></i> <span>Staff</span>\n" .
             "                            </a>\n" .
             "                        </li>\n" .
             "                        @endif\n" .
             '                        <li class="header">SERVICE MANAGEMENT</li>'],
            ['        <div class="wrapper">',
             "        @php(\$azHidden = {$gate}::hiddenMenuRoutes(Auth::user()))\n" .
             "        @if(count(\$azHidden))<style>@foreach(\$azHidden as \$azRoute).sidebar-menu li:has(> a[href=\"{{ route(\$azRoute) }}\"])@if(!\$loop->last),@endif @endforeach{display:none!important}</style>@endif\n" .
             '        <div class="wrapper">'],
        ],
    ];
    foreach ($patches as $rel => $pairs) {
        $path = $panelDir . '/' . $rel;
        $src = @file_get_contents($path);
        if ($src === false) {
            $failures[] = "Staff patch: $rel not found";
            continue;
        }
        if (str_contains($src, 'Azurify\StaffGate')) {
            continue; // already patched
        }
        foreach ($pairs as [$from, $to]) {
            if (!str_contains($src, $from)) {
                $failures[] = "Staff patch: expected code not found in $rel (panel version changed?)";
                continue 2;
            }
            $src = str_replace($from, $to, $src);
        }
        file_put_contents($path, $src);
        say("patched $rel");
    }

    $routes = $panelDir . '/routes/admin.php';
    $r = file_get_contents($routes);
    if (!str_contains($r, 'AzurifyStaffController')) {
        $r .= "\n/*\n| AZURIFY staff permissions (owner only, enforced by StaffGate)\n*/\n" .
            "Route::group(['prefix' => 'azurify/staff'], function () {\n" .
            "    Route::get('/', [Admin\\AzurifyStaffController::class, 'index'])->name('admin.azurify.staff');\n" .
            "    Route::post('/{user:id}', [Admin\\AzurifyStaffController::class, 'update'])->name('admin.azurify.staff.update');\n" .
            "});\n";
        file_put_contents($routes, $r);
        say('staff routes added');
    }
} catch (Throwable $e) {
    $failures[] = 'Staff permissions setup failed: ' . $e->getMessage();
}

if ($keys) {
    $out = "# AZURIFY Host API keys (keep private)\n";
    foreach ($keys as $memo => $token) {
        $out .= "$memo=$token\n";
    }
    file_put_contents($credFile, $out);
    chmod($credFile, 0600);
}

foreach ($failures as $f) {
    fwrite(STDERR, "  PROBLEM: $f\n");
}
exit($failures ? 1 : 0);
