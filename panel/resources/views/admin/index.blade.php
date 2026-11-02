@extends('layouts.admin')

@section('title')
    Control center
@endsection

@php
    $azServers = \Pterodactyl\Models\Server::query();
    $azServerCount = (clone $azServers)->count();
    $azSuspended = (clone $azServers)->where('status', 'suspended')->count();
    $azUsers = \Pterodactyl\Models\User::query()->count();
    $azStaff = \Illuminate\Support\Facades\Schema::hasTable('azurify_staff') ? \Illuminate\Support\Facades\DB::table('azurify_staff')->count() : 0;
    $azOwners = \Pterodactyl\Models\User::query()->where('root_admin', true)->count() - $azStaff;
    $azEggs = \Pterodactyl\Models\Egg::query()->count();
    $azNodes = \Pterodactyl\Models\Node::query()->withCount('servers')->get()->map(function ($node) {
        $alloc = \Illuminate\Support\Facades\DB::table('servers')->where('node_id', $node->id)->selectRaw('COALESCE(SUM(memory),0) m, COALESCE(SUM(disk),0) d')->first();
        $ports = \Illuminate\Support\Facades\DB::table('allocations')->where('node_id', $node->id)->selectRaw('COUNT(*) total, SUM(server_id IS NULL) free')->first();
        $node->az_mem_pct = $node->memory > 0 ? min(100, (int) round($alloc->m / $node->memory * 100)) : 0;
        $node->az_disk_pct = $node->disk > 0 ? min(100, (int) round($alloc->d / $node->disk * 100)) : 0;
        $node->az_mem = $alloc->m;
        $node->az_disk = $alloc->d;
        $node->az_ports_total = (int) $ports->total;
        $node->az_ports_free = (int) $ports->free;
        return $node;
    });
    $azActivity = \Pterodactyl\Models\ActivityLog::query()->with('actor')->orderByDesc('timestamp')->limit(8)->get();
    $azStaffList = \Illuminate\Support\Facades\Schema::hasTable('azurify_staff')
        ? \Illuminate\Support\Facades\DB::table('azurify_staff')->join('users', 'users.id', '=', 'azurify_staff.user_id')->select('users.username', 'users.email', 'azurify_staff.permissions')->limit(6)->get()
        : collect();
    $azLabels = \Pterodactyl\Azurify\StaffGate::PERMISSIONS;
@endphp

@section('content-header')
    <h1>Control center<small>Everything running on {{ config('app.name') }}, at a glance.</small></h1>
@endsection

@section('content')
<div class="az-cc">
    <div class="az-cc-actions">
        @if(\Pterodactyl\Azurify\StaffGate::allows(Auth::user(), 'servers.create'))
            <a href="{{ route('admin.servers.new') }}" class="btn btn-primary">+ Create server</a>
        @endif
        @if(\Pterodactyl\Azurify\StaffGate::isOwner(Auth::user()))
            <a href="{{ route('admin.azurify.staff') }}" class="btn btn-default">Manage staff</a>
        @endif
        <a href="/" class="btn btn-default">Open client view</a>
    </div>

    <div class="az-kpis">
        <div class="az-kpi"><span>Servers</span><strong>{{ $azServerCount }}</strong><small>{{ $azSuspended }} suspended</small></div>
        <div class="az-kpi"><span>Users</span><strong>{{ $azUsers }}</strong><small>{{ $azOwners }} owner{{ $azOwners === 1 ? '' : 's' }}, {{ $azStaff }} staff</small></div>
        <div class="az-kpi"><span>App templates</span><strong>{{ $azEggs }}</strong><small>AzuRaya eggs</small></div>
        <div class="az-kpi"><span>Panel version</span><strong>{{ config('app.version') }}</strong>
            <small>{{ $version->isLatestPanel() ? 'up to date' : 'update available: ' . $version->getPanel() }}</small></div>
    </div>

    <div class="az-row">
        <section class="az-card az-grow">
            <h2>Nodes</h2>
            @forelse($azNodes as $node)
                <div class="az-node">
                    <div class="az-node-head">
                        <a href="{{ route('admin.nodes.view', $node->id) }}"><strong>{{ $node->name }}</strong></a>
                        <span class="text-muted">{{ $node->fqdn }}</span>
                        <span class="label {{ $node->maintenance_mode ? 'label-warning' : 'label-success' }}">{{ $node->maintenance_mode ? 'Maintenance' : 'Active' }}</span>
                    </div>
                    <div class="az-meter"><div class="az-meter-top"><span>Memory allocated</span><span>{{ number_format($node->az_mem) }} / {{ number_format($node->memory) }} MiB</span></div>
                        <div class="az-track"><div class="{{ $node->az_mem_pct >= 85 ? 'az-hot' : 'az-fill' }}" style="width: {{ $node->az_mem_pct }}%"></div></div></div>
                    <div class="az-meter"><div class="az-meter-top"><span>Disk allocated</span><span>{{ number_format($node->az_disk) }} / {{ number_format($node->disk) }} MiB</span></div>
                        <div class="az-track"><div class="{{ $node->az_disk_pct >= 85 ? 'az-hot' : 'az-fill' }}" style="width: {{ $node->az_disk_pct }}%"></div></div></div>
                    <p class="text-muted az-small">{{ $node->servers_count }} server{{ $node->servers_count === 1 ? '' : 's' }} &middot; ports free: {{ $node->az_ports_free }} of {{ $node->az_ports_total }}</p>
                </div>
            @empty
                <p class="text-muted">No nodes yet.</p>
            @endforelse
        </section>

        <section class="az-card az-side">
            <h2>Staff</h2>
            @forelse($azStaffList as $member)
                @php($perms = json_decode($member->permissions, true) ?: [])
                <div class="az-person">
                    <span class="az-initial">{{ strtoupper(substr($member->username, 0, 1)) }}</span>
                    <div>
                        <strong>{{ $member->username }}</strong>
                        <small>{{ count($perms) ? implode(', ', array_map(fn ($p) => $azLabels[$p][0] ?? $p, $perms)) : 'No permissions yet' }}</small>
                    </div>
                </div>
            @empty
                <p class="text-muted">No staff yet. Owners can add staff from the Staff page.</p>
            @endforelse
        </section>
    </div>

    <section class="az-card">
        <h2>Recent activity</h2>
        <div class="table-responsive">
            <table class="table">
                <thead><tr><th>When</th><th>Who</th><th>What</th><th>From</th></tr></thead>
                <tbody>
                @forelse($azActivity as $log)
                    <tr>
                        <td class="text-muted">{{ $log->timestamp->diffForHumans() }}</td>
                        <td>{{ optional($log->actor)->username ?? 'System' }}</td>
                        <td><code>{{ $log->event }}</code></td>
                        <td class="text-muted">{{ $log->ip }}</td>
                    </tr>
                @empty
                    <tr><td colspan="4" class="text-muted">No activity yet.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
    </section>
</div>
@endsection
