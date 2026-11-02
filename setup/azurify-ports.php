<?php
/*
 * AZURIFY Host - add a port range to a node, the same way Admin > Nodes > Allocation does.
 *   php azurify-ports.php <panel_dir> <node_id> <ip> <alias> <from-to>
 */

[$self, $panelDir, $nodeId, $ip, $alias, $ports] = array_pad($argv, 6, null);
if (!$panelDir || !$nodeId || !$ip || !$ports) {
    fwrite(STDERR, "usage: php $self <panel_dir> <node_id> <ip> <alias> <from-to>\n");
    exit(2);
}

require $panelDir . '/vendor/autoload.php';
$app = require $panelDir . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

try {
    $node = Pterodactyl\Models\Node::query()->findOrFail((int) $nodeId);
    $app->make(Pterodactyl\Services\Allocations\AssignmentService::class)->handle($node, [
        'allocation_ip' => $ip,
        'allocation_alias' => $alias ?: null,
        'allocation_ports' => [$ports],
    ]);
} catch (Throwable $e) {
    fwrite(STDERR, '  PROBLEM: ' . $e->getMessage() . "\n");
    exit(1);
}
