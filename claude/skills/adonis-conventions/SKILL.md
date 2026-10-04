# Stack

AdonisJS v7, TypeScript strict, Node.js 24, Lucid ORM, VineJS, Japa

---

# Architecture — Service Layer

Controllers are thin. Services own the logic. Transformers own the output shape.

```
app/
├── controllers/         # HTTP only — validate, call service, serialize
├── services/            # Business logic — no HttpContext, no request, no response
├── models/              # Lucid models — persistence only, no business logic
├── transformers/        # One transformer per model — owns the JSON output shape
├── validators/          # VineJS schemas — one file per resource action
├── exceptions/          # Typed domain exceptions extending Exception
├── middleware/          # Cross-cutting HTTP concerns
└── policies/            # Bouncer authorization policies

start/
└── routes.ts            # Grouped by domain, named routes only
```

**Controller — one action per controller, max two methods:**

- `render` — handles GET requests (display a page or return JSON data)
- `execute` — handles all other verbs (POST, PATCH, PUT, DELETE)

A controller that only mutates data has no `render`. A controller that only displays has no `execute`.

Naming: `<action>_<resource>_controller.ts` — never a generic resource controller.

```
# Inertia (SSR pages)
show_posts_controller     → render: display posts list
show_post_controller      → render: display single post
create_post_controller    → render: display form / execute: create post
edit_post_controller      → render: display edit form / execute: update post
delete_post_controller    → execute: delete post (no render)

# JSON API
show_posts_controller     → render: return posts list
show_post_controller      → render: return single post
create_post_controller    → execute: create post (no render)
update_post_controller    → execute: update post (no render)
delete_post_controller    → execute: delete post (no render)
```

Each method follows these steps:
- `render`: call service → return `inertia.render()` or `serialize(Transformer.transform(result))`
- `execute`: validate input → call service → redirect or return `serialize(Transformer.transform(result))`

**Service — rules:**
- All business logic lives here — zero framework imports allowed
- Never import `HttpContext`, `request`, or `response`
- One service per domain: `UserService`, `BillingService` — never `AppService`
- Services can call other services, max 2 levels deep
- Services are **always classes** decorated with `@inject()` — never plain exported functions
- Inject via constructor (Adonis IoC container handles instantiation)
- Jobs support `@inject()` the same way controllers do — always use it

```ts
// ✅ correct
import { inject } from '@adonisjs/core'

@inject()
export class WhisperService {
  async transcribeLocal(...) {}
}

// ✅ consumer (controller or job)
@inject()
export default class ProcessVodJob extends Job<Payload> {
  constructor(private readonly whisperService: WhisperService) {
    super()
  }
}

// ❌ wrong — plain exported functions prevent injection and mocking
export async function transcribeLocal(...) {}
```

**Model — rules:**
- Columns, relationships, hooks only
- No business logic — `User.createWithWelcomeEmail()` belongs in `UserService`
- Query scopes are allowed for reusable query fragments
- Never call `Model.query()` directly in controllers

---

# Transformers — mandatory for all responses

Every HTTP response that returns data must go through a transformer. Never return raw models, raw objects, or `JSON.stringify` manually.

**Pattern:**
```ts
// app/transformers/post_transformer.ts
import { BaseTransformer } from '@adonisjs/core/transformers'
import type Post from '#models/post'

export default class PostTransformer extends BaseTransformer<Post> {
  toObject() {
    return this.pick(this.resource, [
      'id',
      'title',
      'content',
      'createdAt',
      'updatedAt',
    ])
  }
}

// app/posts/show_posts_controller.ts
async render({ serialize }: HttpContext) {
  const posts = await this.postService.getAll()
  return serialize(PostTransformer.transform(posts))
}

// app/posts/show_post_controller.ts
async render({ serialize, params }: HttpContext) {
  const post = await this.postService.getById(params.id)
  return serialize(PostTransformer.transform(post))
}
```

**Rules:**
- One transformer per model: `UserTransformer`, `PostTransformer` — never reuse for different shapes
- Use variants for different output contexts (e.g. `PostTransformer.variant('summary')`)
- Relationships: transform nested resources with their own transformer — never inline
- Never expose: `password`, `rememberMeToken`, internal flags, audit fields unless explicitly needed
- Always use `this.pick()` — never spread the whole model (`{ ...this.resource }`)
- Transformers generate TypeScript types for the frontend — keep them stable

---

# File & Module Structure

- One class per file
- Filename matches exported class in snake_case: `UserService` → `user_service.ts`
- Group by domain: `app/users/` holds controller + service + validators + transformer + policy
- No barrel `index.ts` files — import from the source file directly
- Generated barrel file `#generated/controllers` is the only exception (Adonis v7 convention)
- Max ~150 lines per file — extract when it grows beyond that

```
app/
├── users/
│   ├── show_users_controller.ts
│   ├── show_user_controller.ts
│   ├── create_user_controller.ts
│   ├── update_user_controller.ts
│   ├── delete_user_controller.ts
│   ├── user_service.ts
│   ├── user_transformer.ts
│   ├── user_policy.ts
│   └── validators/
│       ├── create_user_validator.ts
│       └── update_user_validator.ts
├── posts/
│   ├── show_posts_controller.ts
│   ├── show_post_controller.ts
│   ├── create_post_controller.ts
│   ├── update_post_controller.ts
│   ├── delete_post_controller.ts
│   ├── post_service.ts
│   ├── post_transformer.ts
│   └── validators/
│       ├── create_post_validator.ts
│       └── update_post_validator.ts
```

---

# Validation — VineJS

- Every route with a body or query params has a dedicated VineJS validator
- Validators live in `app/<domain>/validators/<action>_<resource>_validator.ts`
- Validation happens in the controller — never in services
- Never access `request.body()` or `request.all()` without validating first
- Fail with field-level messages — never `"Invalid input"`

```ts
// app/users/validators/create_user_validator.ts
import vine from '@vinejs/vine'

export const createUserValidator = vine.compile(
  vine.object({
    email: vine.string().email().normalizeEmail(),
    password: vine.string().minLength(8),
    name: vine.string().trim().minLength(2),
  })
)

// In controller:
const payload = await request.validateUsing(createUserValidator)
const user = await this.userService.create(payload)
return serialize(UserTransformer.transform(user))
```

---

# Error Handling

- Never throw generic `Error` — create typed exceptions in `app/exceptions/`
- Extend `Exception` from `@adonisjs/core/exceptions`
- Encode HTTP status and error code in the class:

```ts
import { Exception } from '@adonisjs/core/exceptions'

export class UserNotFoundException extends Exception {
  static status = 404
  static code = 'E_USER_NOT_FOUND'
}
```

- Services throw domain exceptions — controllers never catch and reformat
- Use the global exception handler in `app/exceptions/handler.ts` for consistent error shapes
- Never expose stack traces or internal error messages to HTTP responses

---

# Routes

- Group routes by domain with a shared prefix and middleware
- Route names are explicit action-based — never use REST conventions (`index`, `store`, `update`, `destroy`)
- Use `<domain>.<action>` pattern: `posts.show_posts`, `posts.create_post`, `posts.delete_post`
- Never hardcode URLs — use `router.makeUrl('posts.show_post', { id })`
- HTTP verbs must match intent: `GET` reads, `POST` creates, `PATCH` partial update, `PUT` full replace, `DELETE` removes
- Import controllers via `#generated/controllers` barrel (Adonis v7):

```ts
import { controllers } from '#generated/controllers'

router.group(() => {
  router.get('/', [controllers.ShowPosts, 'render']).as('posts.show_posts')
  router.get('/:id', [controllers.ShowPost, 'render']).as('posts.show_post')
  router.get('/create', [controllers.CreatePost, 'render']).as('posts.create_post')
  router.post('/', [controllers.CreatePost, 'execute']).as('posts.create_post')
  router.get('/:id/edit', [controllers.EditPost, 'render']).as('posts.edit_post')
  router.patch('/:id', [controllers.EditPost, 'execute']).as('posts.edit_post')
  router.delete('/:id', [controllers.DeletePost, 'execute']).as('posts.delete_post')
}).prefix('/posts').middleware([middleware.auth()])
```

---

# Database & Lucid

- Migrations for every schema change — never edit DB directly
- Always preload relationships explicitly — no lazy loading in loops
- Wrap multi-step writes in a transaction
- Column names: `snake_case` in DB, `camelCase` in model via `@column` decorator
- Never write raw SQL inline in a controller or service — wrap in a model scope or dedicated query method

---

# Testing — Japa

- Feature tests for every controller route: happy path + main error cases
- Unit tests for services with non-trivial business logic
- Use `testUtils.db().withGlobalTransaction()` to isolate DB state between tests
- Use model factories for test data — never hardcode fixture objects inline
- Test file mirrors source: `user_service.spec.ts` next to `user_service.ts`
- Assert on transformer output shape, not raw model fields

---

# Commands

```bash
node ace make:controller <name>     # Generate controller
node ace make:transformer <name>    # Generate transformer
node ace make:service <name>        # Generate service
node ace make:validator <name>      # Generate VineJS validator
node ace make:migration <name>      # Generate migration
node ace make:model <name>          # Generate Lucid model
node ace list:routes                # List all registered routes
node ace test                       # Run Japa tests
```
