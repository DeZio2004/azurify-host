import React, { useEffect, useMemo, useState } from 'react';
import { Server } from '@/api/server/getServer';
import getServers from '@/api/getServers';
import ServerRow from '@/components/dashboard/ServerRow';
import Spinner from '@/components/elements/Spinner';
import PageContentBlock from '@/components/elements/PageContentBlock';
import useFlash from '@/plugins/useFlash';
import { useStoreState } from 'easy-peasy';
import { usePersistedState } from '@/plugins/usePersistedState';
import useSWR from 'swr';
import { PaginatedResult } from '@/api/http';
import Pagination from '@/components/elements/Pagination';
import { useLocation } from 'react-router-dom';
import { bytesToString, mbToBytes } from '@/lib/formatters';
import styles from '@/components/azurify/dashboard.module.css';

const greeting = () => {
    const h = new Date().getHours();
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
};

export default () => {
    const { search } = useLocation();
    const defaultPage = Number(new URLSearchParams(search).get('page') || '1');

    const [page, setPage] = useState(!isNaN(defaultPage) && defaultPage > 0 ? defaultPage : 1);
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const uuid = useStoreState((state) => state.user.data!.uuid);
    const username = useStoreState((state) => state.user.data!.username);
    const rootAdmin = useStoreState((state) => state.user.data!.rootAdmin);
    const [showOnlyAdmin, setShowOnlyAdmin] = usePersistedState(`${uuid}:show_all_servers`, false);
    const acc = (window as unknown as { AzurifyAccess?: { role: string; permissions: string[] } }).AzurifyAccess;
    const canCreate = rootAdmin && (!acc || acc.role === 'owner' || acc.permissions.includes('servers.create'));

    const { data: servers, error } = useSWR<PaginatedResult<Server>>(
        ['/api/client/servers', showOnlyAdmin && rootAdmin, page],
        () => getServers({ page, type: showOnlyAdmin && rootAdmin ? 'admin' : undefined })
    );

    useEffect(() => {
        setPage(1);
    }, [showOnlyAdmin]);

    useEffect(() => {
        if (!servers) return;
        if (servers.pagination.currentPage > 1 && !servers.items.length) {
            setPage(1);
        }
    }, [servers?.pagination.currentPage]);

    useEffect(() => {
        window.history.replaceState(null, document.title, `/${page <= 1 ? '' : `?page=${page}`}`);
    }, [page]);

    useEffect(() => {
        if (error) clearAndAddHttpError({ key: 'dashboard', error });
        if (!error) clearFlashes('dashboard');
    }, [error]);

    // Totals come from the servers' configured limits on this page of results.
    const totals = useMemo(() => {
        const items = servers?.items || [];
        const sum = (pick: (s: Server) => number) => items.reduce((n, s) => n + pick(s), 0);
        const unlimited = (pick: (s: Server) => number) => items.some((s) => pick(s) === 0);
        return {
            count: servers?.pagination.total ?? 0,
            memory: unlimited((s) => s.limits.memory) ? 'Unlimited' : bytesToString(mbToBytes(sum((s) => s.limits.memory))),
            disk: unlimited((s) => s.limits.disk) ? 'Unlimited' : bytesToString(mbToBytes(sum((s) => s.limits.disk))),
            nodes: new Set(items.map((s) => s.node)).size,
        };
    }, [servers]);

    return (
        <PageContentBlock title={'Overview'} showFlashKey={'dashboard'}>
            <header className={styles.header}>
                <div>
                    <h1 className={styles.title}>
                        {greeting()}, {username}
                    </h1>
                    <p className={styles.subtitle}>
                        {showOnlyAdmin && rootAdmin ? 'Servers owned by your clients.' : 'Your servers and apps at a glance.'}
                    </p>
                </div>
                <div className={styles.actions}>
                    {rootAdmin && (
                        <div role={'group'} aria-label={'Which servers'} className={styles.segment}>
                            <button type={'button'} aria-pressed={!showOnlyAdmin}
                                    className={!showOnlyAdmin ? styles.segmentOn : undefined}
                                    onClick={() => setShowOnlyAdmin(false)}>
                                Mine
                            </button>
                            <button type={'button'} aria-pressed={showOnlyAdmin}
                                    className={showOnlyAdmin ? styles.segmentOn : undefined}
                                    onClick={() => setShowOnlyAdmin(true)}>
                                All clients
                            </button>
                        </div>
                    )}
                    {canCreate && (
                        <a href={'/admin/servers/new'} className={styles.primary}>
                            + New server
                        </a>
                    )}
                </div>
            </header>

            <section aria-label={'Totals'} className={styles.kpis}>
                <div className={styles.kpi}>
                    <span>Servers</span>
                    <strong>{servers ? totals.count : '-'}</strong>
                    <small>{showOnlyAdmin && rootAdmin ? 'owned by clients' : 'you can access'}</small>
                </div>
                <div className={styles.kpi}>
                    <span>Memory allocated</span>
                    <strong>{servers ? totals.memory : '-'}</strong>
                    <small>across listed servers</small>
                </div>
                <div className={styles.kpi}>
                    <span>Disk allocated</span>
                    <strong>{servers ? totals.disk : '-'}</strong>
                    <small>across listed servers</small>
                </div>
                <div className={styles.kpi}>
                    <span>Nodes</span>
                    <strong>{servers ? totals.nodes : '-'}</strong>
                    <small>hosting these servers</small>
                </div>
            </section>

            {!servers ? (
                <Spinner centered size={'large'} />
            ) : (
                <Pagination data={servers} onPageSelect={setPage}>
                    {({ items }) =>
                        items.length > 0 ? (
                            <div className={styles.grid}>
                                {items.map((server) => (
                                    <ServerRow key={server.uuid} server={server} />
                                ))}
                            </div>
                        ) : (
                            <div className={styles.empty}>
                                <h2>{showOnlyAdmin ? 'No client servers yet' : 'No servers yet'}</h2>
                                <p>
                                    {showOnlyAdmin
                                        ? 'Servers you create for clients will show up here.'
                                        : 'When a server is assigned to your account it will appear here.'}
                                </p>
                                {canCreate && (
                                    <a href={'/admin/servers/new'} className={styles.primary}>
                                        Create a server
                                    </a>
                                )}
                            </div>
                        )
                    }
                </Pagination>
            )}
        </PageContentBlock>
    );
};
