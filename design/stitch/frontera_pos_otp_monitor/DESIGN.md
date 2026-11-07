---
name: Frontera POS & OTP Monitor
colors:
  surface: '#f9f9ff'
  surface-dim: '#d3daea'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f0f3ff'
  surface-container: '#e7eefe'
  surface-container-high: '#e2e8f8'
  surface-container-highest: '#dce2f3'
  on-surface: '#151c27'
  on-surface-variant: '#3f4943'
  inverse-surface: '#2a313d'
  inverse-on-surface: '#ebf1ff'
  outline: '#6f7a73'
  outline-variant: '#bec9c1'
  surface-tint: '#056c4d'
  primary: '#00543b'
  on-primary: '#ffffff'
  primary-container: '#0b6e4f'
  on-primary-container: '#98edc6'
  inverse-primary: '#83d7b1'
  secondary: '#555f6f'
  on-secondary: '#ffffff'
  secondary-container: '#d6e0f3'
  on-secondary-container: '#596373'
  tertiary: '#713b00'
  on-tertiary: '#ffffff'
  tertiary-container: '#944f00'
  on-tertiary-container: '#ffd4b5'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#9ff4cc'
  primary-fixed-dim: '#83d7b1'
  on-primary-fixed: '#002115'
  on-primary-fixed-variant: '#005139'
  secondary-fixed: '#d9e3f6'
  secondary-fixed-dim: '#bdc7d9'
  on-secondary-fixed: '#121c2a'
  on-secondary-fixed-variant: '#3d4756'
  tertiary-fixed: '#ffdcc3'
  tertiary-fixed-dim: '#ffb77d'
  on-tertiary-fixed: '#2f1500'
  on-tertiary-fixed-variant: '#6e3900'
  background: '#f9f9ff'
  on-background: '#151c27'
  surface-variant: '#dce2f3'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 2.25rem
    fontWeight: '700'
    lineHeight: 2.75rem
    letterSpacing: -0.025em
  headline-xl-mobile:
    fontFamily: Inter
    fontSize: 1.75rem
    fontWeight: '700'
    lineHeight: 2.25rem
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 1.75rem
    fontWeight: '600'
    lineHeight: 2.25rem
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 1.375rem
    fontWeight: '600'
    lineHeight: 1.75rem
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Inter
    fontSize: 1.25rem
    fontWeight: '600'
    lineHeight: 1.75rem
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 1.125rem
    fontWeight: '400'
    lineHeight: 1.625rem
  body-md:
    fontFamily: Inter
    fontSize: 1rem
    fontWeight: '400'
    lineHeight: 1.5rem
  body-sm:
    fontFamily: Inter
    fontSize: 0.875rem
    fontWeight: '400'
    lineHeight: 1.25rem
  label-numeric-lg:
    fontFamily: JetBrains Mono
    fontSize: 1.5rem
    fontWeight: '600'
    lineHeight: 2rem
    letterSpacing: -0.01em
  label-numeric-md:
    fontFamily: JetBrains Mono
    fontSize: 1.125rem
    fontWeight: '500'
    lineHeight: 1.5rem
    letterSpacing: '0'
  label-numeric-sm:
    fontFamily: JetBrains Mono
    fontSize: 0.875rem
    fontWeight: '500'
    lineHeight: 1.25rem
    letterSpacing: '0'
  label-receipt:
    fontFamily: JetBrains Mono
    fontSize: 0.75rem
    fontWeight: '400'
    lineHeight: 1.125rem
    letterSpacing: 0.02em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system is engineered for dual mission-critical operations: fast-paced retail checkout at the US-Mexico border and real-time actor runtime monitoring for distributed Erlang/OTP systems. It bridges high-velocity border commerce in Tijuana with the fault-tolerant resilience of BEAM-driven infrastructure.

The design aesthetic combines utilitarian precision and high-contrast ergonomics. It draws from industrial tactical interfaces and Swiss modernism, prioritizing legibility under bright counter lighting, immediate hardware readability on thermal screens and touch POS terminals, and rapid incident triage in command-line-informed telemetry dashboards. 

### Key Tenets
- **High-Stakes Clarity:** Zero ambiguity in critical states. Every transaction total, currency conversion, and worker-tree failure must be scannable in under 100 milliseconds.
- **Bilingual & Bi-monetary Rhythm:** Native accommodation of rapid switching between MXN and USD cash handling, exchange rates, and binational operational workflows.
- **Fault-Tolerant Feedback:** Explicit status indicators pairing iconography with direct text labels, refusing to rely solely on color encoding.

## Colors

The palette balances clinical efficiency with unambiguous situational awareness. High contrast is maintained across both themes to satisfy strict indoor ambient lighting variances typical in retail bays and dispatch rooms.

### Light Mode (Default)
- **Canvas Base:** `#F4F5F7` (tactile light grey, minimizing eye fatigue during 10-hour shifts)
- **Surface / Card Base:** `#FFFFFF` with deliberate structural borders (`#E2E4E9`)
- **Primary / Brand Action:** `#0B6E4F` (deep border jade)
- **Primary Interactive Hover/Active:** `#08503A` / `#053A2A`
- **Secondary (Structural & Systemic):** `#111827` (slate ink)
- **Text Main:** `#0F172A`
- **Text Muted / Subdued:** `#475569`
- **Hairlines & Dividers:** `#D1D5DB`

### Dark Mode (Operational / Low-Light NOC Variant)
- **Canvas Base:** `#0B0F17` (deep tactical carbon)
- **Surface / Card Base:** `#131B26`
- **Surface Highlight / Elevation:** `#1A2433`
- **Primary Brand / Key Indicators:** `#10B981` (high-luminance emerald for visibility on pitch canvas)
- **Border / Structural Lines:** `#243042`
- **Text Main:** `#F9FAFB`
- **Text Muted:** `#9CA3AF`

### Strict Semantic Status Tokens
Every semantic state must pair with explicit text and iconography:
- **Operando (Normal):** Base `#0B6E4F` (Light) / `#10B981` (Dark). Surface Tint: `#ECFDF5`. Foreground: `#065F46`.
- **Alerta (Warning / Degraded OTP Process):** Base `#D97706` (Light) / `#FBBF24` (Dark). Surface Tint: `#FFFBEB`. Foreground: `#92400E`.
- **Falla (Critical / Crash / Network Partition):** Base `#DC2626` (Light) / `#F87171` (Dark). Surface Tint: `#FEF2F2`. Foreground: `#991B1B`.
- **Bimonetary Accent:** Dedicated badge tone `#1E40AF` for currency differential tags.

## Typography

The type scale separates communicative narrative content from transactional numeric readouts.

### Type Pairing Architecture
- **Primary Sans (Inter):** Applied across all navigational targets, headings, input forms, and status descriptors. Features clear distinct apertures ensuring legibility at steep viewing angles on POS countertops.
- **Technical Monospace (JetBrains Mono):** Mandatory for monetary valuations, currency signs, exchange ratios, process identifiers (`<0.154.0>`), restart intensity counts, memory byte tables, and timestamps.

### Bimonetary & Number Formatting Directives
- Numbers must always render with CSS `font-variant-numeric: tabular-nums lining-nums` or rely on `JetBrains Mono` to prevent column shifting during live streaming updates.
- **Format Requirements:**
  - Mexican Pesos: `$1,234.56` (implicit MXN) or `$1,234.56 MXN`.
  - US Dollars: `US$12.00` (explicit prefix).
  - Exchange Rates: Exact 4-decimal precision `TC: 18.2000`.

## Layout & Spacing

The interface implements a fluid dense-grid layout optimized for touch targets on terminals (minimum 48px hit boundaries) while maintaining high data density for operations monitors.

### Screen Adaptations
- **Mobile Handheld (360px - 767px):** Single-column layout. Sticky quick-action bar anchored to the bottom. OTP monitors reflow into accordion-style list structures.
- **POS Tablet / Dual-Display (768px - 1024px):** Asymmetric split-pane: 60% item catalogue/numpad, 40% active receipt ticket. Supervision trees simplify into horizontal swimlanes.
- **Desktop / NOC Control Room (1025px+):** 12-column dynamic grid. OTP node maps occupy up to 8 columns with synchronized split inspector panes and real-time message logs in the remaining 4 columns.

### Rhythmic Density
Use dense vertical padding (`space-xs` and `space-sm`) inside tables and OTP tree leaves to maximize visible node density without sacrificing vertical baseline rhythm.

## Elevation & Depth

This system intentionally eliminates soft, diffuse consumer shadows. It uses structured border mechanics and high-contrast tonal containment to guarantee structural boundaries under all physical display settings.

### Tier Structure
- **Level 0 (Canvas Base):** Flat background tone (`#F4F5F7` Light / `#0B0F17` Dark).
- **Level 1 (Card & Module Layer):** Solid surface (`#FFFFFF` Light / `#131B26` Dark) combined with a mandatory 1px solid border (`#E2E4E9` Light / `#243042` Dark). No shadow.
- **Level 2 (Active Focus & Flyouts):** Used for currency calculators, cash drawers, and OTP worker inspector popovers. Rendered with an explicit 1px outline (`#0B6E4F` or `#10B981`) and a rigid, dark offset shadow: `0px 4px 0px 0px rgba(15, 23, 42, 0.08)` in light mode, or `0px 4px 12px 0px rgba(0, 0, 0, 0.5)` in dark mode.
- **Level 3 (Modal Alerts & Crash Overlays):** Deep solid neutral backing paired with high-contrast border and a hard scrim (`rgba(15, 23, 42, 0.7)`).

## Shapes

Corner radii adhere strictly to industrial softness (`roundedness: 1` — 0.25rem / 4px base). 

- **Containers, Cards & Data Tables:** 4px radius (`0.25rem`). Maintains the architectural feel of physical hardware consoles.
- **Buttons, Text Inputs, and Segmented Switches:** 4px radius (`0.25rem`). Prevents touch boundary visual overlap.
- **Badges, Tags, and OTP Process PIDs:** 2px radius (`0.125rem`) for compact, badge-like density.
- **Circular Elements:** Reserved exclusively for status indicator pips and process lifecycle avatar nodes.

## Components

### Buttons & Touch Triggers
- **Primary:** Background `#0B6E4F`, text white, weight 600. No shadow, 1px border `#08503A`. Minimum tap area: 48px × 48px.
- **Secondary:** Surface white, 1px border `#D1D5DB`, text `#0F172A`.
- **Destructive / Reset:** Background `#DC2626`, text white. Requires confirmation states when terminating OTP workers or voiding completed sales.

### Form Inputs & Monetary Fields
- Numeric input fields must enforce monospaced numerals with prominent currency pre-labels (`MXN $` or `USD US$`).
- Direct feedback states with high-contrast rings (2px solid `#0B6E4F`) on focus.

### Status Indicators
- Must always consist of an SVG status glyph, an active color dot, and unambiguous Spanish text:
  - Check icon + Dot + **"Operando"**
  - Alert triangle + Dot + **"Alerta"**
  - Octagon alert / X + Dot + **"Falla"**

### Thermal Counter Ticket ("COMPROBANTE INTERNO")
- **Visual Treatment:** White receipt card framed by dashed demarcation lines `#9CA3AF`, simulated 80mm thermal paper width (`max-width: 384px`), styled in `JetBrains Mono`.
- **Mandatory Header:** Explicit all-caps warning block:
  `COMPROBANTE INTERNO — NO ES CFDI`
  Must include date/time, Cajero ID, Sucursal Tijuana Centro, and dual subtotal rows:
  - `TOTAL MXN: $1,234.56`
  - `TOTAL USD: US$67.83`
  - `T.C. VENTA: 18.2000`

### Erlang/OTP Supervision Tree Visualizer
- **Tree Canvas:** Orthogonal connection lines (1px solid `#94A3B8`) connecting supervisor nodes to monitored children processes.
- **Node Element:** Rigid rectangle containing:
  - Process Type Badge: `supervisor` (primary badge) or `worker` (subdued badge).
  - Identifier: `<0.241.0>` (mono).
  - Restart Strategy: `one_for_all`, `one_for_one`, or `rest_for_one`.
  - Status Tag: `Operando`, `Alerta`, or `Falla`.
  - Restart Counter: `restarts: 0/5 (60s)`.

### Simulation Mode Switch (Conmutador de Simulación)
- Prominent toggle control at the system header.
- **Active State:** When simulation is active, trigger an unmistakable global striped amber-black hazard border banner (4px top edge) and badge: `MODO SIMULACIÓN ACTIVO — SIN IMPACTO FISCAL NI HARDWARE`.