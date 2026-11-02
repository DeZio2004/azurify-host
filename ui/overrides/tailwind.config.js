const colors = require('tailwindcss/colors');

// AZURIFY navy scale: every "neutral"/"gray" surface in the app picks this up.
const gray = {
    50: '#f2f6fc',
    100: '#e6edf7',
    200: '#c9d5e6',
    300: '#9fb0c8',
    400: '#8195b3',
    500: '#5d7090',
    600: '#24344f',
    700: '#14213a',
    800: '#0b1527',
    900: '#07101f',
};

module.exports = {
    content: [
        './resources/scripts/**/*.{js,ts,tsx}',
    ],
    theme: {
        extend: {
            fontFamily: {
                sans: ['Inter', 'system-ui', 'sans-serif'],
                header: ['Sora', 'Inter', 'system-ui', 'sans-serif'],
                mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
            },
            colors: {
                black: '#03060d',
                // "primary" and "neutral" are deprecated upstream; both map onto the AZURIFY palette.
                primary: colors.sky,
                blue: colors.sky,
                gray: gray,
                neutral: gray,
                cyan: colors.cyan,
                azure: {
                    ground: '#050812',
                    line: 'rgba(148, 197, 255, 0.12)',
                    accent: '#22d3ee',
                },
            },
            fontSize: {
                '2xs': '0.625rem',
            },
            transitionDuration: {
                250: '250ms',
            },
            borderColor: theme => ({
                default: theme('colors.neutral.600', 'currentColor'),
            }),
        },
    },
    plugins: [
        require('@tailwindcss/line-clamp'),
        require('@tailwindcss/forms')({
            strategy: 'class',
        }),
    ]
};
