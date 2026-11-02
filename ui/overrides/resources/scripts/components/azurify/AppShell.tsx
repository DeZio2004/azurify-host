import React, { useEffect, useState } from 'react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { useStoreState } from 'easy-peasy';
import { ApplicationStore } from '@/state';
import http from '@/api/http';
import SpinnerOverlay from '@/components/elements/SpinnerOverlay';
import SearchModal from '@/components/dashboard/search/SearchModal';
import useEventListener from '@/plugins/useEventListener';
import Avatar from '@/components/Avatar';
import styles from './shell.module.css';

const Icon = ({ d }: { d: string }) => (
    <svg width={18} height={18} viewBox={'0 0 24 24'} fill={'none'} stroke={'currentColor'} strokeWidth={2}
         strokeLinecap={'round'} strokeLinejoin={'round'} aria-hidden={'true'}>
        <path d={d} />
    </svg>
);

const ICONS = {
    overview: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
    account: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c1.5-4 4.5-6 8-6s6.5 2 8 6',
    key: 'M15 7a4 4 0 1 1-3.9 5H3v3h3v3h3v-3h2.1A4 4 0 0 1 15 7z',
    ssh: 'M4 6l6 6-6 6M12 18h8',
    activity: 'M3 12h4l3 8 4-16 3 8h4',
    control: 'M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z',
    staff: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20c1-3.5 3.5-5.5 6.5-5.5s5.5 2 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5c2 .7 3.2 2.6 3.5 5.5',
    server: 'M3 4h18v6H3zM3 14h18v6H3zM7 7h.01M7 17h.01',
    plus: 'M12 5v14M5 12h14',
    menu: 'M4 6h16M4 12h16M4 18h16',
    logout: 'M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3',
};

interface Props {
    children: React.ReactNode;
}

// Set by the page template (AZURIFY staff permissions); absent on an unpatched panel.
interface Access {
    role: 'owner' | 'staff' | 'client' | 'guest';
    permissions: string[];
}
const access = (): Access | undefined => (window as unknown as { AzurifyAccess?: Access }).AzurifyAccess;

export default ({ children }: Props) => {
    const name = useStoreState((state: ApplicationStore) => state.settings.data!.name);
    const user = useStoreState((state: ApplicationStore) => state.user.data!);
    const [isLoggingOut, setIsLoggingOut] = useState(false);
    const [open, setOpen] = useState(false);
    const [searching, setSearching] = useState(false);
    const location = useLocation();
    const acc = access();
    const role = acc?.role ?? (user.rootAdmin ? 'owner' : 'client');
    const can = (perm: string) => role === 'owner' || (acc?.permissions ?? []).includes(perm);
    const roleLabel = { owner: 'Owner', staff: 'Staff', client: 'Client', guest: 'Guest' }[role];

    // "/" or Ctrl/Cmd+K opens server search, unless the user is typing somewhere.
    useEventListener('keydown', (e: KeyboardEvent) => {
        const tag = ((e.target as HTMLElement).tagName || '').toLowerCase();
        if (searching || ['input', 'textarea', 'select'].includes(tag) || (e.target as HTMLElement).isContentEditable) return;
        if (e.key === '/' || ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k')) {
            e.preventDefault();
            setSearching(true);
        }
    });

    useEffect(() => setOpen(false), [location.pathname]);

    const onLogout = () => {
        setIsLoggingOut(true);
        http.post('/auth/logout').finally(() => {
            // @ts-expect-error this is valid
            window.location = '/';
        });
    };

    const link = (to: string, label: string, icon: keyof typeof ICONS, exact = false) => (
        <NavLink to={to} exact={exact} className={styles.link} activeClassName={styles.active}>
            <Icon d={ICONS[icon]} />
            <span>{label}</span>
        </NavLink>
    );

    return (
        <div className={styles.shell}>
            <SpinnerOverlay visible={isLoggingOut} />
            {searching && <SearchModal appear visible={searching} onDismissed={() => setSearching(false)} />}
            <header className={styles.mobileBar}>
                <Link to={'/'} className={styles.brand}>
                    <img src={'/azurify/logo.png'} alt={''} />
                    <span>{name}</span>
                </Link>
                <button type={'button'} className={styles.iconButton} aria-label={'Open menu'}
                        aria-expanded={open} onClick={() => setOpen((v) => !v)}>
                    <Icon d={ICONS.menu} />
                </button>
            </header>

            <nav aria-label={'Main'} className={`${styles.sidebar} ${open ? styles.sidebarOpen : ''}`}>
                <Link to={'/'} className={`${styles.brand} ${styles.brandDesktop}`}>
                    <img src={'/azurify/logo.png'} alt={''} />
                    <span>{name}</span>
                </Link>

                <button type={'button'} className={styles.search} onClick={() => setSearching(true)}>
                    <svg width={16} height={16} viewBox={'0 0 24 24'} fill={'none'} stroke={'currentColor'} strokeWidth={2}
                         strokeLinecap={'round'} aria-hidden={'true'}>
                        <circle cx={11} cy={11} r={7} />
                        <path d={'m20 20-3.5-3.5'} />
                    </svg>
                    <span>Search servers</span>
                    <kbd>/</kbd>
                </button>

                <p className={styles.section}>Workspace</p>
                {link('/', 'Overview', 'overview', true)}
                {link('/account', 'Account', 'account', true)}
                {link('/account/api', 'API keys', 'key')}
                {link('/account/ssh', 'SSH keys', 'ssh')}
                {link('/account/activity', 'Activity', 'activity')}

                {user.rootAdmin && (
                    <>
                        <p className={styles.section}>Control</p>
                        <a href={'/admin'} className={styles.link}>
                            <Icon d={ICONS.control} />
                            <span>Control center</span>
                        </a>
                        {can('servers.create') && (
                            <a href={'/admin/servers/new'} className={styles.link}>
                                <Icon d={ICONS.plus} />
                                <span>Create server</span>
                            </a>
                        )}
                        {role === 'owner' && (
                            <a href={'/admin/azurify/staff'} className={styles.link}>
                                <Icon d={ICONS.staff} />
                                <span>Staff</span>
                            </a>
                        )}
                    </>
                )}

                <div className={styles.user}>
                    <span className={styles.avatar}><Avatar.User /></span>
                    <div className={styles.userText}>
                        <strong>{user.username}</strong>
                        <small>{roleLabel}</small>
                    </div>
                    <button type={'button'} className={styles.iconButton} aria-label={'Sign out'} onClick={onLogout}>
                        <Icon d={ICONS.logout} />
                    </button>
                </div>
            </nav>
            {open && <button type={'button'} aria-label={'Close menu'} className={styles.scrim} onClick={() => setOpen(false)} />}

            <main className={styles.main}>{children}</main>
        </div>
    );
};
