# shelly

shelly turns a request in plain words into one shell command, and then runs it.

```
$ shelly list the 3 most recent dirs in here
$ ls -dt -- */ | head -n 3
delta/
epsilon/
gamma/
```

The first line is the request that you type.
The second line is the command that the AI wrote. shelly shows it, and then runs it.

## How it works

shelly sends the request to an AI agent in non-interactive mode.
It uses [Claude Code](https://github.com/anthropics/claude-code) first, as `claude -p --dangerously-skip-permissions`.
If `claude` is not in your `PATH`, or if `claude` fails, shelly uses the
[Codex CLI](https://github.com/openai/codex), as `codex exec --yolo`.
Both harnesses use the login that you already have. shelly needs no API key.

The agent can look at your system before it replies. For example, it can read files or `--help` output.
It does not do the request itself. Its reply is one line that starts with a tag.

| Reply | What shelly does |
| --- | --- |
| `RUN <command>` | Shows `$ <command>` and runs it. The exit status of shelly is the status of the command. |
| `ASK <command>` | Shows the command and asks `[y/N]` before it runs it. The agent uses `ASK` for commands that delete, overwrite, stop processes or publish data. |
| `SAY <text>` | Prints the text on stdout. Nothing runs. The agent uses `SAY` for a general question that needs no command. |
| `ERR <text>` | Prints the text on stderr and exits with status 1. The agent uses `ERR` when it cannot make a command. |

If the reply has no tag line, shelly shows the reply and exits with status 2.

The command runs with `bash -c` in the current directory.
The standard input of shelly goes to the command, so a pipe into shelly works.

```
ps aux | shelly show the 5 processes that use the most memory
```

## Requirements

- Bash 4.4 or later.
- `claude` (Claude Code) or `codex` (the Codex CLI), installed and logged in.
- Python 3, only for the tests.

## Install

1. Clone the repository.

   ```
   git clone https://github.com/fcecin/shelly.git ~/shelly
   ```

2. Put `shelly` in a directory in your `PATH`.

   ```
   ln -s ~/shelly/shelly ~/.local/bin/shelly
   ```

3. Optional. Add this line to `~/.bashrc` (see [Run commands in your own shell](#run-commands-in-your-own-shell)).

   ```
   eval "$(shelly --init)"
   ```

## Usage

```
shelly [-n] [-y] <request ...>
shelly --init
```

| Option | Function |
| --- | --- |
| `-n` | Print the command on stdout. Do not run it. |
| `-y` | Run an `ASK` command without the question. |
| `--init` | Print the bash function for your own shell. |
| `-h`, `--help` | Show the help. |

| Environment variable | Function |
| --- | --- |
| `SHELLY_HARNESS` | Set to `claude` or `codex` to use only that harness. |
| `SHELLY_CLAUDE_ARGS` | More arguments for `claude`, for example `--model sonnet` or `--effort low`. |
| `SHELLY_CODEX_ARGS` | More arguments for `codex exec`. |
| `SHELLY_HOME` | The tool home. The default is `~/.shelly`. |

Your shell expands `*`, `?`, `$` and quotes before shelly gets the request.
Put the request in quotes when it contains these characters.

```
shelly "what's the biggest file in here?"
```

## Run commands in your own shell

A program cannot type a line into your shell prompt. Thus, by default the command runs in a child process.
In a child process, `cd` and `export` have no effect after the command ends.

The `--init` function removes this limit. It runs the command with `eval` in your interactive bash.
With the function, `cd` and `export` stay, and the command goes into your history.
Push the up arrow to run the command again or to change it.

```
$ shelly go into the most recent dir
$ cd -- "$(ls -td -- */ | head -n 1)"
```

Without the function, a request like this gets an `ERR` reply that tells you to add the function.

## The tool home

shelly uses `~/.shelly` as a home for the agent.

| Path | Contents |
| --- | --- |
| `bin/` | Tools that the agent writes. |
| `TOOLS.md` | The list of the tools. The agent keeps it current. shelly gives the list to the agent with each request. |
| `tmp/` | Scratch files of the agent. |
| `history.log` | One line for each request, with the time, harness, directory, request and reply. |

When a job is too long for one clear line, or when it is likely to come again, the agent writes a tool.
It tests the tool and adds a line for it to `TOOLS.md`. Its reply then calls the tool by its full path.
On a subsequent request, the agent uses the tool again.

```
$ shelly build a reusable tool that lists the N biggest files under a dir, then show the 3 biggest here
$ /home/you/.shelly/bin/bigfiles -n 3 .
$ shelly -n top 2 biggest files under gamma
/home/you/.shelly/bin/bigfiles -n 2 gamma
```

## Claude Code settings

shelly starts `claude` with `--safe-mode`.
Thus, your `CLAUDE.md` files, skills, hooks and MCP servers do not load, and `claude` starts more quickly.
The prompt tells the agent to read a `CLAUDE.md` or `AGENTS.md` file in the current directory when the request is about that project.

A request usually takes 3 to 10 seconds. A request that builds a tool can take approximately one minute.

## Safety

> **WARNING:** Read each command that shelly shows before you use shelly on important data.
> shelly runs `RUN` commands immediately, and the agent runs with all permission checks off.
> An incorrect command can cause loss of data.

> **WARNING:** Do not use `-y` unless you accept the risk.
> With `-y`, shelly also runs commands that delete or publish data without a question.

Use `-n` to see the command before it runs.

## Tests

The tests use fake `claude` and `codex` programs, so they do not call an AI.

```
tests/run.sh
```

## License

[MIT](LICENSE)
