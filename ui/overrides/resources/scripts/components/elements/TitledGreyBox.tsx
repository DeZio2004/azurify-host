import React, { memo } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { IconProp } from '@fortawesome/fontawesome-svg-core';
import tw from 'twin.macro';
import isEqual from 'react-fast-compare';

interface Props {
    icon?: IconProp;
    title: string | React.ReactNode;
    className?: string;
    children: React.ReactNode;
}

// AZURIFY card with a title row.
const TitledGreyBox = ({ icon, title, children, className }: Props) => (
    <div
        css={tw`overflow-hidden`}
        style={{ borderRadius: 18, background: 'rgba(255, 255, 255, 0.04)', border: '1px solid rgba(148, 197, 255, 0.12)' }}
        className={className}
    >
        <div css={tw`px-5 py-4`} style={{ borderBottom: '1px solid rgba(148, 197, 255, 0.1)' }}>
            {typeof title === 'string' ? (
                <p css={tw`font-header font-semibold text-base text-neutral-100`}>
                    {icon && <FontAwesomeIcon icon={icon} css={tw`mr-2 text-cyan-300`} />}
                    {title}
                </p>
            ) : (
                title
            )}
        </div>
        <div css={tw`p-5`}>{children}</div>
    </div>
);

export default memo(TitledGreyBox, isEqual);
