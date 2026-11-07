// Configuracion de Tailwind exportada de Google Stitch (design/stitch/*/code.html),
// identica en las 7 pantallas. Unico cambio: los colores pasan a variables CSS
// (definidas en assets/entrada.css) para el modo oscuro que describe DESIGN.md.
// Regenerar el CSS con scripts/construir_css.sh.
module.exports = {
  "darkMode": "class",
  "content": [
    "./priv/www/**/*.{html,js}"
  ],
  "theme": {
    "extend": {
      "colors": {
        "background": "rgb(var(--c-background) / <alpha-value>)",
        "error": "rgb(var(--c-error) / <alpha-value>)",
        "error-container": "rgb(var(--c-error-container) / <alpha-value>)",
        "inverse-on-surface": "rgb(var(--c-inverse-on-surface) / <alpha-value>)",
        "inverse-primary": "rgb(var(--c-inverse-primary) / <alpha-value>)",
        "inverse-surface": "rgb(var(--c-inverse-surface) / <alpha-value>)",
        "on-background": "rgb(var(--c-on-background) / <alpha-value>)",
        "on-error": "rgb(var(--c-on-error) / <alpha-value>)",
        "on-error-container": "rgb(var(--c-on-error-container) / <alpha-value>)",
        "on-primary": "rgb(var(--c-on-primary) / <alpha-value>)",
        "on-primary-container": "rgb(var(--c-on-primary-container) / <alpha-value>)",
        "on-primary-fixed": "rgb(var(--c-on-primary-fixed) / <alpha-value>)",
        "on-primary-fixed-variant": "rgb(var(--c-on-primary-fixed-variant) / <alpha-value>)",
        "on-secondary": "rgb(var(--c-on-secondary) / <alpha-value>)",
        "on-secondary-container": "rgb(var(--c-on-secondary-container) / <alpha-value>)",
        "on-secondary-fixed": "rgb(var(--c-on-secondary-fixed) / <alpha-value>)",
        "on-secondary-fixed-variant": "rgb(var(--c-on-secondary-fixed-variant) / <alpha-value>)",
        "on-surface": "rgb(var(--c-on-surface) / <alpha-value>)",
        "on-surface-variant": "rgb(var(--c-on-surface-variant) / <alpha-value>)",
        "on-tertiary": "rgb(var(--c-on-tertiary) / <alpha-value>)",
        "on-tertiary-container": "rgb(var(--c-on-tertiary-container) / <alpha-value>)",
        "on-tertiary-fixed": "rgb(var(--c-on-tertiary-fixed) / <alpha-value>)",
        "on-tertiary-fixed-variant": "rgb(var(--c-on-tertiary-fixed-variant) / <alpha-value>)",
        "outline": "rgb(var(--c-outline) / <alpha-value>)",
        "outline-variant": "rgb(var(--c-outline-variant) / <alpha-value>)",
        "primary": "rgb(var(--c-primary) / <alpha-value>)",
        "primary-container": "rgb(var(--c-primary-container) / <alpha-value>)",
        "primary-fixed": "rgb(var(--c-primary-fixed) / <alpha-value>)",
        "primary-fixed-dim": "rgb(var(--c-primary-fixed-dim) / <alpha-value>)",
        "secondary": "rgb(var(--c-secondary) / <alpha-value>)",
        "secondary-container": "rgb(var(--c-secondary-container) / <alpha-value>)",
        "secondary-fixed": "rgb(var(--c-secondary-fixed) / <alpha-value>)",
        "secondary-fixed-dim": "rgb(var(--c-secondary-fixed-dim) / <alpha-value>)",
        "surface": "rgb(var(--c-surface) / <alpha-value>)",
        "surface-bright": "rgb(var(--c-surface-bright) / <alpha-value>)",
        "surface-container": "rgb(var(--c-surface-container) / <alpha-value>)",
        "surface-container-high": "rgb(var(--c-surface-container-high) / <alpha-value>)",
        "surface-container-highest": "rgb(var(--c-surface-container-highest) / <alpha-value>)",
        "surface-container-low": "rgb(var(--c-surface-container-low) / <alpha-value>)",
        "surface-container-lowest": "rgb(var(--c-surface-container-lowest) / <alpha-value>)",
        "surface-dim": "rgb(var(--c-surface-dim) / <alpha-value>)",
        "surface-tint": "rgb(var(--c-surface-tint) / <alpha-value>)",
        "surface-variant": "rgb(var(--c-surface-variant) / <alpha-value>)",
        "tertiary": "rgb(var(--c-tertiary) / <alpha-value>)",
        "tertiary-container": "rgb(var(--c-tertiary-container) / <alpha-value>)",
        "tertiary-fixed": "rgb(var(--c-tertiary-fixed) / <alpha-value>)",
        "tertiary-fixed-dim": "rgb(var(--c-tertiary-fixed-dim) / <alpha-value>)"
      },
      "borderRadius": {
        "DEFAULT": "0.125rem",
        "lg": "0.25rem",
        "xl": "0.5rem",
        "full": "0.75rem"
      },
      "spacing": {
        "space-xl": "2.5rem",
        "margin-desktop": "2rem",
        "gutter": "1rem",
        "space-lg": "1.5rem",
        "margin": "1rem",
        "space-sm": "0.5rem",
        "space-xs": "0.25rem",
        "gutter-desktop": "1.5rem",
        "space-md": "1rem"
      },
      "fontFamily": {
        "label-numeric-sm": [
          "JetBrains Mono"
        ],
        "headline-md": [
          "Inter"
        ],
        "body-sm": [
          "Inter"
        ],
        "body-md": [
          "Inter"
        ],
        "label-receipt": [
          "JetBrains Mono"
        ],
        "body-lg": [
          "Inter"
        ],
        "headline-xl": [
          "Inter"
        ],
        "headline-lg-mobile": [
          "Inter"
        ],
        "headline-lg": [
          "Inter"
        ],
        "label-numeric-md": [
          "JetBrains Mono"
        ],
        "headline-xl-mobile": [
          "Inter"
        ],
        "label-numeric-lg": [
          "JetBrains Mono"
        ]
      },
      "fontSize": {
        "label-numeric-sm": [
          "0.875rem",
          {
            "lineHeight": "1.25rem",
            "letterSpacing": "0",
            "fontWeight": "500"
          }
        ],
        "headline-md": [
          "1.25rem",
          {
            "lineHeight": "1.75rem",
            "letterSpacing": "-0.01em",
            "fontWeight": "600"
          }
        ],
        "body-sm": [
          "0.875rem",
          {
            "lineHeight": "1.25rem",
            "fontWeight": "400"
          }
        ],
        "body-md": [
          "1rem",
          {
            "lineHeight": "1.5rem",
            "fontWeight": "400"
          }
        ],
        "label-receipt": [
          "0.75rem",
          {
            "lineHeight": "1.125rem",
            "letterSpacing": "0.02em",
            "fontWeight": "400"
          }
        ],
        "body-lg": [
          "1.125rem",
          {
            "lineHeight": "1.625rem",
            "fontWeight": "400"
          }
        ],
        "headline-xl": [
          "2.25rem",
          {
            "lineHeight": "2.75rem",
            "letterSpacing": "-0.025em",
            "fontWeight": "700"
          }
        ],
        "headline-lg-mobile": [
          "1.375rem",
          {
            "lineHeight": "1.75rem",
            "letterSpacing": "-0.015em",
            "fontWeight": "600"
          }
        ],
        "headline-lg": [
          "1.75rem",
          {
            "lineHeight": "2.25rem",
            "letterSpacing": "-0.02em",
            "fontWeight": "600"
          }
        ],
        "label-numeric-md": [
          "1.125rem",
          {
            "lineHeight": "1.5rem",
            "letterSpacing": "0",
            "fontWeight": "500"
          }
        ],
        "headline-xl-mobile": [
          "1.75rem",
          {
            "lineHeight": "2.25rem",
            "letterSpacing": "-0.02em",
            "fontWeight": "700"
          }
        ],
        "label-numeric-lg": [
          "1.5rem",
          {
            "lineHeight": "2rem",
            "letterSpacing": "-0.01em",
            "fontWeight": "600"
          }
        ]
      }
    }
  },
  "plugins": []
};
