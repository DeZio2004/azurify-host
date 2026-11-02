<?php
/*
 * AZURIFY Host - add port ranges to a node, the same way Admin > Nodes > Allocation does.
 *   php azurify-ports.php <panel_dir> <node_id> <ip> <alias> <from-to> [<from-to> ...]
 *
 * The panel itself only accepts ports above 1024; lower ports (the installer has already
 * checked they don't clash with SSH, the panel, node or SFTP) are inserted directly.
 */

$args = array_pad($argv, 6, null);
[$self, $panelDir, $nodeId, $ip, $alias] = $args;
$ranges = array_slice($argv, 5);
if (!$panelDir || !$nodeId || !$ip || !$ranges) {
    fwrite(STDERR, "usage: php $self <panel_dir> <node_id> <ip> <alias> <from-to> [<from-to> ...]\n");
    exit(2);
}

require $panelDir . '/vendor/autoload.php';
$app = require $panelDir . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$failed = false;
$node = Pterodactyl\Models\Node::query()->find((int) $nodeId);
if (!$node) {
    fwrite(STDERR, "  PROBLEM: node $nodeId not found\n");
    exit(1);
}

foreach ($ranges as $range) {
    if (!preg_match('/^(\d{1,5})(?:-(\d{1,5}))?$/', $range, $m)) {
        fwrite(STDERR, "  PROBLEM: '$range' is not a port or range\n");
        $failed = true;
        continue;
    }
    $from = (int) $m[1];
    $to = isset($m[2]) ? (int) $m[2] : $from;

    try {
        if ($from > 1024) {
            $app->make(Pterodactyl\Services\Allocations\AssignmentService::class)->handle($node, [
                'allocation_ip' => $ip,
                'allocation_alias' => $alias ?: null,
                'allocation_ports' => [$from === $to ? (string) $from : "$from-$to"],
            ]);
        } else {
            $rows = [];
            foreach (range($from, $to) as $port) {
                $rows[] = ['node_id' => $node->id, 'ip' => $ip, 'port' => $port, 'ip_alias' => $alias ?: null, 'server_id' => null];
            }
            Illuminate\Support\Facades\DB::table('allocations')->insertOrIgnore($rows);
        }
        fwrite(STDOUT, "  ports $from-$to added\n");
    } catch (Throwable $e) {
        fwrite(STDERR, "  PROBLEM: ports $from-$to: " . $e->getMessage() . "\n");
        $failed = true;
    }
}

exit($failed ? 1 : 0);
