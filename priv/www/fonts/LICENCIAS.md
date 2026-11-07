# Fuentes incluidas

Se sirven localmente para que la demo funcione sin conexión a Internet. Son las
mismas fuentes que usa el diseño exportado de Google Stitch (`design/stitch/`).

| Archivo | Fuente | Licencia | Origen |
|---|---|---|---|
| `inter.woff2` | Inter (variable, subconjunto latin) | SIL Open Font License 1.1 | Google Fonts |
| `jetbrains-mono.woff2` | JetBrains Mono (variable, subconjunto latin) | SIL Open Font License 1.1 | Google Fonts |
| `material-symbols-outlined.woff2` | Material Symbols Outlined (solo los iconos que usa la interfaz) | Apache License 2.0 | Google Fonts |

Si se agregan iconos nuevos a la interfaz, hay que volver a generar el
subconjunto de Material Symbols: `scripts/construir_css.sh --fuentes`.
