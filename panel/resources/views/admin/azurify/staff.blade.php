@extends('layouts.admin')

@section('title')
    Staff & Permissions
@endsection

@section('content-header')
    <h1>Staff<small>Give users access to the control panel, permission by permission.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li class="active">Staff</li>
    </ol>
@endsection

@section('content')
<div class="row">
    <div class="col-xs-12">
        <div class="callout callout-info">
            <strong>Owner</strong> can do everything. <strong>Staff</strong> can only use the permissions you tick.
            <strong>User</strong> only sees their own servers. Create the account first under
            <a href="{{ route('admin.users.new') }}">Users &rarr; Create New</a>, then set its role here.
        </div>
    </div>
</div>
<div class="row az-staff-grid">
    @foreach($users as $u)
        <div class="col-md-6 col-lg-4">
            <form method="POST" action="{{ route('admin.azurify.staff.update', $u->id) }}" class="box az-staff-card" data-role="{{ $u->az_role }}">
                @csrf
                <div class="box-header with-border">
                    <h3 class="box-title">
                        {{ $u->username }}
                        <span class="label az-role-badge label-{{ ['owner' => 'success', 'staff' => 'primary', 'none' => 'default'][$u->az_role] }}">
                            {{ ['owner' => 'Owner', 'staff' => 'Staff', 'none' => 'User'][$u->az_role] }}
                        </span>
                    </h3>
                    <p class="text-muted small no-margin">{{ $u->email }}</p>
                </div>
                <div class="box-body">
                    @if($u->id === Auth::user()->id)
                        <p class="text-muted">This is you. Your own role cannot be changed here.</p>
                    @else
                        <div class="form-group">
                            <label>Role</label>
                            <select name="role" class="form-control az-role-select">
                                <option value="none" @selected($u->az_role === 'none')>User (own servers only)</option>
                                <option value="staff" @selected($u->az_role === 'staff')>Staff (pick permissions)</option>
                                <option value="owner" @selected($u->az_role === 'owner')>Owner (full access)</option>
                            </select>
                        </div>
                        <div class="az-perms">
                            @foreach($permissions as $key => [$label, $help])
                                <label class="az-perm" title="{{ $help }}">
                                    <input type="checkbox" name="permissions[]" value="{{ $key }}" @checked(in_array($key, $u->az_perms))>
                                    <span><strong>{{ $label }}</strong><small>{{ $help }}</small></span>
                                </label>
                            @endforeach
                        </div>
                    @endif
                </div>
                @if($u->id !== Auth::user()->id)
                    <div class="box-footer">
                        <button type="submit" class="btn btn-sm btn-primary pull-right">Save</button>
                    </div>
                @endif
            </form>
        </div>
    @endforeach
</div>
@endsection

@section('footer-scripts')
    @parent
    <style>
        .az-staff-grid { display: flex; flex-wrap: wrap; }
        .az-staff-grid > div { display: flex; }
        .az-staff-card { width: 100%; }
        .az-role-badge { margin-left: 8px; vertical-align: middle; }
        .az-perms { display: grid; gap: 8px; }
        .az-perm { display: flex; gap: 10px; align-items: flex-start; font-weight: 400; margin: 0; padding: 8px 10px;
                   border-radius: 10px; background: rgba(255,255,255,.04); cursor: pointer; }
        .az-perm input { margin-top: 3px; }
        .az-perm strong { display: block; font-weight: 600; }
        .az-perm small { display: block; opacity: .7; }
        .az-staff-card:not([data-role="staff"]) .az-perms { display: none; }
    </style>
    <script>
        document.querySelectorAll('.az-role-select').forEach(function (s) {
            s.addEventListener('change', function () { s.closest('.az-staff-card').dataset.role = s.value; });
        });
    </script>
@endsection
