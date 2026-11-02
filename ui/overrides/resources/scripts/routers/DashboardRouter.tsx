import React from 'react';
import { Route, Switch } from 'react-router-dom';
import AppShell from '@/components/azurify/AppShell';
import DashboardContainer from '@/components/dashboard/DashboardContainer';
import { NotFound } from '@/components/elements/ScreenBlock';
import TransitionRouter from '@/TransitionRouter';
import { useLocation } from 'react-router';
import Spinner from '@/components/elements/Spinner';
import routes from '@/routers/routes';
import ContentContainer from '@/components/elements/ContentContainer';
import tw from 'twin.macro';

export default () => {
    const location = useLocation();

    return (
        <AppShell>
            <TransitionRouter>
                <React.Suspense fallback={<Spinner centered />}>
                    <Switch location={location}>
                        <Route path={'/'} exact>
                            <DashboardContainer />
                        </Route>
                        {routes.account.map(({ path, name, component: Component }) => (
                            <Route key={path} path={`/account/${path}`.replace('//', '/')} exact>
                                {name && (
                                    <ContentContainer css={tw`pt-8`}>
                                        <p css={tw`text-sm text-neutral-400`}>Your account</p>
                                        <h1 css={tw`font-header text-2xl font-semibold text-neutral-50 mt-1`}>{name}</h1>
                                    </ContentContainer>
                                )}
                                <Component />
                            </Route>
                        ))}
                        <Route path={'*'}>
                            <NotFound />
                        </Route>
                    </Switch>
                </React.Suspense>
            </TransitionRouter>
        </AppShell>
    );
};
