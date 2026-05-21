| Classification | Description | Location | Feature |
|----------------|-------------|----------|---------|
| temporary-solution | Hardcoded fallback palette — replace with theme provider lookup | src/theme/colors.ts:42 | dark-mode |
| incomplete | Add dark mode toggle to mobile nav | src/components/MobileNav.tsx:18 | dark-mode |
| dependency-limitation | Waiting for styled-components v6 `colorScheme` prop | src/theme/provider.ts:73 | dark-mode |
| tech-debt | CSS variable naming inconsistent with design tokens spec | src/styles/variables.css:91 | [?] dark-mode |
| tech-debt | Remove legacy color override after migration | src/legacy/overrides.ts:12 | dark-mode |
