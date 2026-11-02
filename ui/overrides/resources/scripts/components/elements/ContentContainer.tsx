import styled from 'styled-components/macro';

const ContentContainer = styled.div`
    max-width: 1280px;
    margin: 0 auto;
    padding: 0 32px;

    @media (max-width: 640px) {
        padding: 0 16px;
    }
`;
ContentContainer.displayName = 'ContentContainer';

export default ContentContainer;
