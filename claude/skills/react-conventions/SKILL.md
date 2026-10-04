---
name: react-conventions
description: >
  React conventions and architecture rules. Use when creating or editing
  components, hooks, pages, layouts, or any React/TSX file. Also use when
  asked to add a feature, refactor UI code, or generate React boilerplate.
---

# Stack

React 19, TypeScript strict, clsx/cn() for classnames.
Projects are either React + Inertia (AdonisJS, frontend in `inertia/`) or React standalone (Vite / Next.js).

---

# File & Module Structure

- All filenames in snake_case: `user_badge.tsx`, `use_auth.ts`, `post_card.tsx`
- One export per file — one component, one hook, one helper
- Group by domain, not by type

## Folder structure

```
inertia/
├── shared/              # Primitives with zero business logic (Button, Badge, Input, Modal)
├── pages/               # Inertia page components — one per controller action
│   └── posts/
│       ├── show_posts.tsx
│       ├── show_post.tsx
│       └── create_post.tsx
├── posts/               # Domain — components, hooks, helpers for posts
│   ├── shared/          # Shared across multiple post pages
│   ├── show_posts/      # Specific to the show_posts page
│   │   ├── post_list.tsx
│   │   └── post_filters.tsx
│   └── show_post/       # Specific to the show_post page
│       ├── post_detail.tsx
│       └── post_comments.tsx
└── users/
    ├── shared/
    ├── show_users/
    └── show_user/
```

## Promotion rules

A component starts in the most specific folder. It moves up only when reused:

1. Used in one page → lives in `<domain>/<page>/`
2. Used in multiple pages of the same domain → moves to `<domain>/shared/`
3. Used across multiple domains → moves to `inertia/shared/`

Never pre-emptively put something in `shared/` — wait until the second use.

## Subdivide a domain folder when it exceeds ~8 files

```
inertia/posts/
├── list/
├── detail/
└── shared/
```

## Max ~100 lines per file — decompose when it grows beyond that

---

# Components

## Pure components (JSX only — no state, no effects, no variables)

Use a `const` arrow function with implicit return:

```tsx
// post_badge.tsx
interface PostBadgeProps {
  label: string
  className?: string
}

export const PostBadge = ({ label, className }: Readonly<PostBadgeProps>) => (
  <span className={cn('inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium', className)}>
    {label}
  </span>
)
```

## Components with logic (state, effects, variables)

Use a named `function` declaration with explicit return:

```tsx
// post_card.tsx
interface PostCardProps {
  postId: string
  onDelete: (id: string) => void
}

export function PostCard({ postId, onDelete }: Readonly<PostCardProps>) {
  const { post, isLoading } = usePost(postId)

  if (isLoading) return <PostCardSkeleton />

  const handleDelete = () => onDelete(postId)

  return (
    <div className={cn('rounded-lg border p-4')}>
      <h2>{post.title}</h2>
      <button onClick={handleDelete}>Delete</button>
    </div>
  )
}
```

## Inertia page components

Always a named `function` declaration — never a const arrow. **Must use `export default`** — Inertia resolves pages by default export:

```tsx
// inertia/pages/posts/show_post.tsx
interface ShowPostProps {
  post: PostResource
}

export default function ShowPost({ post }: Readonly<ShowPostProps>) {
  return (
    <div>
      <PostDetail post={post} />
    </div>
  )
}
```

## Rules

- Props declared via `interface` or `type` in the same file — never in a global `types.ts`
- Always `Readonly<Props>` — props are never mutated
- Use `interface` for plain prop shapes, `type` when composing other types — follow global TS conventions
- `children` typed as `React.ReactNode`
- Always named exports — never default exports, **except** Inertia page components which must use `export default` (Inertia resolves pages by default export)
- No logic inside JSX — ternaries, `.map()` with logic, nested conditions → extract to a variable or component
- Max 2 levels of JSX nesting before extracting a sub-component
- Never pass more than 3 props through an intermediary component — use composition or `children`

---

# Classnames

Always use `cn()` — never template literals for conditional or combined classes:

```tsx
// ❌
<div className={`base-class ${isActive ? 'active' : ''} ${className}`}>

// ✅
<div className={cn('base-class', isActive && 'active', className)}>
```

- Base classes first, conditional classes after, forwarded `className` last
- Always accept and forward a `className` prop on reusable components in `shared/`

---

# Hooks

- One hook per file — even if it's 5 lines
- Filename: `use_<name>.ts` — never `.tsx` unless the hook returns JSX (rare)
- Hook name matches filename: `use_auth.ts` → `useAuth()`
- Return type always explicitly typed — never rely on inference:

```ts
// use_posts.ts
interface UsePostsReturn {
  posts: Post[]
  isLoading: boolean
  error: string | null
  refetch: () => void
}

export function usePosts(): UsePostsReturn {
  // ...
}
```

- Never put fetch logic directly in a component — always in a hook
- A hook wrapping a single `useState` is only worth extracting if it adds logic

---

# JSX Discipline

- No anonymous functions in JSX — always extract handlers:

```tsx
// ❌
<button onClick={() => { setOpen(true); track('click') }}>

// ✅
const handleOpen = () => {
  setOpen(true)
  track('click')
}
<button onClick={handleOpen}>
```

- No nested ternaries in JSX — extract to a variable or sub-component
- Lists always have a stable, unique `key` — never array index as key
- Use `<>` fragments instead of wrapping `<div>` when no DOM element is needed

---

# Composition over props drilling

```tsx
// ❌ Drilling through intermediaries
<Layout user={user} onLogout={onLogout}>
  <Page user={user} onLogout={onLogout} />
</Layout>

// ✅ Composition with children
<Layout>
  <Page />
</Layout>
```

- If a prop passes through a component without being used, stop and use composition or context

---

# Inertia-specific (AdonisJS projects)

- Page components live in `inertia/pages/<domain>/` — named after the controller action
- Use `router.get()` / `router.post()` from `@inertiajs/react` for navigation — never native `fetch` for Inertia actions
- Forms use `useForm()` from `@inertiajs/react` — never `useState` for form fields in Inertia pages