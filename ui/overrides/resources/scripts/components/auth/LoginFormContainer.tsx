import React, { forwardRef } from 'react';
import { Form } from 'formik';
import FlashMessageRender from '@/components/FlashMessageRender';
import { useStoreState } from 'easy-peasy';
import { ApplicationStore } from '@/state';
import styles from '@/components/azurify/auth.module.css';

type Props = React.DetailedHTMLProps<React.FormHTMLAttributes<HTMLFormElement>, HTMLFormElement> & {
    title?: string;
};

export default forwardRef<HTMLFormElement, Props>(({ title, ...props }, ref) => {
    const name = useStoreState((state: ApplicationStore) => state.settings.data?.name || 'AZURIFY');

    return (
        <div className={styles.page}>
            <section className={styles.hero} aria-hidden={'true'}>
                <div className={styles.glow} />
                <div className={styles.brand}>
                    <img src={'/azurify/logo.png'} alt={''} />
                    <span>{name}</span>
                    <em>Host</em>
                </div>
                <div className={styles.pitch}>
                    <h1>Your websites, bots and dashboards. One control room.</h1>
                    <p>Deploy AzuRaya apps, watch live usage and manage every client from a single panel.</p>
                    <div className={styles.tiles}>
                        <div><strong>AzuRaya</strong><small>Bots &amp; inbox</small></div>
                        <div><strong>Websites</strong><small>Node.js hosting</small></div>
                        <div><strong>Staff</strong><small>Roles &amp; access</small></div>
                    </div>
                </div>
                <p className={styles.legal}>&copy; {new Date().getFullYear()} {name}</p>
            </section>

            <section className={styles.panel}>
                <div className={styles.formWrap}>
                    <div className={styles.mobileBrand}>
                        <img src={'/azurify/logo.png'} alt={''} />
                        <span>{name}</span>
                    </div>
                    {title && <h2 className={styles.title}>{title === 'Login to Continue' ? 'Sign in' : title}</h2>}
                    <FlashMessageRender className={styles.flash} />
                    <Form {...props} ref={ref} className={styles.form}>
                        {props.children}
                    </Form>
                </div>
            </section>
        </div>
    );
});
