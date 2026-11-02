import React, { useEffect, useState } from 'react';
import ContentBox from '@/components/elements/ContentBox';
import CreateApiKeyForm from '@/components/dashboard/forms/CreateApiKeyForm';
import getApiKeys, { ApiKey } from '@/api/account/getApiKeys';
import SpinnerOverlay from '@/components/elements/SpinnerOverlay';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faEye, faEyeSlash, faKey, faTrashAlt } from '@fortawesome/free-solid-svg-icons';
import deleteApiKey from '@/api/account/deleteApiKey';
import FlashMessageRender from '@/components/FlashMessageRender';
import { format } from 'date-fns';
import PageContentBlock from '@/components/elements/PageContentBlock';
import tw from 'twin.macro';
import GreyRowBox from '@/components/elements/GreyRowBox';
import { Dialog } from '@/components/elements/dialog';
import { Button } from '@/components/elements/button/index';
import { useFlashKey } from '@/plugins/useFlash';
import Code from '@/components/elements/Code';
import CopyOnClick from '@/components/elements/CopyOnClick';
import Input from '@/components/elements/Input';
import Label from '@/components/elements/Label';
import http, { httpErrorToHuman } from '@/api/http';

export default () => {
    const [deleteIdentifier, setDeleteIdentifier] = useState('');
    const [keys, setKeys] = useState<ApiKey[]>([]);
    const [loading, setLoading] = useState(true);
    const { clearAndAddHttpError } = useFlashKey('account');

    // AZURIFY: reveal a key's full secret again after confirming the account password.
    const [revealFor, setRevealFor] = useState('');
    const [password, setPassword] = useState('');
    const [revealError, setRevealError] = useState('');
    const [revealing, setRevealing] = useState(false);
    const [revealed, setRevealed] = useState<Record<string, string>>({});

    useEffect(() => {
        getApiKeys()
            .then((keys) => setKeys(keys))
            .then(() => setLoading(false))
            .catch((error) => clearAndAddHttpError(error));
    }, []);

    const doDeletion = (identifier: string) => {
        setLoading(true);

        clearAndAddHttpError();
        deleteApiKey(identifier)
            .then(() => setKeys((s) => [...(s || []).filter((key) => key.identifier !== identifier)]))
            .catch((error) => clearAndAddHttpError(error))
            .then(() => {
                setLoading(false);
                setDeleteIdentifier('');
            });
    };

    const closeReveal = () => {
        setRevealFor('');
        setPassword('');
        setRevealError('');
    };

    const doReveal = (e?: React.FormEvent) => {
        e?.preventDefault();
        if (!password) {
            setRevealError('Enter your account password.');
            return;
        }
        setRevealing(true);
        setRevealError('');
        http.post(`/api/client/account/api-keys/${revealFor}/reveal`, { password })
            .then(({ data }) => {
                setRevealed((s) => ({ ...s, [revealFor]: data.token }));
                closeReveal();
            })
            .catch((error) => setRevealError(httpErrorToHuman(error)))
            .then(() => setRevealing(false));
    };

    const hide = (identifier: string) =>
        setRevealed((s) => {
            const next = { ...s };
            delete next[identifier];
            return next;
        });

    return (
        <PageContentBlock title={'Account API'}>
            <FlashMessageRender byKey={'account'} />
            <div css={tw`md:flex flex-nowrap my-10`}>
                <ContentBox title={'Create API Key'} css={tw`flex-none w-full md:w-1/2`}>
                    <CreateApiKeyForm onKeyCreated={(key) => setKeys((s) => [...s!, key])} />
                </ContentBox>
                <ContentBox title={'API Keys'} css={tw`flex-1 overflow-hidden mt-8 md:mt-0 md:ml-8`}>
                    <SpinnerOverlay visible={loading} />
                    <Dialog.Confirm
                        title={'Delete API Key'}
                        confirm={'Delete Key'}
                        open={!!deleteIdentifier}
                        onClose={() => setDeleteIdentifier('')}
                        onConfirmed={() => doDeletion(deleteIdentifier)}
                    >
                        All requests using the <Code>{deleteIdentifier}</Code> key will be invalidated.
                    </Dialog.Confirm>
                    <Dialog
                        open={!!revealFor}
                        onClose={closeReveal}
                        title={'Show full API key'}
                        description={'For your security, confirm your account password to view this key.'}
                    >
                        <form onSubmit={doReveal} css={tw`mt-4`}>
                            <Label htmlFor={'reveal-password'}>Account password</Label>
                            <Input
                                id={'reveal-password'}
                                type={'password'}
                                autoComplete={'current-password'}
                                value={password}
                                onChange={(e) => setPassword(e.currentTarget.value)}
                                autoFocus
                            />
                            {revealError && <p css={tw`text-sm text-red-300 mt-2`}>{revealError}</p>}
                        </form>
                        <Dialog.Footer>
                            <Button.Text onClick={closeReveal}>Cancel</Button.Text>
                            <Button onClick={() => doReveal()} disabled={revealing}>
                                {revealing ? 'Checking...' : 'Show key'}
                            </Button>
                        </Dialog.Footer>
                    </Dialog>
                    {keys.length === 0 ? (
                        <p css={tw`text-center text-sm`}>
                            {loading ? 'Loading...' : 'No API keys exist for this account.'}
                        </p>
                    ) : (
                        keys.map((key, index) => (
                            <GreyRowBox
                                key={key.identifier}
                                css={[tw`flex flex-wrap items-center`, index > 0 && tw`mt-2`]}
                            >
                                <FontAwesomeIcon icon={faKey} css={tw`text-cyan-300`} />
                                <div css={tw`ml-4 flex-1 overflow-hidden`}>
                                    <p css={tw`text-sm break-words`}>{key.description}</p>
                                    <p css={tw`text-2xs text-neutral-300 uppercase`}>
                                        Last used:&nbsp;
                                        {key.lastUsedAt ? format(key.lastUsedAt, 'MMM do, yyyy HH:mm') : 'Never'}
                                    </p>
                                </div>
                                {!revealed[key.identifier] && (
                                    <p css={tw`text-sm ml-4 hidden md:block`}>
                                        <code css={tw`font-mono py-1 px-2 bg-neutral-900 rounded`}>
                                            {key.identifier}
                                        </code>
                                    </p>
                                )}
                                <button
                                    type={'button'}
                                    css={tw`ml-2 p-2 text-sm`}
                                    aria-label={revealed[key.identifier] ? 'Hide full key' : 'Show full key'}
                                    title={revealed[key.identifier] ? 'Hide full key' : 'Show full key'}
                                    onClick={() =>
                                        revealed[key.identifier] ? hide(key.identifier) : setRevealFor(key.identifier)
                                    }
                                >
                                    <FontAwesomeIcon
                                        icon={revealed[key.identifier] ? faEyeSlash : faEye}
                                        css={tw`text-neutral-400 hover:text-cyan-300 transition-colors duration-150`}
                                    />
                                </button>
                                <button
                                    type={'button'}
                                    css={tw`ml-1 p-2 text-sm`}
                                    aria-label={'Delete key'}
                                    onClick={() => setDeleteIdentifier(key.identifier)}
                                >
                                    <FontAwesomeIcon
                                        icon={faTrashAlt}
                                        css={tw`text-neutral-400 hover:text-red-400 transition-colors duration-150`}
                                    />
                                </button>
                                {revealed[key.identifier] && (
                                    <div css={tw`w-full mt-3`}>
                                        <CopyOnClick text={revealed[key.identifier]}>
                                            <code
                                                css={tw`block font-mono text-sm py-2 px-3 bg-neutral-900 rounded-lg break-all cursor-pointer`}
                                                title={'Click to copy'}
                                            >
                                                {revealed[key.identifier]}
                                            </code>
                                        </CopyOnClick>
                                        <p css={tw`text-2xs text-neutral-400 mt-1`}>Click the key to copy it.</p>
                                    </div>
                                )}
                            </GreyRowBox>
                        ))
                    )}
                </ContentBox>
            </div>
        </PageContentBlock>
    );
};
