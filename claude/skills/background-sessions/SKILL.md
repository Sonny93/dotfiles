---
name: background-sessions
description: >
  Start work in separate Claude Code sessions that run in the background
  (`claude --bg`) and show up in the user's agent view and Remote Control,
  one session per subject. Use whenever the user asks to run something in
  another session or conversation, whatever the wording: "lance ça dans
  une autre session", "dans une nouvelle conversation", "dans des sessions
  à part", "en parallèle dans d'autres sessions", "ouvre une session pour",
  "start a new session/conversation for", "run these in separate sessions".
  The subjects can be anything (a Notion ticket, a study, a bug, a
  question). Never use a subagent or tmux for these requests.
---

# Background sessions

The user follows sessions from the agent view (`claude agents`) and Remote Control, and answers their questions there. A subagent dies with this conversation and is invisible there; a session started in tmux is invisible there too, and its questions wait unseen.

## 1. Decide it is a session request

- Words about a session or a conversation (session, conversation, nouvelle conversation, autre session, à part) mean a background session. Nothing else does.
- Several unrelated subjects handed at once for work (for example several Notion tickets through `notion-ticket`) also count as a session request, without asking, even when the words don't mention a session.
- "Un agent", "en parallèle", "délègue" alone are ambiguous: ask whether the user wants a separate session or a subagent of this conversation, unless the context already settles it.
- Any other doubt (how many sessions, which subject goes where, one session or several): ask before launching.

## 2. One session per subject

The user names the subjects; one session each, never a split of your own. A subject can be a ticket, a study, a fix, a question. Related subjects (same feature, same files, a dependency, shared context) stay in one session rather than being split. When the user handed the work to this conversation (as `notion-ticket` does with several tickets), this session may keep one subject for itself and only the others are launched. When two subjects will likely edit the same files, say so and ask whether to run them in parallel or one after the other.

## 3. Write each prompt

The new session knows nothing of this conversation: the prompt must stand on its own.

- A Notion ticket: `Occupe-toi du ticket Notion <url>` (it loads `notion-ticket`, which stops before committing), plus anything the user said about it.
- Anything else: the user's request in their words, plus the context this conversation holds that the session needs (files, decisions, constraints), and what to deliver (a report, a plan, a fix waiting for review).
- Always add one line naming the other sessions launched at the same time and their subjects, so each stays in its scope.
- Write it in French, the user's language.

## 4. Launch

From the project directory, one command per session:

```bash
claude --bg -n <project>-<short-name> [--worktree <short-name>] --permission-mode <mode> "<prompt>"
```

- `<short-name>`: a few words in kebab-case from the subject (`franchise-rate-limit`, `etude-acces`).
- `--worktree <short-name>` when the session may edit files in a git repository (a devslot repository requires it for edits); leave it out for a read-only study or a question.
- `--permission-mode`: the mode this session runs in (`auto` in auto mode), unless the user says otherwise.
- Quote the prompt safely (single quotes, or a heredoc into a variable) so apostrophes and backticks survive.

## 5. Check and report

- `claude agents --json`: every new session must appear with its name. One missing: read `claude logs <id>` and say what went wrong.
- Tell the user the session names and what each one does, in one short list.
- Do not follow, answer for, or commit for these sessions: the user drives them from the agent view.

## Recovering a session started the wrong way

A session started in tmux or another interactive terminal: find its `sessionId` in `claude agents --json`, stop its process (`tmux kill-session -t <name>` for tmux), then `claude --bg --resume <sessionId> -n <name> --permission-mode <mode>`; it keeps its working directory and conversation. A question it was showing is lost: send it a message (SendMessage to its name) asking it to ask again.
