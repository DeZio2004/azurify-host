import tw from 'twin.macro';
import { createGlobalStyle } from 'styled-components/macro';

// Sora, Inter and JetBrains Mono are loaded from Google Fonts by the page template (see brand.sh).
export default createGlobalStyle`
    html, body {
        background: #050812;
    }

    body {
        ${tw`font-sans text-neutral-200`};
        letter-spacing: 0;
        -webkit-font-smoothing: antialiased;
    }

    h1, h2, h3, h4, h5, h6 {
        ${tw`font-semibold tracking-tight font-header`};
    }

    p {
        ${tw`text-neutral-200 leading-snug font-sans`};
    }

    form {
        ${tw`m-0`};
    }

    textarea, select, input, button, button:focus, button:focus-visible {
        ${tw`outline-none`};
    }

    a:focus-visible, button:focus-visible {
        box-shadow: 0 0 0 3px rgba(34, 211, 238, 0.45);
    }

    ::selection {
        background: rgba(34, 211, 238, 0.35);
        color: #ffffff;
    }

    input[type=number]::-webkit-outer-spin-button,
    input[type=number]::-webkit-inner-spin-button {
        -webkit-appearance: none !important;
        margin: 0;
    }

    input[type=number] {
        -moz-appearance: textfield !important;
    }

    ::-webkit-scrollbar {
        background: none;
        width: 10px;
        height: 10px;
    }

    ::-webkit-scrollbar-thumb {
        background: rgba(148, 197, 255, 0.18);
        border-radius: 8px;
        border: 2px solid transparent;
        background-clip: padding-box;
    }

    ::-webkit-scrollbar-corner {
        background: transparent;
    }
`;
