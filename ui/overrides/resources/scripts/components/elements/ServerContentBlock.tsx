import PageContentBlock, { PageContentBlockProps } from '@/components/elements/PageContentBlock';
import React from 'react';
import { ServerContext } from '@/state/server';
import tw from 'twin.macro';

interface Props extends PageContentBlockProps {
    title: string;
}

// Every server section gets the same heading; the console draws its own.
const ServerContentBlock: React.FC<Props> = ({ title, children, ...props }) => {
    const name = ServerContext.useStoreState((state) => state.server.data!.name);

    return (
        <PageContentBlock title={`${name} | ${title}`} {...props}>
            {title !== 'Console' && (
                <div css={tw`mb-6`}>
                    <p css={tw`text-sm text-neutral-400`}>{name}</p>
                    <h1 css={tw`font-header text-2xl font-semibold text-neutral-50 mt-1`}>{title}</h1>
                </div>
            )}
            {children}
        </PageContentBlock>
    );
};

export default ServerContentBlock;
