# DESIGN_SYSTEM (Native Swift Track)

Last updated: 2026-03-06
Supersedes for active runtime: `DESIGN_SYSTEM.md`
Runtime scope: `native/SamsWorkoutNative`

## 1. Design Principles

- Native macOS first, not browser emulation.
- Clear hierarchy over decoration.
- System semantic colors for status and affordance.
- Dense-but-readable analytics and settings surfaces.

## 2. Core UI Primitives

- Root layout: `NavigationSplitView`
- Page containers: `ScrollView` with vertically stacked sections
- Information groupings: `GroupBox`
- Status surfaces: bordered `StatusBannerView`
- Primary actions: `.buttonStyle(.borderedProminent)`
- Secondary actions: `.buttonStyle(.bordered)`

## 3. Semantic Color Usage

- Informational status: `.blue`
- Success status: `.green`
- Warning status: `.orange`
- Error status: `.red`
- Secondary copy: `.secondary`
- Tertiary support copy: `.tertiary`

## 4. Spacing and Layout Tokens

Observed layout values in the native app:

- Tight inline spacing: `6`
- Standard inline spacing: `8`
- Control row spacing: `12`
- Section spacing: `16`
- Large page spacing: `24`
- Page rhythm spacing: `32`
- Setup/root padding: `20`
- Status banner corner radius: `10`

## 5. Window and Navigation Constraints

- Root app minimum frame: `1080 x 720`
- Sidebar minimum width: `200`
- Detail pane is the primary working surface

## 6. Typography Patterns

- Page titles: `.largeTitle.bold()`
- Group headings: `.headline`
- Supporting copy: `.callout`
- Metadata / status text: `.caption`

## 7. Interaction Standards

- Buttons and toggles must remain keyboard navigable.
- Long-running work must expose visible progress or status.
- Error states must use `StatusBannerView` or equivalent explicit copy.
- Settings actions that mutate persistence or integrations must be surfaced inline with timestamps or summaries.
