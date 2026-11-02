import React, { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Server } from '@/api/server/getServer';
import getServerResourceUsage, { ServerStats } from '@/api/server/getServerResourceUsage';
import { bytesToString, ip, mbToBytes } from '@/lib/formatters';
import styles from '@/components/azurify/dashboard.module.css';

type Timer = ReturnType<typeof setInterval>;

const percent = (used: number, limit: number) => (limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0);

const Meter = ({ label, value, pct }: { label: string; value: string; pct: number }) => (
    <div className={styles.meter}>
        <div className={styles.meterTop}>
            <span>{label}</span>
            <span>{value}</span>
        </div>
        <div className={styles.meterTrack}>
            <div className={pct >= 85 ? styles.meterHot : styles.meterFill} style={{ width: `${pct}%` }} />
        </div>
    </div>
);

export default ({ server }: { server: Server; className?: string }) => {
    const interval = useRef<Timer>(null) as React.MutableRefObject<Timer>;
    const [isSuspended, setIsSuspended] = useState(server.status === 'suspended');
    const [stats, setStats] = useState<ServerStats | null>(null);

    const getStats = () =>
        getServerResourceUsage(server.uuid)
            .then((data) => setStats(data))
            .catch((error) => console.error(error));

    useEffect(() => {
        setIsSuspended(stats?.isSuspended || server.status === 'suspended');
    }, [stats?.isSuspended, server.status]);

    useEffect(() => {
        if (isSuspended || server.isNodeUnderMaintenance) return;

        getStats().then(() => {
            interval.current = setInterval(() => getStats(), 30000);
        });

        return () => {
            interval.current && clearInterval(interval.current);
        };
    }, [isSuspended, server.isNodeUnderMaintenance]);

    const address = server.allocations
        .filter((alloc) => alloc.isDefault)
        .map((a) => `${a.alias || ip(a.ip)}:${a.port}`)
        .join(', ');

    let status: { label: string; tone: string };
    if (isSuspended) status = { label: 'Suspended', tone: styles.toneBad };
    else if (server.isNodeUnderMaintenance) status = { label: 'Maintenance', tone: styles.toneWarn };
    else if (server.isTransferring) status = { label: 'Transferring', tone: styles.toneWarn };
    else if (server.status === 'installing') status = { label: 'Installing', tone: styles.toneWarn };
    else if (server.status === 'restoring_backup') status = { label: 'Restoring', tone: styles.toneWarn };
    else if (!stats) status = { label: 'Checking', tone: styles.toneIdle };
    else if (stats.status === 'running') status = { label: 'Running', tone: styles.toneOk };
    else if (stats.status === 'starting') status = { label: 'Starting', tone: styles.toneWarn };
    else if (stats.status === 'stopping') status = { label: 'Stopping', tone: styles.toneWarn };
    else status = { label: 'Offline', tone: styles.toneIdle };

    const cpuLimit = server.limits.cpu;
    const memLimit = mbToBytes(server.limits.memory);
    const diskLimit = mbToBytes(server.limits.disk);

    return (
        <Link to={`/server/${server.id}`} className={styles.card}>
            <div className={styles.cardTop}>
                <div className={styles.cardTitle}>
                    <h3>{server.name}</h3>
                    <p>{server.description || `Hosted on ${server.node}`}</p>
                </div>
                <span className={`${styles.pill} ${status.tone}`}>{status.label}</span>
            </div>

            {stats && !isSuspended ? (
                <div className={styles.meters}>
                    <Meter label={'CPU'} value={`${stats.cpuUsagePercent.toFixed(0)}%`}
                           pct={cpuLimit ? percent(stats.cpuUsagePercent, cpuLimit) : 0} />
                    <Meter label={'RAM'} value={bytesToString(stats.memoryUsageInBytes)}
                           pct={percent(stats.memoryUsageInBytes, memLimit)} />
                    <Meter label={'Disk'} value={bytesToString(stats.diskUsageInBytes)}
                           pct={percent(stats.diskUsageInBytes, diskLimit)} />
                </div>
            ) : (
                <div className={styles.meters}>
                    <Meter label={'CPU'} value={cpuLimit ? `${cpuLimit}%` : '∞'} pct={0} />
                    <Meter label={'RAM'} value={server.limits.memory ? bytesToString(memLimit) : '∞'} pct={0} />
                    <Meter label={'Disk'} value={server.limits.disk ? bytesToString(diskLimit) : '∞'} pct={0} />
                </div>
            )}

            <div className={styles.cardFoot}>
                <span className={styles.mono}>{address || 'No address'}</span>
                <span className={styles.open}>Open &rarr;</span>
            </div>
        </Link>
    );
};
