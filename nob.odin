#+private file
package main

/*
nob.odin

USAGE: odin run . -- [OPTIONS]
OPTIONS:
	- b: executes only build commands
	- r: executes only run commands
	- d: executes only debug commands

By default it executes build and run commands.

Recommended directory structure:
```
project_dir
	├ src          // all source code
	├ nob.odin
	└ build.odin   // your build script
```

Example `build.odin`
```odin
package main

main :: proc() {
	watch(outfile = "./my_program", path = "./src", filetype = ".odin")
	build("odin", "build", "./src", "-out:my_program")
	run("./my_program")
}
```

Now simply do
```bash
odin run .
odin run . -- r
odin run . -- bd
odin run . -- b r
```
*/

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

@(private)
build :: proc(cmd: ..string) {
	exec_command(.Build, ..cmd)
}

@(private)
run :: proc(cmd: ..string) {
	exec_command(.Run, ..cmd)
}

@(private)
debug :: proc(cmd: ..string) {
	exec_command(.Debug, ..cmd)
}

// all commands between `start_parallel` and `end_parallel` will be executed in parallel with maximum number of concurrent jobs equal to `os.get_processor_core_count() - 1`.
@(private)
start_parallel :: proc() {
	g_state.parallel = true
	clear(&g_state.jobs)
}

@(private)
end_parallel :: proc() {
	wait_for_all_jobs_to_finish()
	g_state.parallel = false
}

// watch compares the mtime of outfile and path. If path is a dir then it checks all files inside path recursively. It effects only the immediate build, run or debug command.
@(private)
watch :: proc(outfile, path: string, filetype := "", loc := #caller_location) {
	out_fi, err := os.stat(outfile, context.temp_allocator)
	if err != nil do return
	if out_fi.type != .Regular {
		fmt.printfln("%v Error: outfile %q expected to be file, got %v", loc, outfile, out_fi.type)
		os.exit(1)
	}

	out_mtime_ns := out_fi.modification_time._nsec

	path_fi, err1 := os.stat(path, context.temp_allocator)
	if err1 != nil {
		fmt.printfln("%v Error: could not stat path %q", loc, path)
		os.exit(1)
	}

	#partial switch path_fi.type {
	case .Regular:
		g_state.skip = out_mtime_ns > path_fi.modification_time._nsec

	case .Directory:
		g_state.skip = true

		w: os.Walker
		os.walker_init_path(&w, path)
		defer os.walker_destroy(&w)

		for fi in os.walker_walk(&w) {
			// NOTE error not handled here
			if fi.type == .Regular {
				if strings.has_suffix(fi.fullpath, filetype) {
					if out_mtime_ns < fi.modification_time._nsec {
						g_state.skip = false
						return
					}
				}
			} else if fi.type == .Directory {
				if strings.has_suffix(fi.fullpath, ".git") {
					os.walker_skip_dir(&w)
				}
			}
		}

	case:
		fmt.printfln("%v Error: path %q expected to be file or dir, got %v", loc, path, path_fi.type)
		os.exit(1)
	}
}

//////////// INTERNAL ////////////

State :: struct {
	allowed_cmd_kinds: CmdKinds,
	skip:              bool,

	// parallel
	parallel:          bool,
	max_jobs:          int,
	cur_id:            int,
	jobs:              [dynamic]Job,
}

CmdKind :: enum {
	Build,
	Run,
	Debug,
}

CmdKinds :: distinct bit_set[CmdKind;u8]

g_state: State

@(init)
nob_init :: proc "contextless" () {
	context = runtime.default_context()
	if len(os.args) == 1 {
		g_state.allowed_cmd_kinds = {.Build, .Run}
	} else do for arg in os.args[1:] do for ch in arg {
		switch ch {
		case 'b':
			g_state.allowed_cmd_kinds += {.Build}
		case 'r':
			g_state.allowed_cmd_kinds += {.Run}
		case 'd':
			g_state.allowed_cmd_kinds += {.Debug}
		case:
			fmt.printfln("Invalid flag: %q. Using default options.", ch)
			g_state.allowed_cmd_kinds = {.Build, .Run}
		}
	}

	g_state.max_jobs = os.get_processor_core_count() - 1
}

exec_command :: proc(kind: CmdKind, cmd: ..string) {
	// handle file watcher(this should be first)
	if g_state.skip {
		g_state.skip = false
		return
	}

	// handle cli args
	if kind not_in g_state.allowed_cmd_kinds do return

	// handle parallel
	if g_state.parallel {
		id := wait_for_one_to_finish_and_add_job(cmd)
		fmt.printfln("JOB(%d) %v", id, cmd)
		return
	}

	// handle default
	fmt.println(cmd)

	desc := os.Process_Desc {
		working_dir = ".",
		command     = cmd,
	}
	state, stdout, stderr, err := os.process_exec(desc, context.allocator)
	if err != nil {
		fmt.printfln("%v:%v Error: process_exec failed: %v", #file, #line, err)
		os.exit(1)
	}
	defer {
		delete(stdout)
		delete(stderr)
	}
	fmt.printf("%s%s", stdout, stderr)

	if !state.success do os.exit(1)
}

Job :: struct {
	id:      int,
	process: os.Process,
	r:       ^os.File,
}

POLL_SLEEP_TIMEOUT :: 50 * time.Millisecond

wait_for_one_to_finish_and_add_job :: proc(cmd: []string) -> int {
	for {
		if len(g_state.jobs) < g_state.max_jobs {
			// add job
			r, w, perr := os.pipe()
			if perr != nil {
				fmt.printfln("%v:%v Error: %v", #file, #line, perr)
				kill_all_jobs_and_exit()
			}

			desc := os.Process_Desc {
				command = cmd,
				stderr  = w,
				stdout  = w,
			}
			process, err := os.process_start(desc)
			if err != nil {
				fmt.printfln("%v:%v Error: %v", #file, #line, err)
				kill_all_jobs_and_exit()
			}
			os.close(w)

			g_state.cur_id += 1
			append(&g_state.jobs, Job{id = g_state.cur_id, process = process, r = r})
			return g_state.cur_id
		}

		any_failed := poll_jobs()
		if any_failed do kill_all_jobs_and_exit()

		time.sleep(POLL_SLEEP_TIMEOUT)
	}
	unreachable()
}

wait_for_all_jobs_to_finish :: proc() {
	for len(g_state.jobs) > 0 {
		any_failed := poll_jobs()
		if any_failed do kill_all_jobs_and_exit()
		time.sleep(POLL_SLEEP_TIMEOUT)
	}
}

kill_all_jobs_and_exit :: proc() {
	for j in g_state.jobs {
		_ = os.process_kill(j.process)
	}
	os.exit(1)
}

@(require_results)
poll_jobs :: proc() -> (any_failed: bool) {
	#reverse for &job, i in g_state.jobs {
		// NOTE: do i need to handle the error here?
		state, _ := os.process_wait(job.process, 0)
		if state.exited {
			output, _ := os.read_entire_file(job.r, context.allocator)
			defer delete(output)
			if len(output) > 0 do fmt.printf("JOB(%d) %s", job.id, output)

			os.close(job.r)

			unordered_remove(&g_state.jobs, i)

			if !state.success {
				any_failed = true
				break
			}
		}
	}
	return
}

