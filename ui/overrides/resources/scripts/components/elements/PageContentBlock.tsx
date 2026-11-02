import React, { useEffect } from 'react';
import ContentContainer from '@/components/elements/ContentContainer';
import { CSSTransition } from 'react-transition-group';
import tw from 'twin.macro';
import FlashMessageRender from '@/components/FlashMessageRender';
import { useStoreState } from 'easy-peasy';
import { ApplicationStore } from '@/state';

export interface PageContentBlockProps {
    title?: string;
    className?: string;
    showFlashKey?: string;
}

const PageContentBlock: React.FC<PageContentBlockProps> = ({ title, showFlashKey, className, children }) => {
    const name = useStoreState((state: ApplicationStore) => state.settings.data?.name || 'AZURIFY');

    useEffect(() => {
        if (title) {
            document.title = `${title} | ${name}`;
        }
    }, [title, name]);

    return (
        <CSSTransition timeout={150} classNames={'fade'} appear in>
            <>
                <ContentContainer css={tw`py-6 sm:py-8`} className={className}>
                    {showFlashKey && <FlashMessageRender byKey={showFlashKey} css={tw`mb-4`} />}
                    {children}
                </ContentContainer>
                <ContentContainer css={tw`pb-6`}>
                    <p css={tw`text-xs text-neutral-500`}>
                        &copy; {new Date().getFullYear()} {name}
                    </p>
                </ContentContainer>
            </>
        </CSSTransition>
    );
};

export default PageContentBlock;
