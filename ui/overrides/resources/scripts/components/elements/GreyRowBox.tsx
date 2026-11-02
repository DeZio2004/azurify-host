import styled from 'styled-components/macro';
import tw from 'twin.macro';

// AZURIFY card row: translucent surface with a hairline border instead of a grey slab.
export default styled.div<{ $hoverable?: boolean }>`
    ${tw`flex no-underline text-neutral-200 items-center p-4 transition-colors duration-150 overflow-hidden`};
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(148, 197, 255, 0.12);

    ${(props) =>
        props.$hoverable !== false &&
        `
        &:hover {
            border-color: rgba(34, 211, 238, 0.45);
            background: rgba(255, 255, 255, 0.06);
        }
    `};

    & .icon {
        ${tw`w-12 h-12 flex items-center justify-center p-3`};
        border-radius: 12px;
        background: rgba(34, 211, 238, 0.12);
        color: #67e8f9;
    }
`;
