---
name: accessibility
description: >
  Accessibility rules (WCAG 2.2 AA) for UI code — semantics, keyboard, focus,
  contrast, labels, ARIA, dialogs, motion, target size, plus React Native and
  CLI output. Use when creating or editing components, pages, forms, modals,
  design tokens, styles, Storybook stories or terminal output.
  Triggers: a11y, accessibility, WCAG, ARIA, aria-label, role, focus, tabIndex,
  keyboard, screen reader, contrast, alt, label, dialog, modal, tooltip, tabs,
  accessibilityLabel, NO_COLOR, .tsx, .css, .stories.tsx.
---

These are defaults: apply them as far as the project allows, and follow the project when its needs differ (see "Applying These Rules" in `CLAUDE.md`).

**Proportionality.** Scale to the project. A small PWA, script or prototype gets the **Always** list; a public site, a product used by many people, or a shared component library gets everything. Skip an item that does not pay off here and name it once in the final report, never in every message.

Target: WCAG 2.2 AA.

---

# Always

Design never overrides these.

- Native elements first: `button`, `a`, `label`, `input`, `dialog`. Never `div onClick`.
- Everything operable by keyboard; no keyboard trap.
- Visible focus with `:focus-visible`. The style is free as long as it is visible with 3:1 contrast.
- Focus not obscured by sticky UI (2.4.11).
- Accessible name for every control; icon-only buttons need `aria-label`.
- Text contrast 4.5:1 (3:1 for large text); UI components and meaningful graphics 3:1.
- Form fields have a programmatic label; errors linked with `aria-describedby`, never conveyed by color alone.
- `lang` on `<html>`; logical heading order; landmarks (`main`, `nav`, `header`).
- `alt` on images, `alt=""` for decorative ones.
- Respect `prefers-reduced-motion`.
- Target size at least 24x24 CSS px (2.5.8).
- Dialogs move focus in, contain it, restore it on close, and close on Escape.

```tsx
// ❌
<div onClick={save} className="icon-save" />

// ✅
<button type="button" onClick={save} aria-label="Save">
  <SaveIcon aria-hidden="true" />
</button>
```

```tsx
<label htmlFor="email">Email</label>
<input id="email" aria-invalid={!!error} aria-describedby={error ? 'email-error' : undefined} />
{error && <p id="email-error">{error}</p>}
```

---

# When it pays off

**Design may win** (say in one line what is lost):
- AAA contrast (7:1): lost for low-vision users in bright light.
- Denser layouts, above the 24px minimum.
- Hover-revealed secondary actions, if also reachable on keyboard focus.
- Custom widgets instead of native ones, only when the WAI-ARIA APG pattern is implemented fully (roles, states, keyboard map).

**ARIA**
- No ARIA is better than bad ARIA. Use a native element before a role.
- Follow the APG pattern for tabs, menu, combobox, dialog, disclosure.
- `aria-*` states (`expanded`, `selected`, `pressed`, `current`) stay in sync with the UI.
- Live regions (`role="status"`, `aria-live="polite"`) for async results: toasts, form submission, search counts.

**React and Inertia**
- After a route change or Inertia visit, move focus to the page heading or `main` and update `document.title`.
- Announce async results through a live region that exists before the update.
- Keep `aria-hidden` off focusable elements.

**React Native / Expo**
- `accessibilityLabel`, `accessibilityRole`, `accessibilityState` on touchables.
- Hit areas at least 44x44 pt (iOS) / 48 dp (Android); use `hitSlop` when the visual is smaller.

**CLI**
- Information never by color alone; add a symbol or word.
- Honor `NO_COLOR` and non-TTY output.
- Plain-text fallback for spinners and progress (one line per step).
- Keep output linear so screen readers read it in order.

**Semantic check tools miss**
- Is the name or `alt` meaningful ("Delete invoice 42", not "button" or "image1.png")?
- Does the role match the behavior (a link that navigates, a button that acts)?
- Does the reading and focus order match the visual order?

---

# When NOT to apply

- Throwaway prototypes run locally, not shown to users.
- Generated code and third-party components you do not edit.
- Purely decorative content already hidden with `aria-hidden` or `alt=""`.

---

# Rationalizations to reject

| Rationalization | Reality |
| --- | --- |
| "Nobody here uses a screen reader" | Keyboard, zoom, low vision and temporary injuries affect everyone. |
| "The focus ring looks ugly" | Restyle it; do not remove it. |
| "A `div` with `onClick` is faster" | It has no role, no focus and no Enter/Space handling. |
| "Color is enough to show the error" | Add text and `aria-describedby`; color-blind users miss it. |
| "I'll add ARIA to fix it" | Wrong ARIA is worse than none; fix the element first. |
| "axe passes" | axe cannot judge whether names, roles and focus order make sense. |
| "Placeholder works as a label" | It disappears on input and has low contrast. |
| "It's an icon, everyone knows it" | Without an accessible name it is silent to assistive tech. |

---

# Tools

Run what is present in the project; never install a tool without asking.

- The `jsx-a11y` lint rules through the project lint script (oxlint plugin, enabled by the `@minimalstuff/tooling` react preset, or `eslint-plugin-jsx-a11y`).
- `vitest-axe` in component tests, `@axe-core/playwright` in end-to-end tests.
- Storybook `@storybook/addon-a11y` with the test-runner.
- Lighthouse accessibility audit.
- Manual keyboard pass: Tab, Shift+Tab, Enter, Space, Escape, arrows. Tools do not replace it.
