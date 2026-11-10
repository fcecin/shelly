#!/usr/bin/env bash
# Tests for shelly. They use the fake harnesses in `tests/fake`, so they call no AI.
# Usage: tests/run.sh
# The tests put their files in a new directory under TMPDIR (default /tmp).
# The hook tests give code to an inner bash, so the single quotes are correct.
# shellcheck disable=SC2016

set -u

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
S=$REPO/shelly
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT

export FAKE_DIR=$T/state SHELLY_HOME=$T/home NO_COLOR=1
BASE=/usr/bin:/bin
FAKE=$REPO/tests/fake:$BASE
mkdir -p "$T/only-codex"
ln -s "$REPO/tests/fake/codex" "$T/only-codex/codex"

npass=0 nfail=0
out='' err='' rc=0
check() {
	local name=$1
	shift
	if "$@"; then
		npass=$((npass + 1))
		echo "ok   $name"
	else
		nfail=$((nfail + 1))
		echo "FAIL $name"
		echo "     out=[$out]"
		echo "     err=[$err]"
		echo "     rc=$rc"
	fi
}

# Start each test with no state, in an empty work directory.
reset() {
	rm -rf -- "$FAKE_DIR" "$SHELLY_HOME" "$T/work"
	mkdir -p "$FAKE_DIR" "$T/work"
	cd "$T/work" || exit 2
	unset FAKE_OUT FAKE_RC FAKE_CODEX_OUT FAKE_CODEX_RC SHELLY_HARNESS SHELLY_CLAUDE_ARGS
	P=$FAKE
}

# Run shelly with PATH=$P. This sets out, err and rc.
run() {
	out=$(PATH=$P "$S" "$@" 2>"$T/err" </dev/null)
	rc=$?
	err=$(cat -- "$T/err")
}

# Run shelly in a new pty and send the answer to the [y/N] question.
run_pty() {
	local answer=$1
	shift
	out=$(PATH=$P python3 -I "$REPO/tests/pty.py" "$answer" "$S" "$@")
	rc=$?
	err=''
}

# Run commands in a bash that has the --init function and the history on.
hook() {
	PATH=$P bash -c 'set -o history; HISTFILE=/dev/null; eval "$("$1" --init)"; eval "$2"' _ "$S" "$1"
}

t_run() { [[ $out == hello && $err == *'$ echo hello'* && $rc == 0 ]]; }
reset
export FAKE_OUT='thinking...\nRUN echo hello'
run list stuff
check "RUN shows the command and runs it" t_run

t_status() { [[ $rc == 7 ]]; }
reset
export FAKE_OUT='RUN exit 7'
run x
check "RUN gives the exit status of the command" t_status

t_say() { [[ $out == 'use tar -x' && $rc == 0 ]]; }
reset
export FAKE_OUT='SAY use tar -x'
run how to untar
check "SAY prints on stdout" t_say

t_err() { [[ -z $out && $err == *'no such thing'* && $rc == 1 ]]; }
reset
export FAKE_OUT='ERR no such thing'
run x
check "ERR prints on stderr and gives status 1" t_err

t_untagged() { [[ $rc == 2 && $err == *'did not reply'* && $err == *'I refuse'* && ! -e $FAKE_DIR/codex.args ]]; }
reset
export FAKE_OUT='I refuse to obey the format' FAKE_CODEX_OUT='RUN echo codex'
run x
check "a reply without a tag gives status 2 and does not ask codex" t_untagged

t_fallback() { [[ $out == from-codex && $err == *'claude failed with exit status 1'* && $err == *'API Error'* && $rc == 0 ]]; }
t_codex_args() {
	grep -qx exec "$FAKE_DIR/codex.args" && grep -qx -- --yolo "$FAKE_DIR/codex.args" &&
		grep -q 'You are the planner' "$FAKE_DIR/codex.stdin" && grep -qx 'Request: x' "$FAKE_DIR/codex.stdin"
}
reset
export FAKE_OUT='API Error: 500' FAKE_RC=1 FAKE_CODEX_OUT='RUN echo from-codex'
run x
check "codex runs when claude fails" t_fallback
check "codex gets exec --yolo and the full prompt on stdin" t_codex_args

t_only_codex() { [[ $out == only-codex && $rc == 0 ]]; }
reset
export FAKE_CODEX_OUT='RUN echo only-codex'
P=$T/only-codex:$BASE
run x
check "codex runs when claude is not in PATH" t_only_codex

t_none() { [[ $rc == 2 && $err == *'not in PATH'* ]]; }
reset
P=$BASE
run x
check "no harness in PATH gives status 2" t_none

t_force() { [[ $out == forced && ! -e $FAKE_DIR/claude.args ]]; }
reset
export FAKE_OUT='RUN echo claude' FAKE_CODEX_OUT='RUN echo forced'
SHELLY_HARNESS=codex run x
check "SHELLY_HARNESS=codex uses only codex" t_force

t_bad_harness() { [[ $rc == 2 && $err == *'must be claude or codex'* ]]; }
reset
SHELLY_HARNESS=gpt run x
check "an unknown SHELLY_HARNESS gives status 2" t_bad_harness

t_claude_args() {
	local a
	a=$(tr '\n' ' ' <"$FAKE_DIR/claude.args")
	[[ $a == *'-p --dangerously-skip-permissions --safe-mode --no-session-persistence'* &&
		$a == *'--append-system-prompt You are the planner'* &&
		$a == *'--model sonnet --effort low'* ]]
}
t_claude_stdin() { grep -qx 'Request: x' "$FAKE_DIR/claude.stdin"; }
reset
export FAKE_OUT='RUN echo hi'
SHELLY_CLAUDE_ARGS='--model sonnet --effort low' run x
check "claude gets its flags and SHELLY_CLAUDE_ARGS" t_claude_args
check "claude gets the request on stdin" t_claude_stdin

t_parse() { [[ $out == last ]]; }
reset
export FAKE_OUT='  RUN echo first\r\nnoise\n  RUN echo last  \r\n```'
run x
check "the last tag line wins, without blanks and CR" t_parse

t_dry() { [[ $out == 'touch made' && ! -e made && $rc == 0 ]]; }
reset
export FAKE_OUT='RUN touch made'
run -n make it
check "-n prints the command and does not run it" t_dry

t_dry_ask() { [[ $out == 'touch made' && $err == *destructive* && ! -e made ]]; }
reset
export FAKE_OUT='ASK touch made'
run -n make it
check "-n with ASK prints a note and does not run" t_dry_ask

t_yes() { [[ -e made && $rc == 0 ]]; }
reset
export FAKE_OUT='ASK touch made'
run -y make it
check "-y runs an ASK command without a question" t_yes

t_no_tty() { [[ ! -e made && $rc == 1 && $err == *'no terminal'* ]]; }
reset
export FAKE_OUT='ASK touch made'
out=$(PATH=$P setsid -w "$S" make it 2>"$T/err" </dev/null)
rc=$?
err=$(cat -- "$T/err")
check "ASK with no terminal does not run and gives status 1" t_no_tty

t_ask_yes() { [[ -e made && $out == *'[y/N]'* && $out == *RC=0* ]]; }
reset
export FAKE_OUT='ASK touch made'
run_pty y make it
check "ASK runs after a yes answer" t_ask_yes

t_ask_no() { [[ ! -e made && $out == *'did not run'* && $out == *RC=1* ]]; }
reset
export FAKE_OUT='ASK touch made'
run_pty n make it
check "ASK does not run after a no answer and gives status 1" t_ask_no

t_stdin() { [[ $out == $'a\nb' ]] && grep -q 'piped data' "$FAKE_DIR/claude.args"; }
reset
export FAKE_OUT='RUN sort'
out=$(printf 'b\na\n' | PATH=$P "$S" sort it 2>"$T/err")
rc=$?
err=$(cat -- "$T/err")
check "piped stdin goes to the command, and the prompt tells the AI" t_stdin

t_home() {
	[[ -d $SHELLY_HOME/bin && -d $SHELLY_HOME/tmp && -f $SHELLY_HOME/TOOLS.md ]] &&
		grep -q $'\tclaude\t'"$T/work"$'\tx\tRUN echo hi$' "$SHELLY_HOME/history.log"
}
t_tmp_clean() { [[ -z $(ls -A -- "$SHELLY_HOME/tmp") ]]; }
t_tools_prompt() { grep -q '# shelly tools' "$FAKE_DIR/claude.args"; }
reset
export FAKE_OUT='RUN echo hi'
run x
check "shelly makes its home and writes history.log" t_home
check "shelly removes its temporary directory" t_tmp_clean
check "TOOLS.md goes into the prompt" t_tools_prompt

t_bad_opt() { [[ $rc == 2 && $err == *'unknown option'* ]]; }
reset
run --bogus x
check "an unknown option gives status 2" t_bad_opt

t_no_args() { [[ $rc == 2 && $err == *usage* ]]; }
reset
run
check "no request prints the usage and gives status 2" t_no_args

t_emit_fd() { [[ $rc == 2 && $err == *'fd 3'* ]]; }
reset
run --emit x
check "--emit without fd 3 gives status 2" t_emit_fd

t_init_cd() { [[ $out == *"$T/work/sub dir|1"* && $out == *'cd "sub dir" && export ZZ=1'* ]]; }
t_init_prompt() { grep -q 'interactive bash shell' "$FAKE_DIR/claude.args"; }
reset
mkdir -p "sub dir"
export FAKE_OUT='RUN cd "sub dir" && export ZZ=1'
out=$(hook 'shelly go in </dev/null 2>/dev/null; echo "$PWD|$ZZ"; history 1' 2>&1)
check "--init: cd and export stay, and the history has the command" t_init_cd
check "--init: the prompt tells the AI that cd stays" t_init_prompt

t_init_say() { [[ $out == '[plain answer]' ]]; }
reset
export FAKE_OUT='SAY plain answer'
out=$(hook 'x=$(shelly q </dev/null 2>/dev/null); echo "[$x]"')
check "--init: SAY goes to stdout and nothing runs" t_init_say

t_init_err() { [[ $out == rc=1 ]]; }
reset
export FAKE_OUT='ERR nope'
out=$(hook 'shelly q </dev/null 2>/dev/null; echo "rc=$?"')
check "--init: ERR gives status 1" t_init_err

t_init_dry() { [[ $out == $'exit 3\nrc=0' ]]; }
reset
export FAKE_OUT='RUN exit 3'
out=$(hook 'shelly -n q </dev/null 2>/dev/null; echo "rc=$?"')
check "--init: -n prints the command and does not run it" t_init_dry

echo "passed $npass, failed $nfail"
((nfail == 0))
