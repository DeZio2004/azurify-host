<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Http\Request;
use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\DB;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Azurify\StaffGate;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Models\User;

/**
 * Owner-only page for giving users staff access with per-user permissions.
 * Access is limited to owners by StaffGate (the "azurify" admin area is owner-only).
 */
class AzurifyStaffController extends Controller
{
    public function __construct(private AlertsMessageBag $alert)
    {
    }

    public function index(): View
    {
        $staff = DB::table(StaffGate::TABLE)->pluck('permissions', 'user_id')
            ->map(fn ($p) => json_decode($p, true) ?: []);

        $users = User::query()->orderByDesc('root_admin')->orderBy('username')->get()
            ->map(function (User $user) use ($staff) {
                $user->setAttribute('az_role', !$user->root_admin ? 'none' : ($staff->has($user->id) ? 'staff' : 'owner'));
                $user->setAttribute('az_perms', $staff->get($user->id, []));

                return $user;
            });

        return view('admin.azurify.staff', [
            'users' => $users,
            'permissions' => StaffGate::PERMISSIONS,
        ]);
    }

    public function update(Request $request, User $user): RedirectResponse
    {
        $data = $request->validate([
            'role' => 'required|in:none,staff,owner',
            'permissions' => 'array',
            'permissions.*' => 'string|in:' . implode(',', array_keys(StaffGate::PERMISSIONS)),
        ]);

        if ($user->id === $request->user()->id) {
            $this->alert->danger('You cannot change your own role (so you never lock yourself out).')->flash();

            return redirect()->route('admin.azurify.staff');
        }

        DB::transaction(function () use ($user, $data) {
            DB::table('users')->where('id', $user->id)->update(['root_admin' => $data['role'] === 'none' ? 0 : 1]);

            if ($data['role'] === 'staff') {
                DB::table(StaffGate::TABLE)->updateOrInsert(
                    ['user_id' => $user->id],
                    ['permissions' => json_encode(array_values($data['permissions'] ?? [])), 'updated_at' => now(), 'created_at' => now()]
                );
            } else {
                DB::table(StaffGate::TABLE)->where('user_id', $user->id)->delete();
            }
        });
        StaffGate::forget($user->id);

        $label = ['none' => 'a normal user', 'staff' => 'staff', 'owner' => 'an owner'][$data['role']];
        $this->alert->success("{$user->username} is now {$label}.")->flash();

        return redirect()->route('admin.azurify.staff');
    }
}
