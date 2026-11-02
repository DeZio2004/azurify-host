import styled from 'styled-components/macro';
import tw from 'twin.macro';

// AZURIFY: server sections as a pill tab bar under the page header.
const SubNavigation = styled.div`
    ${tw`w-full overflow-x-auto`};
    padding: 24px 32px 0;

    @media (max-width: 640px) {
        padding: 16px 16px 0;
    }

    & > div {
        ${tw`inline-flex items-center text-sm`};
        gap: 4px;
        padding: 5px;
        border-radius: 14px;
        background: rgba(255, 255, 255, 0.04);
        border: 1px solid rgba(148, 197, 255, 0.12);

        & > a,
        & > div {
            ${tw`inline-flex items-center no-underline whitespace-nowrap transition-all duration-150`};
            height: 36px;
            padding: 0 14px;
            border-radius: 10px;
            color: #9fb0c8;
            font-weight: 600;

            &:hover {
                color: #ffffff;
                background: rgba(255, 255, 255, 0.05);
            }

            &:active,
            &.active {
                color: #ffffff;
                background: rgba(34, 211, 238, 0.16);
            }
        }
    }
`;

export default SubNavigation;
