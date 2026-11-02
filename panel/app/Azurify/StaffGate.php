<?php

namespace Pterodactyl\Azurify;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Pterodactyl\Models\User;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * AZURIFY staff permissions.
 *
 * Owners are root admins with no row in `azurify_staff`: they can do everything.
 * Staff are root admins with a row listing the permissions they were given, so the
 * panel's own root-admin checks let them in and this gate narrows what they can do.
 */
class StaffGate
{
    public const TABLE = 'azurify_staff';

    /** Permission key => [label, description] (order is the order shown on the Staff page). */
    public const PERMISSIONS = [
        'servers.view' => ['View all servers', 'See every server in the admin list and open any server\'s console, files and settings.'],
        'servers.create' => ['Create servers', 'Create new servers for any user.'],
        'servers.manage' => ['Edit servers', 'Change build limits, startup, databases, suspend, reinstall and transfer.'],
        'servers.delete' => ['Delete servers', 'Permanently delete servers.'],
        'users' => ['Manage users', 'Create, edit and delete normal (non-admin) users.'],
        'nests' => ['Manage eggs', 'Create, import and edit nests and eggs.'],
        'nodes' => ['Manage nodes', 'Nodes, locations and port allocations.'],
        'databases' => ['Database hosts', 'Add and edit database hosts.'],
        'mounts' => ['Mounts', 'Create and edit mounts.'],
        'settings' => ['Panel settings', 'General, mail and advanced panel settings.'],
        'api' => ['Application API', 'Create and revoke application API keys.'],
    ];

    /** @var array<int, array<string>|null> */
    private static array $cache = [];

    /**
     * Returns null for owners / non-admins, or the staff member's permission list.
     */
    public static function staffPermissions(?User $user): ?array
    {
        if (!$user || !$user->root_admin) {
            return null;
        }
        if (!array_key_exists($user->id, self::$cache)) {
            $row = Schema::hasTable(self::TABLE)
                ? DB::table(self::TABLE)->where('user_id', $user->id)->value('permissions')
                : null;
            self::$cache[$user->id] = $row === null ? null : (json_decode($row, true) ?: []);
        }

        return self::$cache[$user->id];
    }

    public static function isOwner(?User $user): bool
    {
        return $user !== null && $user->root_admin && self::staffPermissions($user) === null;
    }

    public static function isStaff(?User $user): bool
    {
        return $user !== null && $user->root_admin && self::staffPermissions($user) !== null;
    }

    public static function allows(?User $user, string $permission): bool
    {
        if (!$user || !$user->root_admin) {
            return false;
        }
        $perms = self::staffPermissions($user);

        return $perms === null || in_array($permission, $perms, true);
    }

    /**
     * Replacement for `$user->root_admin` wherever the panel decides that someone can
     * see and control every server (client area, client API, SFTP, websocket).
     */
    public static function seesAllServers(?User $user): bool
    {
        return self::allows($user, 'servers.view');
    }

    /**
     * Called from AdminAuthenticate for every /admin request.
     */
    public static function checkAdminRequest(Request $request): void
    {
        $user = $request->user();
        if (self::isOwner($user)) {
            return;
        }

        $segments = array_values(array_filter(explode('/', trim($request->path(), '/')), 'strlen'));
        $area = $segments[1] ?? '';
        $method = strtoupper($request->method());
        $isRead = in_array($method, ['GET', 'HEAD'], true);

        $permission = match ($area) {
            '' => null, // overview
            'servers' => self::serverPermission($segments, $isRead),
            'users' => 'users',
            'nests' => 'nests',
            'nodes', 'locations' => 'nodes',
            'databases' => 'databases',
            'mounts' => 'mounts',
            'settings' => 'settings',
            'api' => 'api',
            default => 'owner-only', // includes the Staff page itself
        };

        // The server create/edit forms look up owners from the users list.
        if ($area === 'users' && ($segments[2] ?? '') === 'accounts.json' && $isRead
            && (self::allows($user, 'servers.create') || self::allows($user, 'servers.manage'))) {
            $permission = null;
        }

        if ($permission !== null && !self::allows($user, $permission)) {
            throw new AccessDeniedHttpException('Your staff account does not have permission for this page.');
        }

        // Staff can manage normal users, but can never create or edit admins.
        if ($area === 'users' && !$isRead) {
            $target = $request->route('user');
            if ($target instanceof User && $target->root_admin) {
                throw new AccessDeniedHttpException('Only the panel owner can change admin or staff accounts.');
            }
            if ($request->has('root_admin')) {
                $request->merge(['root_admin' => 0]);
            }
        }
    }

    private static function serverPermission(array $segments, bool $isRead): string
    {
        $sub = $segments[2] ?? '';
        if ($sub === 'new') {
            return 'servers.create';
        }
        // /admin/servers/view/{id}/delete (both the confirm page and the POST)
        if ($sub === 'view' && ($segments[4] ?? '') === 'delete' && count($segments) === 5) {
            return 'servers.delete';
        }

        return $isRead ? 'servers.view' : 'servers.manage';
    }

    /**
     * Admin sidebar entries (by route) a staff member cannot open, for hiding them.
     */
    public static function hiddenMenuRoutes(?User $user): array
    {
        if (self::isOwner($user)) {
            return [];
        }
        $map = [
            'admin.settings' => 'settings',
            'admin.api.index' => 'api',
            'admin.databases' => 'databases',
            'admin.locations' => 'nodes',
            'admin.nodes' => 'nodes',
            'admin.servers' => 'servers.view',
            'admin.users' => 'users',
            'admin.mounts' => 'mounts',
            'admin.nests' => 'nests',
        ];

        return array_keys(array_filter($map, fn ($perm) => !self::allows($user, $perm)));
    }

    public static function forget(int $userId): void
    {
        unset(self::$cache[$userId]);
    }
}
